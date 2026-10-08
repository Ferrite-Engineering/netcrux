// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Wire-visible state of a collaborative schematic session.
///
/// Open core owns these types because the schematic painter renders remote
/// cursors and remote selection, and the status bar shows who is in the room —
/// both open-core surfaces. The session itself is Enterprise and lives in
/// the Pro overlay; open core ships
/// `NoopSchematicCollaborationService`, which never opens a socket.
///
/// **The protocol is WaveCrux's, not a second design.** Admission and
/// end-to-end encryption are ported rather than reinvented; what differs
/// is only what the payloads carry, because a schematic is anchored by a
/// hierarchy scope and a set of element ids where a waveform is anchored by a
/// time and a row.
library;

import 'package:meta/meta.dart';

/// Network mode for a collaborative session.
enum SchematicCollabMode {
  /// Not in a session.
  none,

  /// Peer-to-peer over LAN: the host runs a WebSocket server and is the
  /// router, discovered over mDNS.
  lan,

  /// Relay-routed over WAN. The relay is a stateless router that holds no key
  /// material — see [SchematicCollabSessionState.hasUnreadableFrames].
  wan,
}

/// Whether the local participant has been admitted to the session by its host.
///
/// A session is joined in two steps: the transport connects and the joiner
/// announces itself, and only then does the **host** admit them. Until that
/// happens the joiner is connected but not a member — it adopts no room state
/// and appears in nobody's roster.
enum SchematicCollabAdmission {
  /// The local participant is a member. Always the case for the host, which
  /// admits itself.
  approved,

  /// Announced, and waiting for the host's approve-or-deny decision. The
  /// transport is up, but no room state has been adopted.
  awaitingApproval,
}

/// How the most recent join attempt ended.
///
/// Read after a join returns (and again once a pending admission resolves) so
/// the join dialog can say what actually happened rather than collapsing every
/// failure into "couldn't connect".
enum SchematicCollabJoinOutcome {
  /// No join has been attempted in this app run.
  none,

  /// Connected and admitted.
  connected,

  /// Connected and announced; the host has not yet decided.
  awaitingApproval,

  /// The host explicitly denied the request.
  denied,

  /// No decision arrived before the local deadline expired — a host who walked
  /// away, or one that dropped while the request was pending.
  timedOut,

  /// The transport never came up: relay unreachable, LAN host not found, port
  /// refused.
  connectFailed,

  /// The invite did not parse, so no socket was ever opened. A distinct
  /// outcome on purpose: an invite carries the session key, so a mistyped one
  /// is a *wrong key*, and once a socket is open a wrong key is
  /// indistinguishable from a network failure. Catching it before connecting
  /// is what lets the UI say "check the invite" instead of "check your
  /// network".
  invalidInvite,
}

/// A joiner awaiting the host's approve-or-deny admission decision.
///
/// Carried on the host's authoritative snapshot so every client converges on
/// the same pending set. Deliberately **not** a [SchematicParticipantInfo]:
/// membership of the roster *is* admission, so a pending joiner has no colour,
/// no join sequence and no cursor.
@immutable
final class SchematicCollabJoinRequest {
  /// Creates a pending join request.
  const SchematicCollabJoinRequest({
    required this.participantId,
    required this.displayName,
  });

  /// The joiner's participant id, as announced in their `hello`.
  final String participantId;

  /// The name the joiner announced. Attacker-controlled text — render it as a
  /// name, never as markup, and never treat it as identity.
  final String displayName;

  @override
  bool operator ==(Object other) =>
      other is SchematicCollabJoinRequest &&
      other.participantId == participantId &&
      other.displayName == displayName;

  @override
  int get hashCode => Object.hash(participantId, displayName);
}

/// Snapshot of one participant's visible state.
///
/// [colorIndex] is 0–7, cycling through a palette the UI layer maps to real
/// colours; the domain layer stays free of `dart:ui`.
@immutable
final class SchematicParticipantInfo {
  /// Creates a participant snapshot.
  const SchematicParticipantInfo({
    required this.id,
    required this.displayName,
    required this.colorIndex,
    required this.isHost,
    this.joinSequence = 0,
    this.scopePath = '',
    this.cursorX,
    this.cursorY,
    this.selectedElementIds = const <String>{},
    this.netlistContentHash,
  });

  /// Stable per-installation participant id.
  final String id;

  /// Name as entered in Settings ▸ Collaboration.
  final String displayName;

  /// Palette slot, 0–7.
  final int colorIndex;

  /// Whether this participant initiated the session.
  final bool isHost;

  /// Host-assigned, monotonically increasing arrival order — a **logical
  /// clock**, not a wall-clock timestamp, so it stays deterministic and
  /// skew-free across machines. Defaults to `0` for participants whose
  /// sequence has not been assigned (the no-op path never runs a session).
  final int joinSequence;

  /// The `HierarchyNode.path` of the scope this participant is viewing.
  ///
  /// **The anchor everything else hangs off.** A schematic cursor coordinate
  /// is design-space, and design space is per-scope: the same `(x, y)` means
  /// two unrelated places in two different modules. So a cursor is only drawn
  /// for participants whose [scopePath] matches the local one — showing it
  /// otherwise would put a colleague's pointer on a gate they are not looking
  /// at, which is worse than showing nothing.
  ///
  /// Empty until the participant announces a scope (no design open yet).
  final String scopePath;

  /// Design-space X of this participant's pointer, or `null` when it is
  /// outside the canvas.
  ///
  /// **Design space, never pixels.** Participants have different window sizes,
  /// zoom levels and pan offsets; a pixel coordinate would land somewhere
  /// different on every screen. This is the same "data-anchored, never pixels"
  /// rule WaveCrux's shared pointers follow.
  final double? cursorX;

  /// Design-space Y of this participant's pointer. See [cursorX].
  final double? cursorY;

  /// Ids of the elements this participant has selected, in the vocabulary the
  /// painter uses — cell ids, `cellId:portId`, `port:<name>` and edge ids.
  final Set<String> selectedElementIds;

  /// SHA-256 of the elaborated netlist this participant has loaded, or `null`
  /// if they have not reported one (nothing open, or the announcement has not
  /// arrived yet).
  ///
  /// Used by [SchematicCollabSessionState.hasNetlistMismatch] to detect a room
  /// looking at two different designs. Only the digest crosses the network.
  final String? netlistContentHash;

  /// Whether this participant has a live pointer position.
  bool get hasCursor => cursorX != null && cursorY != null;

  /// Returns a copy with the given fields replaced.
  SchematicParticipantInfo copyWith({
    String? id,
    String? displayName,
    int? colorIndex,
    bool? isHost,
    int? joinSequence,
    String? scopePath,
    double? cursorX,
    double? cursorY,
    bool clearCursor = false,
    Set<String>? selectedElementIds,
    String? netlistContentHash,
    bool clearNetlistContentHash = false,
  }) => SchematicParticipantInfo(
    id: id ?? this.id,
    displayName: displayName ?? this.displayName,
    colorIndex: colorIndex ?? this.colorIndex,
    isHost: isHost ?? this.isHost,
    joinSequence: joinSequence ?? this.joinSequence,
    scopePath: scopePath ?? this.scopePath,
    cursorX: clearCursor ? null : (cursorX ?? this.cursorX),
    cursorY: clearCursor ? null : (cursorY ?? this.cursorY),
    selectedElementIds: selectedElementIds ?? this.selectedElementIds,
    netlistContentHash: clearNetlistContentHash
        ? null
        : (netlistContentHash ?? this.netlistContentHash),
  );

  @override
  bool operator ==(Object other) =>
      other is SchematicParticipantInfo &&
      other.id == id &&
      other.displayName == displayName &&
      other.colorIndex == colorIndex &&
      other.isHost == isHost &&
      other.joinSequence == joinSequence &&
      other.scopePath == scopePath &&
      other.cursorX == cursorX &&
      other.cursorY == cursorY &&
      _sameIds(other.selectedElementIds, selectedElementIds) &&
      other.netlistContentHash == netlistContentHash;

  @override
  int get hashCode => Object.hash(
    id,
    displayName,
    colorIndex,
    isHost,
    joinSequence,
    scopePath,
    cursorX,
    cursorY,
    Object.hashAllUnordered(selectedElementIds),
    netlistContentHash,
  );

  static bool _sameIds(Set<String> a, Set<String> b) {
    if (a.length != b.length) return false;
    for (final id in a) {
      if (!b.contains(id)) return false;
    }
    return true;
  }
}

/// The presenter's camera, in design space.
///
/// **A centre and a zoom, never a pixel offset.** Participants have different
/// window sizes: the same pixel offset frames a different part of the design
/// in every window, but the design point at the centre of the canvas, at a
/// given zoom, frames the same place everywhere. Each follower converts it to
/// its own offset against its own canvas size.
@immutable
final class SchematicCollabCamera {
  /// Creates a camera centred on design point ([centerX], [centerY]).
  const SchematicCollabCamera({
    required this.centerX,
    required this.centerY,
    required this.zoom,
  });

  /// Design-space X at the centre of the presenter's canvas.
  final double centerX;

  /// Design-space Y at the centre of the presenter's canvas.
  final double centerY;

  /// The presenter's zoom.
  final double zoom;

  @override
  bool operator ==(Object other) =>
      other is SchematicCollabCamera &&
      other.centerX == centerX &&
      other.centerY == centerY &&
      other.zoom == zoom;

  @override
  int get hashCode => Object.hash(centerX, centerY, zoom);
}

/// The presenter's active trace overlay: which elements a fanin, fanout or
/// cone-of-influence trace lit, by id.
///
/// Ids only. The follower draws them over its own schematic as the presenter's
/// highlight; nothing here recomputes a trace, and the follower's own trace
/// overlay is never touched.
@immutable
final class SchematicCollabTrace {
  /// Creates a trace description.
  const SchematicCollabTrace({
    required this.cellIds,
    required this.edgeIds,
    required this.boundaryPortIds,
    this.mode,
  });

  /// `fanin` or `fanout`, by the overlay's own mode name, or `null` when the
  /// overlay carries none.
  final String? mode;

  /// Lit cell ids.
  final Set<String> cellIds;

  /// Lit edge ids.
  final Set<String> edgeIds;

  /// Lit boundary-port ids.
  final Set<String> boundaryPortIds;

  /// Every lit id, in the painter's vocabulary.
  Set<String> get allIds => {...cellIds, ...edgeIds, ...boundaryPortIds};

  @override
  bool operator ==(Object other) =>
      other is SchematicCollabTrace &&
      other.mode == mode &&
      _sameIds(other.cellIds, cellIds) &&
      _sameIds(other.edgeIds, edgeIds) &&
      _sameIds(other.boundaryPortIds, boundaryPortIds);

  @override
  int get hashCode => Object.hash(
    mode,
    Object.hashAllUnordered(cellIds),
    Object.hashAllUnordered(edgeIds),
    Object.hashAllUnordered(boundaryPortIds),
  );
}

/// What the presenter is showing: the scope, the camera and the trace overlay.
///
/// The schematic counterpart of WaveCrux's shared viewport and view
/// composition. Followers navigate to [scopePath] and frame [camera] (the
/// ephemeral focus they soft-follow), and draw [trace] over their own
/// schematic as a non-destructive overlay. The presenter's selection is not
/// repeated here: it already travels as the presenter's presence, and every
/// participant draws it.
///
/// Published only by the presenter; a frame from anyone else is dropped, and
/// the value is cleared whenever the presenter token moves.
@immutable
final class SchematicCollabPresenterView {
  /// Creates a presenter view.
  const SchematicCollabPresenterView({
    required this.scopePath,
    this.camera,
    this.trace,
  });

  /// The presenter's scope, as `collabScopePath` spells it. Empty for the top
  /// of the design.
  final String scopePath;

  /// The presenter's camera, or `null` before their canvas has laid out.
  final SchematicCollabCamera? camera;

  /// The presenter's active trace overlay, or `null` when none is showing.
  final SchematicCollabTrace? trace;

  @override
  bool operator ==(Object other) =>
      other is SchematicCollabPresenterView &&
      other.scopePath == scopePath &&
      other.camera == camera &&
      other.trace == trace;

  @override
  int get hashCode => Object.hash(scopePath, camera, trace);
}

bool _sameIds(Set<String> a, Set<String> b) {
  if (a.length != b.length) return false;
  for (final id in a) {
    if (!b.contains(id)) return false;
  }
  return true;
}

/// Complete state broadcast by the session on every roster, cursor or
/// selection change.
@immutable
final class SchematicCollabSessionState {
  /// Creates a session snapshot.
  const SchematicCollabSessionState({
    required this.sessionId,
    required this.myParticipantId,
    required this.hostId,
    required this.mode,
    this.participants = const <SchematicParticipantInfo>[],
    this.pendingJoinRequests = const <SchematicCollabJoinRequest>[],
    this.admission = SchematicCollabAdmission.approved,
    this.hasUnreadableFrames = false,
    this.followTargetId,
    this.presenterId,
    this.pendingControlRequests = const <String>[],
    this.presenterView,
  });

  /// The room code (WAN) or host-minted session id (LAN).
  final String sessionId;

  /// This installation's participant id.
  final String myParticipantId;

  /// The session initiator. Owns the room, ends it, and is the single
  /// admission authority.
  final String hostId;

  /// Which transport this session runs over.
  final SchematicCollabMode mode;

  /// Everyone admitted to the room, including the local participant.
  final List<SchematicParticipantInfo> participants;

  /// Joiners awaiting the host's admission decision. Always empty on a client
  /// that is not the host until the host's snapshot carries them.
  final List<SchematicCollabJoinRequest> pendingJoinRequests;

  /// Whether the **local** participant has been admitted.
  final SchematicCollabAdmission admission;

  /// Whether frames have arrived that this session's key cannot open —
  /// in practice, someone in the room holding the wrong invite.
  ///
  /// Surfaced rather than swallowed: from the other side the symptom is a
  /// session that connects and then does nothing, and silence would leave both
  /// people who could fix it with no information. Always `false` on LAN, which
  /// has no key.
  final bool hasUnreadableFrames;

  /// The participant whose scope changes this client follows, or `null` when
  /// not following anyone.
  final String? followTargetId;

  /// Who holds the presenter token, or `null` for "the host" — presenter
  /// defaults to host until the first handoff. Read [effectivePresenterId].
  final String? presenterId;

  /// Participants who have asked to present and are waiting for the host or
  /// the presenter to decide.
  final List<String> pendingControlRequests;

  /// What the presenter is showing, or `null` before they have published it.
  final SchematicCollabPresenterView? presenterView;

  /// Who is presenting, resolving the "defaults to the host" rule.
  String get effectivePresenterId => presenterId ?? hostId;

  /// Whether the local participant holds the presenter token.
  bool get isLocalPresenter => effectivePresenterId == myParticipantId;

  /// The presenting participant, or `null` while the roster has not caught up.
  SchematicParticipantInfo? get presenter => participant(effectivePresenterId);

  /// Whether the local participant is the session host.
  bool get isLocalHost => hostId == myParticipantId;

  /// Whether anyone is waiting at the door.
  bool get hasPendingJoinRequests => pendingJoinRequests.isNotEmpty;

  /// Whether the local participant is connected but not yet admitted.
  bool get isAwaitingAdmission =>
      admission == SchematicCollabAdmission.awaitingApproval;

  /// The distinct netlist hashes reported across all participants.
  ///
  /// Participants who have not announced one contribute nothing — they are
  /// never treated as a difference, only as "unknown".
  Set<String> get reportedNetlistHashes => {
    for (final p in participants)
      if (p.netlistContentHash != null) p.netlistContentHash!,
  };

  /// Whether participants who *have* reported a netlist disagree — i.e. at
  /// least two different designs are open in the room.
  ///
  /// Returns `false` while only one (or zero) hashes are known, so the brief
  /// window before every participant's identity propagates does not flash a
  /// false warning.
  bool get hasNetlistMismatch => reportedNetlistHashes.length > 1;

  /// The participant with [id], or `null` when they are not in the roster.
  SchematicParticipantInfo? participant(String id) {
    for (final p in participants) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Returns a copy with the given fields replaced.
  SchematicCollabSessionState copyWith({
    String? sessionId,
    String? myParticipantId,
    String? hostId,
    SchematicCollabMode? mode,
    List<SchematicParticipantInfo>? participants,
    List<SchematicCollabJoinRequest>? pendingJoinRequests,
    SchematicCollabAdmission? admission,
    bool? hasUnreadableFrames,
    String? followTargetId,
    bool clearFollowTarget = false,
    String? presenterId,
    List<String>? pendingControlRequests,
    SchematicCollabPresenterView? presenterView,
    bool clearPresenterView = false,
  }) => SchematicCollabSessionState(
    sessionId: sessionId ?? this.sessionId,
    myParticipantId: myParticipantId ?? this.myParticipantId,
    hostId: hostId ?? this.hostId,
    mode: mode ?? this.mode,
    participants: participants ?? this.participants,
    pendingJoinRequests: pendingJoinRequests ?? this.pendingJoinRequests,
    admission: admission ?? this.admission,
    hasUnreadableFrames: hasUnreadableFrames ?? this.hasUnreadableFrames,
    followTargetId: clearFollowTarget
        ? null
        : (followTargetId ?? this.followTargetId),
    presenterId: presenterId ?? this.presenterId,
    pendingControlRequests:
        pendingControlRequests ?? this.pendingControlRequests,
    presenterView: clearPresenterView
        ? null
        : (presenterView ?? this.presenterView),
  );

  @override
  bool operator ==(Object other) =>
      other is SchematicCollabSessionState &&
      other.sessionId == sessionId &&
      other.myParticipantId == myParticipantId &&
      other.hostId == hostId &&
      other.mode == mode &&
      _sameList(other.participants, participants) &&
      _sameList(other.pendingJoinRequests, pendingJoinRequests) &&
      other.admission == admission &&
      other.hasUnreadableFrames == hasUnreadableFrames &&
      other.followTargetId == followTargetId &&
      other.presenterId == presenterId &&
      _sameList(other.pendingControlRequests, pendingControlRequests) &&
      other.presenterView == presenterView;

  @override
  int get hashCode => Object.hash(
    sessionId,
    myParticipantId,
    hostId,
    mode,
    Object.hashAll(participants),
    Object.hashAll(pendingJoinRequests),
    admission,
    hasUnreadableFrames,
    followTargetId,
    presenterId,
    Object.hashAll(pendingControlRequests),
    presenterView,
  );

  static bool _sameList<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
