// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/core/theme/collaborator_palette.dart';
import 'package:netcrux/domain/interfaces/bookmark_annotation_store.dart';
import 'package:netcrux/domain/models/annotation.dart';
import 'package:netcrux/domain/models/collaboration/schematic_collab_session.dart';
import 'package:netcrux/features/bookmarks/providers/annotation_writing_provider.dart';
import 'package:netcrux/features/collaboration/collab_annotation_adoption.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/collaboration/schematic_collaboration_service_provider.dart';
import 'package:netcrux/services/session/bookmark_annotation_state.dart';
import 'package:netcrux/services/session/bookmark_annotation_store_provider.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_notifier.dart';

/// The session layer id for a collaborative session: the same for every
/// participant, so a note keeps one layer on every machine it reaches.
String collabSessionLayerId(String sessionId) => 'session:$sessionId';

/// Notes written during a collaborative session travel; notes that predate it
/// never do. One tab's half of that, mounted inside each tab's provider scope.
///
/// Only the **active** tab takes part, as with presenter mode. When it first
/// takes part in a session it takes a **baseline**: every note already in the
/// tab. Those never publish, whatever happens to them during the session — a
/// participant's private notes are theirs, not the meeting's.
///
/// * **Out.** A note written in the tab during the session is stamped with the
///   session's layer, the author's participant id and the author's colour
///   (frozen as a colour, not a palette slot), then published. Editing it
///   republishes; deleting it withdraws it.
/// * **In.** Notes others wrote arrive in the tab's own annotation store, in
///   the session's layer, so they show in the Annotations panel and badge the
///   schematic like any note. Edited or withdrawn by their author (or
///   withdrawn by the host), they change or go here too.
/// * **Rights.** Somebody else's note is not edited here while their name is
///   on it: an edit is put back. Deleting it removes it from this tab only,
///   unless we host, when it withdraws it for everyone. The service checks the
///   same rights again on every frame it receives, from the frame's sender.
/// * **Writing.** While the annotation dialog is open the room is told we are
///   writing a note — a boolean, never the text.
/// * **At the end.** If the session left notes in this tab, an offer goes up
///   (`collabAdoptionOfferProvider`): keep all, keep only mine, or discard.
///   Dismissing it keeps all.
///
/// No tier is consulted anywhere: a guest's notes travel like anyone's.
class CollabAnnotationSync extends ConsumerStatefulWidget {
  /// Wraps [child], the tab's content.
  const CollabAnnotationSync({required this.child, super.key});

  /// The tab content.
  final Widget child;

  @override
  ConsumerState<CollabAnnotationSync> createState() =>
      _CollabAnnotationSyncState();
}

class _CollabAnnotationSyncState extends ConsumerState<CollabAnnotationSync> {
  /// The session this tab is taking part in, and who we are in it.
  String? _layerId;
  String? _layerLabel;
  String? _myId;
  bool _amHost = false;
  String _myName = '';
  int _myColorArgb = 0;

  /// Notes in the tab when it began taking part. Never published.
  final Set<String> _baseline = {};

  /// Our notes as last published, by id.
  final Map<String, Annotation> _published = {};

  /// Others' notes as last received, by id.
  final Map<String, Annotation> _received = {};

  /// Others' notes deleted here (without hosting), at the version that was
  /// deleted: not re-added unless their author changes them.
  final Map<String, Annotation> _dismissed = {};

  /// Our published notes the room has been seen to hold. Only these can be
  /// read as withdrawn by the host when they go missing: a note just
  /// published is absent from a state emitted a moment before it was.
  final Set<String> _acknowledged = {};

  /// Set while this widget writes received notes into the store, so the
  /// store listener does not mistake them for local edits.
  bool _applying = false;

  late final TabId? _tabId = _readTabId();

  TabId? _readTabId() {
    try {
      return ref.read(tabIdProvider);
    } on Object {
      return null;
    }
  }

  bool get _isActiveTab {
    final tab = _tabId;
    if (tab == null) return true;
    return ref.read(netcruxWorkspaceProvider).value?.activeTabId == tab;
  }

  BookmarkAnnotationStore get _store =>
      ref.read(bookmarkAnnotationStoreProvider);

  List<Annotation> get _notes =>
      ref.read(bookmarkAnnotationStateProvider).annotations;

  @override
  Widget build(BuildContext context) {
    if (_tabId != null) {
      ref.listen(netcruxWorkspaceProvider, (previous, next) {
        final was = previous?.value?.activeTabId;
        final now = next.value?.activeTabId;
        if (was == now || !_isActiveTab) return;
        final session = ref.read(schematicCollabSessionProvider).value;
        if (session != null) _onSession(session);
      });
    }
    ref
      ..listen(schematicCollabSessionProvider, (previous, next) {
        final session = next.value;
        if (session == null) {
          if (previous?.value != null) _onSessionEnded();
          return;
        }
        _onSession(session);
      })
      ..listen(
        bookmarkAnnotationStateProvider,
        (previous, next) => _onLocalNotes(),
      )
      ..listen(annotationWritingProvider, (previous, writing) {
        if (_layerId == null || !_isActiveTab) return;
        ref
            .read(schematicCollaborationServiceProvider)
            .setWritingNote(writing: writing);
      });
    return widget.child;
  }

  // ── session ────────────────────────────────────────────────────────────────

  void _onSession(SchematicCollabSessionState session) {
    if (session.isAwaitingAdmission || !_isActiveTab) return;
    final me = session.participant(session.myParticipantId);
    if (me == null) return;
    final layerId = collabSessionLayerId(session.sessionId);
    if (_layerId != layerId) _begin(session, layerId);
    _amHost = session.isLocalHost;
    _myName = me.displayName;
    _myColorArgb = collaboratorColor(me.colorIndex).toARGB32();
    _applyReceived(session);
  }

  void _begin(SchematicCollabSessionState session, String layerId) {
    _layerId = layerId;
    _myId = session.myParticipantId;
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    _layerLabel = L10N
        .of(context)
        .annotationSessionLayerLabel(
          session.sessionId,
          '${now.year}-${two(now.month)}-${two(now.day)}',
        );
    _baseline
      ..clear()
      ..addAll(_notes.map((n) => n.id));
    _published.clear();
    _received.clear();
    _dismissed.clear();
    _acknowledged.clear();
  }

  void _onSessionEnded() {
    final layerId = _layerId;
    final myId = _myId;
    _layerId = null;
    _myId = null;
    if (layerId == null || myId == null) return;
    final inLayer = [
      for (final n in _notes)
        if (n.sessionLayerId == layerId) n,
    ];
    if (inLayer.isEmpty) return;
    ref
        .read(collabAdoptionOfferProvider.notifier)
        .offer(
          CollabAdoptionOffer(
            layerId: layerId,
            noteCount: inLayer.length,
            authorCount: {for (final n in inLayer) n.authorId ?? myId}.length,
            apply: (choice) {
              if (!mounted) return;
              final adopted = adoptSessionLayer(
                _notes,
                layerId: layerId,
                myId: myId,
                choice: choice,
              );
              ref
                  .read(bookmarkAnnotationStateProvider.notifier)
                  .setAnnotations(adopted);
            },
          ),
        );
  }

  // ── out: local notes to the room ───────────────────────────────────────────

  void _onLocalNotes() {
    final layerId = _layerId;
    final myId = _myId;
    if (_applying || layerId == null || myId == null || !_isActiveTab) return;
    final service = ref.read(schematicCollaborationServiceProvider);
    final present = <String>{};
    for (final note in _notes) {
      present.add(note.id);
      if (_baseline.contains(note.id)) continue;
      if (note.sessionLayerId == null) {
        // Written here, during the session: it becomes the meeting's. The
        // stamp goes into the store, which notifies again and publishes.
        _store.updateAnnotation(
          note.copyWith(
            sessionLayerId: layerId,
            sessionLayerLabel: _layerLabel,
            authorId: myId,
            colorArgb: _myColorArgb,
            author: note.author ?? _myName,
          ),
        );
        return;
      }
      if (note.sessionLayerId != layerId) continue;
      if (note.authorId == myId) {
        if (_published[note.id] != note) {
          _published[note.id] = note;
          service.publishAnnotation(note);
        }
        continue;
      }
      // Somebody else's: attribution is read-only, so an edit is put back.
      final received = _received[note.id];
      if (received != null && received != note) {
        _applying = true;
        try {
          _store.updateAnnotation(received);
        } finally {
          _applying = false;
        }
      }
    }
    for (final id in _published.keys.toList()) {
      if (present.contains(id)) continue;
      _published.remove(id);
      service.withdrawAnnotation(id);
    }
    for (final id in _received.keys.toList()) {
      if (present.contains(id)) continue;
      // Deleted here. A host's deletion is moderation, for everyone; anyone
      // else's removes it from their own tab only.
      final version = _received.remove(id);
      if (version != null) _dismissed[id] = version;
      if (_amHost) service.withdrawAnnotation(id);
    }
  }

  // ── in: the room's notes to this tab ───────────────────────────────────────

  void _applyReceived(SchematicCollabSessionState session) {
    final myId = _myId;
    if (myId == null) return;
    final shared = {for (final n in session.sharedAnnotations) n.id: n};
    final notes = _notes;
    final byId = {for (final n in notes) n.id: n};
    _applying = true;
    try {
      for (final note in shared.values) {
        if (note.authorId == myId) {
          _acknowledged.add(note.id);
          continue;
        }
        if (_received[note.id] == note) continue;
        // A note deleted here comes back only if its author changes it.
        final dismissedAt = _dismissed[note.id];
        if (dismissedAt != null) {
          if (dismissedAt == note) continue;
          _dismissed.remove(note.id);
        }
        _received[note.id] = note;
        if (byId.containsKey(note.id)) {
          _store.updateAnnotation(note);
        } else {
          _store.addAnnotation(note);
        }
      }
      // Withdrawn by their author or the host.
      for (final id in _received.keys.toList()) {
        if (shared.containsKey(id)) continue;
        _received.remove(id);
        _store.removeAnnotation(id);
      }
      _dismissed.removeWhere((id, _) => !shared.containsKey(id));
      // Ours, withdrawn by the host: once seen in the room, now gone.
      for (final id in _acknowledged.toList()) {
        if (shared.containsKey(id)) continue;
        _acknowledged.remove(id);
        _published.remove(id);
        _store.removeAnnotation(id);
      }
    } finally {
      _applying = false;
    }
  }
}
