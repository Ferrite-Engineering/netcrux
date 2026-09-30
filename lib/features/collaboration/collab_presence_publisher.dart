// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// The open-core half of collaborative presence: turning what this user is
/// doing into something the session can broadcast.
///
/// The session itself is Enterprise and lives in the Pro overlay. What lives
/// here is the *reading* of local state — the pointer position, the selection,
/// the scope on screen — because all three are open-core providers and a Pro
/// service reaching into a per-tab widget scope to read them would be answering
/// a UI question from inside a transport.
///
/// Every function here is a no-op when no session is running, because
/// [NoopSchematicCollaborationService] ignores everything it is handed. That is
/// deliberate: the call sites run identically in an open-core build and a Pro
/// one, so the seam is exercised by every test in the repo rather than only by
/// the ones that install a Pro overlay.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/interfaces/schematic_collaboration_service.dart';
import 'package:netcrux/domain/models/netlist/hierarchy_node.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/domain/models/selection/selection.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/viewer/rendering/schematic_painter.dart';
import 'package:netcrux/services/collaboration/schematic_collaboration_service_provider.dart';

/// The painter's id for [element], or `null` for the none sentinel.
///
/// One function, because the painter, the hit-tester and the wire all have to
/// agree on what an element is called and three separate spellings of that
/// agreement is how a remote selection ends up outlining the wrong thing.
String? collabElementId(SelectedElement element) => switch (element) {
  SelectedElementNone() => null,
  SelectedElementCell(:final cellId) => cellId,
  // Already `<cellName>:<portName>`, which is the key
  // `NodePosition.ports` is indexed by.
  SelectedElementPort(:final portId) => portId,
  SelectedElementBoundaryPort(:final portId) => portId,
  SelectedElementWire(:final edgeId) => edgeId,
};

/// Every id in [selection], in the painter's vocabulary.
Set<String> collabElementIds(Selection selection) => {
  for (final element in selection.elements) ?collabElementId(element),
};

/// The canonical wire spelling of a hierarchy scope.
///
/// [HierarchyNode.path] is a `List<String>` of instance names; the wire wants
/// one comparable token. Joined with `/` because an instance name cannot
/// contain one — a dot can, inside a generate block — so the join is
/// unambiguous and two participants inside the same scope always produce the
/// same string.
///
/// The empty string means "no scope selected", which is what a participant
/// with nothing open reports.
String collabScopePath(HierarchyNode? node) => node?.path.join('/') ?? '';

/// Converts a canvas-local pointer position into design space under
/// [transform].
///
/// **Design space, not pixels**, and this conversion is the reason: every
/// participant has a different window size, zoom and pan, so a pixel
/// coordinate would land on a different gate on every screen. Mirrors
/// `SchematicHitTester._toDesign` — the same inversion the click path uses, so
/// a pointer and a click resolve to the same place.
Offset collabDesignPoint(Offset localPosition, ViewportTransform transform) {
  if (transform.zoom == 0) return localPosition;
  return (localPosition - transform.offset) / transform.zoom;
}

/// Publishes the local pointer at [designPoint], or clears it when `null`.
///
/// [scopePath] anchors the coordinate: the same `(x, y)` is two unrelated
/// places in two different modules, so a cursor without a scope is a cursor
/// nobody can place.
void publishCollabCursor(
  WidgetRef ref, {
  required Offset? designPoint,
}) {
  final service = ref.read(schematicCollaborationServiceProvider);
  if (!service.isInSession) return;
  service.updateCursor(
    scopePath: collabScopePath(ref.read(hierarchyTreeProvider).selected),
    x: designPoint?.dx,
    y: designPoint?.dy,
  );
}

/// Publishes [selection] for the scope currently on screen.
void publishCollabSelection(WidgetRef ref, Selection selection) {
  final service = ref.read(schematicCollaborationServiceProvider);
  if (!service.isInSession) return;
  service.updateSelection(
    scopePath: collabScopePath(ref.read(hierarchyTreeProvider).selected),
    elementIds: collabElementIds(selection),
  );
}
