// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Regression: a cone-of-influence overlay must POSITIVELY highlight
// the cone's cells and wires in an accent color — not merely dim everything
// else. The mid/detail LOD symbol body is painted identically regardless of
// cone membership, so before this fix the cone cells were barely
// distinguishable from the dimmed rest at normal zoom.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/theme/netcrux_colors.dart';
import 'package:netcrux/domain/models/layout/bounding_box.dart';
import 'package:netcrux/domain/models/layout/edge_route.dart';
import 'package:netcrux/domain/models/layout/netlist_layout.dart';
import 'package:netcrux/domain/models/layout/node_position.dart';
import 'package:netcrux/domain/models/netlist/port_direction.dart';
import 'package:netcrux/domain/models/schematic/cell_kind.dart';
import 'package:netcrux/domain/models/schematic/laid_out_graph.dart';
import 'package:netcrux/domain/models/schematic/schematic_graph.dart';
import 'package:netcrux/domain/models/trace/trace_overlay.dart';
import 'package:netcrux/features/viewer/rendering/schematic_painter.dart';

/// `u_ff -> port` over net 7, laid out with real geometry.
LaidOutGraph _graph() {
  const cell = SchematicCell(
    id: 'u_ff',
    kind: CellKind.flipFlop,
    type: r'$dff',
    ports: <SchematicPort>[
      SchematicPort(
        id: 'u_ff:Q',
        name: 'Q',
        direction: PortDirection.output,
        side: SchematicPortSide.east,
      ),
    ],
  );
  const boundary = SchematicBoundaryPort(
    id: 'port:out',
    name: 'out',
    direction: PortDirection.output,
    width: 1,
  );
  const graph = SchematicGraph(
    moduleName: 'top',
    cells: <SchematicCell>[cell],
    boundaryPorts: <SchematicBoundaryPort>[boundary],
    edges: <SchematicEdge>[
      SchematicEdge(
        id: 'e_7_0',
        sourcePortId: 'u_ff:Q',
        targetPortId: 'port:out',
        netId: 7,
      ),
    ],
  );
  const layout = NetlistLayout(
    nodes: <NodePosition>[
      NodePosition(
        id: 'u_ff',
        bounds: BoundingBox(x: 20, y: 20, width: 60, height: 40),
      ),
      NodePosition(
        id: 'port:out',
        bounds: BoundingBox(x: 160, y: 24, width: 16, height: 16),
      ),
    ],
    edges: <EdgeRoute>[
      EdgeRoute(
        id: 'e_7_0',
        points: <LayoutPoint>[LayoutPoint(80, 40), LayoutPoint(160, 32)],
      ),
    ],
    bounds: BoundingBox(x: 0, y: 0, width: 200, height: 100),
  );
  return const LaidOutGraph(graph: graph, layout: layout);
}

/// Paints [graph] under [overlay] and reports whether the cone accent color
/// was used for (a) a filled rect — the cell body accent — and (b) a stroked
/// path — the wire accent.
({bool cellAccent, bool edgeAccent}) _paintAndInspect(
  LaidOutGraph graph,
  TraceOverlay overlay,
) {
  final renderObject = SchematicCanvasRenderObject(
    laidOut: graph,
    transform: ViewportTransform.identity,
    theme: ThemeData.light(),
    overlay: overlay,
    statsSink: const NoopRenderStatsSink(),
  )..layout(BoxConstraints.tight(const Size(400, 200)));
  final context = TestRecordingPaintingContext(TestRecordingCanvas());
  renderObject.paint(context, Offset.zero);
  final canvas = context.canvas as TestRecordingCanvas;
  final accent = NetcruxColors.coneAccent.toARGB32();
  var cellAccent = false;
  var edgeAccent = false;
  for (final recorded in canvas.invocations) {
    final invocation = recorded.invocation;
    if (invocation.memberName == #drawRect) {
      final paint = invocation.positionalArguments[1] as Paint;
      if (paint.color.toARGB32() == accent) cellAccent = true;
    }
    if (invocation.memberName == #drawPath) {
      final paint = invocation.positionalArguments[1] as Paint;
      if (paint.color.toARGB32() == accent) edgeAccent = true;
    }
  }
  return (cellAccent: cellAccent, edgeAccent: edgeAccent);
}

void main() {
  group('cone-of-influence positive highlight', () {
    test('a cone cell + its wire are drawn in the cone accent', () {
      const overlay = TraceOverlay(
        mode: TraceOverlayMode.fanout,
        highlightedCellIds: <String>{'u_ff'},
        highlightedEdgeIds: <String>{'e_7_0'},
        highlightedBoundaryPortIds: <String>{},
      );
      final result = _paintAndInspect(_graph(), overlay);
      expect(result.cellAccent, isTrue, reason: 'cone cell body accent');
      expect(result.edgeAccent, isTrue, reason: 'cone wire accent');
    });

    test('with no overlay, nothing is painted in the cone accent', () {
      final result = _paintAndInspect(_graph(), TraceOverlay.empty);
      expect(result.cellAccent, isFalse);
      expect(result.edgeAccent, isFalse);
    });
  });
}
