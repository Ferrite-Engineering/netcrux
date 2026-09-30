// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';
import 'package:netcrux/domain/models/schematic/laid_out_graph.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/features/viewer/rendering/schematic_painter.dart';
import 'package:netcrux/features/viewer/rendering/schematic_scene_index.dart';

/// Pure hit-tester for schematic elements.
///
/// Takes a viewport-local pointer position, converts it into design-space
/// coordinates by inverting the [ViewportTransform], and asks the
/// [LaidOutGraph] which element (if any) lives at that point.
///
/// Lives in its own file so the gesture handler and the painter can both
/// consume it without dragging in each other's surface. The selection
/// notifier never calls back into the render object.
class SchematicHitTester {
  /// Creates a hit-tester for [laidOut] under [transform].
  const SchematicHitTester({
    required this.laidOut,
    required this.transform,
    this.wireSlop = 6,
  });

  /// The graph currently painted on the canvas.
  final LaidOutGraph laidOut;

  /// The viewport transform applied at paint time.
  final ViewportTransform transform;

  /// Extra padding in design-space pixels around a wire polyline for
  /// touch friendliness. Cells and ports use their declared bounds
  /// directly because they are large enough to hit reliably.
  final double wireSlop;

  /// Returns the [SelectedElement] hit by [viewportPoint], or
  /// [const SelectedElement.none()] when the click lands on empty
  /// canvas. Hit-test order: ports first (smallest), then cell bodies,
  /// then wires (with slop), then boundary ports — earlier hits win.
  SelectedElement hitTest(Offset viewportPoint) {
    final designPoint = _toDesign(viewportPoint);
    if (laidOut.isEmpty) return const SelectedElement.none();

    // Each pass asks the scene index for the few elements near the click,
    // in scope order, and applies the same exact test the full scan did —
    // so the first element that passes is the one the scan would have
    // returned. See [SchematicSceneIndex].
    final scene = SchematicSceneIndex.of(laidOut);

    // 1. Ports on cells (small, drawn last).
    final pins = scene.pinsIn(
      SchematicSceneIndex.around(designPoint, _portSlop),
    );
    final pinCount = pins?.length ?? scene.pins.length;
    for (var k = 0; k < pinCount; k++) {
      final i = pins == null ? k : pins[k];
      final owner = scene.pinCell[i];
      final position = scene.cellNodes[owner];
      final box = scene.pinBoxes[i];
      final cx = position.bounds.x + box.x;
      final cy = position.bounds.y + box.y;
      final rect = Rect.fromLTWH(
        cx,
        cy,
        box.width,
        box.height,
      ).inflate(_portSlop);
      if (rect.contains(designPoint)) {
        final port = scene.pins[i];
        return SelectedElement.port(
          cellId: scene.cells[owner].id,
          portId: port.id,
          portName: port.name,
        );
      }
    }

    // 2. Cell bodies.
    final cells = scene.cellsIn(SchematicSceneIndex.around(designPoint, 0));
    final cellCount = cells?.length ?? scene.cells.length;
    for (var k = 0; k < cellCount; k++) {
      final i = cells == null ? k : cells[k];
      final position = scene.cellNodes[i];
      final rect = Rect.fromLTWH(
        position.bounds.x,
        position.bounds.y,
        position.bounds.width,
        position.bounds.height,
      );
      if (rect.contains(designPoint)) {
        return SelectedElement.cell(cellId: scene.cells[i].id);
      }
    }

    // 3. Boundary ports.
    final boundary = scene.boundaryPortsIn(
      SchematicSceneIndex.around(designPoint, _portSlop),
    );
    final boundaryCount = boundary?.length ?? scene.boundaryPorts.length;
    for (var k = 0; k < boundaryCount; k++) {
      final i = boundary == null ? k : boundary[k];
      final position = scene.boundaryPortNodes[i];
      final rect = Rect.fromLTWH(
        position.bounds.x,
        position.bounds.y,
        position.bounds.width,
        position.bounds.height,
      ).inflate(_portSlop);
      if (rect.contains(designPoint)) {
        final port = scene.boundaryPorts[i];
        return SelectedElement.boundaryPort(
          portId: port.id,
          portName: port.name,
        );
      }
    }

    // 4. Wires (polyline distance with slop).
    final wires = scene.wiresNear(designPoint, wireSlop);
    final wireCount = wires?.length ?? scene.wires.length;
    for (var k = 0; k < wireCount; k++) {
      final edge = scene.wires[wires == null ? k : wires[k]];
      for (var i = 0; i + 1 < edge.points.length; i++) {
        final a = Offset(edge.points[i].x, edge.points[i].y);
        final b = Offset(edge.points[i + 1].x, edge.points[i + 1].y);
        if (_distanceToSegment(designPoint, a, b) <= wireSlop) {
          // The net id is encoded in the laid-out edge id itself
          // ([EdgeRoute.netId]); prefer it. `graph.findEdge` is only a
          // fallback for the rare hand-authored id that carries no net
          // id — and it can miss entirely, because the laid-out edge ids
          // and the schematic-graph edge ids are numbered by independent
          // counters. Keeping the net id correct here is what arms the
          // outbound cross-probe with the right net name after a click.
          final netId =
              edge.netId ?? laidOut.graph.findEdge(edge.id)?.netId ?? -1;
          return SelectedElement.wire(edgeId: edge.id, netId: netId);
        }
      }
    }

    return const SelectedElement.none();
  }

  /// Inverts [transform] so a screen-space [Offset] maps to design space.
  Offset _toDesign(Offset viewportPoint) {
    if (transform.zoom == 0) return viewportPoint;
    return (viewportPoint - transform.offset) / transform.zoom;
  }

  /// Per-port slop in design units. Tight because pin stubs are small
  /// and we want clicks intended for the cell body to fall through.
  static const double _portSlop = 4;

  /// Minimum perpendicular distance from [p] to segment [a]–[b].
  static double _distanceToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final lenSq = ab.dx * ab.dx + ab.dy * ab.dy;
    if (lenSq == 0) return (p - a).distance;
    var t = ((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / lenSq;
    if (t < 0) t = 0;
    if (t > 1) t = 1;
    final closest = a + ab * t;
    return (p - closest).distance;
  }
}
