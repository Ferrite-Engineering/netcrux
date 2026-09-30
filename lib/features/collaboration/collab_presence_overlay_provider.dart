// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart' show Color;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:netcrux/core/theme/collaborator_palette.dart';
import 'package:netcrux/domain/models/collaboration/schematic_collab_session.dart';
import 'package:netcrux/features/collaboration/collab_presence_publisher.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/services/collaboration/schematic_collaboration_service_provider.dart';

/// One remote participant's pointer, in design space.
@immutable
class CollabPresenceCursor {
  /// Creates a remote cursor.
  const CollabPresenceCursor({
    required this.participantId,
    required this.label,
    required this.color,
    required this.x,
    required this.y,
  });

  /// Who this cursor belongs to.
  final String participantId;

  /// Their display name, drawn beside the pointer. **Peer-supplied text** —
  /// render it as a string, never as markup.
  final String label;

  /// Their palette colour.
  final Color color;

  /// Design-space X. Design space, not pixels: the painter applies the local
  /// viewport transform, so the pointer lands on the same gate on every screen
  /// regardless of pan and zoom.
  final double x;

  /// Design-space Y. See [x].
  final double y;

  @override
  bool operator ==(Object other) =>
      other is CollabPresenceCursor &&
      other.participantId == participantId &&
      other.label == label &&
      other.color == color &&
      other.x == x &&
      other.y == y;

  @override
  int get hashCode => Object.hash(participantId, label, color, x, y);
}

/// What the schematic painter draws for the other people in the room.
///
/// A painter-facing projection of [SchematicCollabSessionState], deliberately
/// narrower than the session itself: the canvas needs pointers and highlighted
/// element ids and nothing else, and handing it the whole session would couple
/// the render path to admission, invites and transport state it has no business
/// knowing about.
///
/// **Already filtered to the local scope.** A design-space coordinate only
/// means something inside one hierarchy scope; the same `(x, y)` is two
/// unrelated places in two modules. Participants viewing a different scope
/// contribute nothing here — see [collabPresenceOverlayProvider].
@immutable
class CollabPresenceOverlay {
  /// Creates a presence overlay.
  const CollabPresenceOverlay({
    required this.cursors,
    required this.selectionColors,
  });

  /// Nothing to draw. `isEmpty` is true and the painter treats this exactly as
  /// it treats `null`.
  static const CollabPresenceOverlay empty = CollabPresenceOverlay(
    cursors: <CollabPresenceCursor>[],
    selectionColors: <String, Color>{},
  );

  /// Remote pointers, one per participant who has one inside this scope.
  final List<CollabPresenceCursor> cursors;

  /// Element id → the colour of the participant who has it selected.
  ///
  /// Ids are the painter's own vocabulary: cell ids, `cellId:portId`,
  /// `port:<name>`, and edge ids. When two participants have selected the same
  /// element the lowest `colorIndex` wins, so the outline is stable rather than
  /// flickering between two colours as snapshots arrive.
  final Map<String, Color> selectionColors;

  /// True when there is nothing to paint.
  bool get isEmpty => cursors.isEmpty && selectionColors.isEmpty;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! CollabPresenceOverlay) return false;
    if (other.cursors.length != cursors.length) return false;
    for (var i = 0; i < cursors.length; i++) {
      if (other.cursors[i] != cursors[i]) return false;
    }
    if (other.selectionColors.length != selectionColors.length) return false;
    for (final entry in selectionColors.entries) {
      if (other.selectionColors[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    Object.hashAll(cursors),
    Object.hashAllUnordered(
      selectionColors.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );
}

/// What the schematic canvas draws for the other participants, or `null` when
/// no session is running.
///
/// Derived in **open core** rather than published by the Pro overlay, unlike
/// [schematicCrossingOverlayProvider] and [netActivityColorOverrideProvider].
/// The difference is where the scope filter belongs: it needs
/// [hierarchyTreeProvider], which is per-tab open-core state, and a session
/// service that reached into the widget tree's tab scope to read it would be
/// answering a rendering question from inside the transport. The Pro overlay
/// supplies the *session*; open core decides what of it is on screen.
///
/// Returns `null` — not [CollabPresenceOverlay.empty] — when there is no
/// session, so the painter branches off a null check instead of walking empty
/// collections every frame.
final collabPresenceOverlayProvider = Provider<CollabPresenceOverlay?>(
  collabPresenceOverlay,
  name: 'collabPresenceOverlayProvider',
);

/// Builds the presence overlay for the scope on screen.
///
/// A named top-level function rather than a closure so
/// `netcruxTabOverridesFactory` can re-bind it per tab —
/// `.overrideWith(collabPresenceOverlay)`. That re-binding is not optional: the
/// scope filter reads `hierarchyTreeProvider`, which is per-tab, and at root it
/// would compare every peer against an empty scope and paint nothing.
CollabPresenceOverlay? collabPresenceOverlay(Ref ref) {
  final session = ref.watch(schematicCollabSessionProvider).value;
  if (session == null) return null;
  // Awaiting the host's decision means we are connected but not a member; a
  // roster we have not been admitted to is not ours to render.
  if (session.isAwaitingAdmission) return null;

  // Through the canonical helper, never `selected?.path ?? ''`: `path` is a
  // `List<String>`, so that expression types as `Object`, every `!=` against a
  // wire string is true, and NOTHING remote ever renders — silently, with no
  // analyzer complaint. `collab_presence_overlay_provider_test.dart` is what
  // found it.
  final scopePath = collabScopePath(
    ref.watch(hierarchyTreeProvider).selected,
  );

  final cursors = <CollabPresenceCursor>[];
  final selectionColors = <String, Color>{};
  final claimedBy = <String, int>{};

  for (final p in session.participants) {
    if (p.id == session.myParticipantId) continue;
    // A participant in another module contributes nothing: their coordinates
    // and element ids belong to a different design space.
    if (p.scopePath != scopePath) continue;

    final color = collaboratorColor(p.colorIndex);
    if (p.hasCursor) {
      cursors.add(
        CollabPresenceCursor(
          participantId: p.id,
          label: p.displayName,
          color: color,
          x: p.cursorX!,
          y: p.cursorY!,
        ),
      );
    }
    for (final id in p.selectedElementIds) {
      final claimed = claimedBy[id];
      if (claimed != null && claimed <= p.colorIndex) continue;
      claimedBy[id] = p.colorIndex;
      selectionColors[id] = color;
    }
  }

  if (cursors.isEmpty && selectionColors.isEmpty) return null;
  return CollabPresenceOverlay(
    cursors: cursors,
    selectionColors: selectionColors,
  );
}
