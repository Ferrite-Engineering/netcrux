// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:math';
import 'dart:ui';

import 'package:netcrux/domain/models/layout/bounding_box.dart';
import 'package:netcrux/domain/models/layout/edge_route.dart';
import 'package:netcrux/domain/models/layout/netlist_layout.dart';
import 'package:netcrux/domain/models/layout/node_position.dart';
import 'package:netcrux/domain/models/netlist/port_direction.dart';
import 'package:netcrux/domain/models/schematic/cell_kind.dart';
import 'package:netcrux/domain/models/schematic/laid_out_graph.dart';
import 'package:netcrux/domain/models/schematic/schematic_graph.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/features/viewer/rendering/schematic_painter.dart';

// The scene's former full scans, kept verbatim as the oracles the scene
// index is proven against: the hit-test that scanned every pin, cell,
// module port and wire per click, the painter's per-frame cull, and the
// keyboard navigator's per-keypress lookups.

/// The hit-test as it was before the scene index.
SelectedElement referenceHitTest(
  LaidOutGraph laidOut,
  ViewportTransform transform,
  Offset viewportPoint, {
  double wireSlop = 6,
}) {
  const portSlop = 4.0;
  final designPoint = transform.zoom == 0
      ? viewportPoint
      : (viewportPoint - transform.offset) / transform.zoom;
  if (laidOut.isEmpty) return const SelectedElement.none();

  for (final cell in laidOut.graph.cells) {
    final position = laidOut.layout.findNode(cell.id);
    if (position == null) continue;
    for (final port in cell.ports) {
      final box = position.ports[port.id];
      if (box == null) continue;
      final cx = position.bounds.x + box.x;
      final cy = position.bounds.y + box.y;
      final rect = Rect.fromLTWH(
        cx,
        cy,
        box.width,
        box.height,
      ).inflate(portSlop);
      if (rect.contains(designPoint)) {
        return SelectedElement.port(
          cellId: cell.id,
          portId: port.id,
          portName: port.name,
        );
      }
    }
  }

  for (final cell in laidOut.graph.cells) {
    final position = laidOut.layout.findNode(cell.id);
    if (position == null) continue;
    final rect = Rect.fromLTWH(
      position.bounds.x,
      position.bounds.y,
      position.bounds.width,
      position.bounds.height,
    );
    if (rect.contains(designPoint)) {
      return SelectedElement.cell(cellId: cell.id);
    }
  }

  for (final port in laidOut.graph.boundaryPorts) {
    final position = laidOut.layout.findNode(port.id);
    if (position == null) continue;
    final rect = Rect.fromLTWH(
      position.bounds.x,
      position.bounds.y,
      position.bounds.width,
      position.bounds.height,
    ).inflate(portSlop);
    if (rect.contains(designPoint)) {
      return SelectedElement.boundaryPort(
        portId: port.id,
        portName: port.name,
      );
    }
  }

  for (final edge in laidOut.layout.edges) {
    if (edge.points.length < 2) continue;
    for (var i = 0; i + 1 < edge.points.length; i++) {
      final a = Offset(edge.points[i].x, edge.points[i].y);
      final b = Offset(edge.points[i + 1].x, edge.points[i + 1].y);
      if (_distanceToSegment(designPoint, a, b) <= wireSlop) {
        final netId =
            edge.netId ?? laidOut.graph.findEdge(edge.id)?.netId ?? -1;
        return SelectedElement.wire(edgeId: edge.id, netId: netId);
      }
    }
  }

  return const SelectedElement.none();
}

double _distanceToSegment(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final lenSq = ab.dx * ab.dx + ab.dy * ab.dy;
  if (lenSq == 0) return (p - a).distance;
  var t = ((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / lenSq;
  if (t < 0) t = 0;
  if (t > 1) t = 1;
  final closest = a + ab * t;
  return (p - closest).distance;
}

/// How many cells and wires the painter's former full-scan cull let
/// through for [visible] — the counts it reported as visible.
({int cells, int wires}) referenceCull(LaidOutGraph laidOut, Rect visible) {
  var cells = 0;
  for (final cell in laidOut.graph.cells) {
    final position = laidOut.layout.findNode(cell.id);
    if (position == null) continue;
    final rect = Rect.fromLTWH(
      position.bounds.x,
      position.bounds.y,
      position.bounds.width,
      position.bounds.height,
    );
    if (visible.overlaps(rect)) cells++;
  }
  var wires = 0;
  for (final edge in laidOut.layout.edges) {
    if (edge.points.length < 2) continue;
    var minX = edge.points.first.x;
    var maxX = minX;
    var minY = edge.points.first.y;
    var maxY = minY;
    for (final p in edge.points) {
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.y > maxY) maxY = p.y;
    }
    if (visible.overlaps(Rect.fromLTRB(minX, minY, maxX, maxY))) wires++;
  }
  return (cells: cells, wires: wires);
}

/// The keyboard navigator's former reading-order list.
List<SelectedElement> referenceReadingOrder(LaidOutGraph laidOut) {
  final placed =
      <(BoundingBox, SelectedElement)>[
        for (final cell in laidOut.graph.cells)
          if (laidOut.layout.findNode(cell.id) case final node?)
            (node.bounds, SelectedElement.cell(cellId: cell.id)),
        for (final port in laidOut.graph.boundaryPorts)
          if (laidOut.layout.findNode(port.id) case final node?)
            (
              node.bounds,
              SelectedElement.boundaryPort(
                portId: port.id,
                portName: port.name,
              ),
            ),
      ]..sort((a, b) {
        final byRow = a.$1.y.compareTo(b.$1.y);
        return byRow != 0 ? byRow : a.$1.x.compareTo(b.$1.x);
      });
  return <SelectedElement>[for (final (_, element) in placed) element];
}

/// The keyboard navigator's former pin-and-net walk list for [anchor].
List<SelectedElement> referenceConnectionsOf(
  LaidOutGraph laidOut,
  SelectedElement anchor,
) {
  final seen = <int>{};
  SelectedElementWire? netOn(String pinId) {
    for (final edge in laidOut.graph.edges) {
      if (edge.sourcePortId == pinId || edge.targetPortId == pinId) {
        return seen.add(edge.netId)
            ? SelectedElementWire(edgeId: edge.id, netId: edge.netId)
            : null;
      }
    }
    return null;
  }

  return switch (anchor) {
    SelectedElementCell(:final cellId) => <SelectedElement>[
      for (final cell in laidOut.graph.cells)
        if (cell.id == cellId)
          for (final pin in cell.ports) ...<SelectedElement>[
            SelectedElementPort(
              cellId: cellId,
              portId: pin.id,
              portName: pin.name,
            ),
            ?netOn(pin.id),
          ],
    ],
    SelectedElementBoundaryPort(:final portId) => <SelectedElement>[
      ?netOn(portId),
    ],
    _ => const <SelectedElement>[],
  };
}

/// The keyboard navigator's former driver lookup for a wire.
SelectedElement referenceDriverOf(LaidOutGraph laidOut, String edgeId) {
  final edge = laidOut.graph.findEdge(edgeId);
  if (edge == null) return const SelectedElement.none();
  final pinId = edge.sourcePortId;
  for (final port in laidOut.graph.boundaryPorts) {
    if (port.id == pinId) {
      return SelectedElement.boundaryPort(portId: port.id, portName: port.name);
    }
  }
  for (final cell in laidOut.graph.cells) {
    if (cell.ports.any((port) => port.id == pinId)) {
      return SelectedElement.cell(cellId: cell.id);
    }
  }
  return const SelectedElement.none();
}

/// A random scope with the geometry the index has to survive: overlapping
/// and nested cells, zero-size, inverted, NaN, infinite and far-away boxes,
/// pins boxed outside their cell, duplicate cell ids, cells and ports with
/// no node, nodes with no cell, wires with no points, one point, NaN points
/// and wires that cross the whole scope.
///
/// [wellFormed] leaves all of that out — every box finite, positive and at
/// least 20 units across — for callers that go on to paint the scene. The
/// painter itself asserts, index or not, on a NaN pin stub and on a cell
/// too narrow for its label.
LaidOutGraph randomScene(Random rng, {bool wellFormed = false}) {
  double coord() => -400 + rng.nextDouble() * 2000;
  double size() => (wellFormed ? 20 : 0) + rng.nextDouble() * 140;
  double odd(double normal) => wellFormed
      ? normal
      : switch (rng.nextInt(60)) {
          0 => double.nan,
          1 => double.infinity,
          2 => -normal,
          3 => 0,
          4 => normal * 1e7,
          _ => normal,
        };

  final cells = <SchematicCell>[];
  final nodes = <NodePosition>[];
  final pinIds = <String>[];
  final cellCount = rng.nextInt(50);
  for (var i = 0; i < cellCount; i++) {
    final id = i > 0 && rng.nextInt(12) == 0
        ? cells[rng.nextInt(cells.length)].id
        : 'c$i';
    final ports = <SchematicPort>[
      for (var j = 0; j < 1 + rng.nextInt(4); j++)
        SchematicPort(
          id: '$id:p$j',
          name: 'p$j',
          direction: PortDirection.input,
          side: SchematicPortSide.values[rng.nextInt(4)],
        ),
    ];
    cells.add(
      SchematicCell(
        id: id,
        kind: CellKind.generic,
        type: 'generic',
        ports: ports,
      ),
    );
    pinIds.addAll(ports.map((p) => p.id));
    if (rng.nextInt(10) == 0) continue; // no node for this cell
    final w = odd(size());
    final h = odd(size());
    nodes.add(
      NodePosition(
        id: id,
        bounds: BoundingBox(
          x: odd(coord()),
          y: odd(coord()),
          width: w,
          height: h,
        ),
        ports: <String, BoundingBox>{
          for (final port in ports)
            if (rng.nextInt(8) != 0)
              port.id: BoundingBox(
                x: odd(-10 + rng.nextDouble() * 160),
                y: odd(-10 + rng.nextDouble() * 160),
                width: odd(rng.nextDouble() * 8),
                height: odd(rng.nextDouble() * 8),
              ),
        },
      ),
    );
  }
  final boundary = <SchematicBoundaryPort>[
    for (var k = 0; k < rng.nextInt(6); k++)
      SchematicBoundaryPort(
        id: 'port:b$k',
        name: 'b$k',
        direction: PortDirection.input,
        width: 1,
      ),
  ];
  for (final port in boundary) {
    if (rng.nextInt(7) == 0) continue;
    nodes.add(
      NodePosition(
        id: port.id,
        bounds: BoundingBox(
          x: odd(coord()),
          y: odd(coord()),
          width: odd(16),
          height: odd(16),
        ),
      ),
    );
  }
  // A node no cell or port names.
  if (rng.nextBool()) {
    nodes.add(
      NodePosition(
        id: 'orphan',
        bounds: BoundingBox(x: coord(), y: coord(), width: 30, height: 30),
      ),
    );
  }

  final routes = <EdgeRoute>[];
  final graphEdges = <SchematicEdge>[];
  for (var k = 0; k < rng.nextInt(60); k++) {
    final net = rng.nextInt(40);
    final id = rng.nextInt(5) == 0 ? 'w$k' : 'e_${net}_$k';
    final pointCount = rng.nextInt(7);
    final long = rng.nextInt(15) == 0;
    var x = coord();
    var y = coord();
    final points = <LayoutPoint>[];
    for (var p = 0; p < pointCount; p++) {
      points.add(LayoutPoint(odd(x), odd(y)));
      final step = long ? 1600.0 : 120.0;
      if (rng.nextBool()) {
        x += (rng.nextDouble() - 0.5) * step;
      } else {
        y += (rng.nextDouble() - 0.5) * step;
      }
      if (rng.nextInt(6) == 0) x += (rng.nextDouble() - 0.5) * step;
    }
    routes.add(EdgeRoute(id: id, points: points));
    if (pinIds.length >= 2 && rng.nextInt(3) == 0) {
      graphEdges.add(
        SchematicEdge(
          id: id,
          sourcePortId: pinIds[rng.nextInt(pinIds.length)],
          targetPortId: pinIds[rng.nextInt(pinIds.length)],
          netId: net + 1000,
        ),
      );
    }
  }
  for (var k = 0; k < rng.nextInt(30); k++) {
    if (pinIds.isEmpty) break;
    final ends = <String>[
      ...pinIds,
      for (final port in boundary) port.id,
    ];
    graphEdges.add(
      SchematicEdge(
        id: 'g$k',
        sourcePortId: ends[rng.nextInt(ends.length)],
        targetPortId: ends[rng.nextInt(ends.length)],
        netId: rng.nextInt(20),
      ),
    );
  }

  return LaidOutGraph(
    graph: SchematicGraph(
      moduleName: 'random',
      cells: cells,
      boundaryPorts: boundary,
      edges: graphEdges,
    ),
    layout: NetlistLayout(
      nodes: nodes,
      edges: routes,
      bounds: const BoundingBox(x: -400, y: -400, width: 2000, height: 2000),
    ),
  );
}

/// A design-space point worth clicking in [laidOut]: anywhere, or on or just
/// beside a pin, a cell edge, a module port or a wire — where slop and
/// half-open rectangle edges decide the answer.
Offset randomClick(Random rng, LaidOutGraph laidOut) {
  final nodes = laidOut.layout.nodes;
  final edges = laidOut.layout.edges;
  double jitter(double reach) => (rng.nextDouble() - 0.5) * 2 * reach;
  final roll = rng.nextInt(5);
  if (roll == 0 && nodes.isNotEmpty) {
    final b = nodes[rng.nextInt(nodes.length)].bounds;
    // A corner or an edge of the node, exactly or within the pin slop.
    final x = rng.nextBool() ? b.x : b.x + b.width;
    final y = rng.nextBool() ? b.y : b.y + b.height;
    final exact = rng.nextInt(3) == 0;
    return Offset(x + (exact ? 0 : jitter(6)), y + (exact ? 0 : jitter(6)));
  }
  if (roll == 1 && nodes.isNotEmpty) {
    final node = nodes[rng.nextInt(nodes.length)];
    if (node.ports.isNotEmpty) {
      final box = node.ports.values.elementAt(rng.nextInt(node.ports.length));
      return Offset(
        node.bounds.x + box.x + jitter(9),
        node.bounds.y + box.y + jitter(9),
      );
    }
  }
  if (roll == 2 && edges.isNotEmpty) {
    final edge = edges[rng.nextInt(edges.length)];
    if (edge.points.isNotEmpty) {
      final p = edge.points[rng.nextInt(edge.points.length)];
      return Offset(p.x + jitter(14), p.y + jitter(14));
    }
  }
  return Offset(-500 + rng.nextDouble() * 2200, -500 + rng.nextDouble() * 2200);
}
