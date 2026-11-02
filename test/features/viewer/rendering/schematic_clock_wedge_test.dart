// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// A cell-library flip-flop marks its clock pins: the canvas draws a clock
// wedge at each, where the layout put the pin, and none at the fixed place a
// Yosys flip-flop has it. A cell drawn with a custom symbol gets none.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/layout/bounding_box.dart';
import 'package:netcrux/domain/models/layout/edge_route.dart';
import 'package:netcrux/domain/models/layout/netlist_layout.dart';
import 'package:netcrux/domain/models/layout/node_position.dart';
import 'package:netcrux/domain/models/netlist/port_direction.dart';
import 'package:netcrux/domain/models/schematic/cell_kind.dart';
import 'package:netcrux/domain/models/schematic/laid_out_graph.dart';
import 'package:netcrux/domain/models/schematic/schematic_graph.dart';
import 'package:netcrux/features/viewer/rendering/schematic_painter.dart';

/// The flip-flop's node: 80 by 60 at (100, 100), D at the top of the west
/// face and CLK below it, with its centre 40 units down.
const _dffRect = Rect.fromLTWH(100, 100, 80, 60);

LaidOutGraph _graph({
  required bool markClock,
  Map<String, Set<String>> symbolCells = const <String, Set<String>>{},
}) {
  SchematicPort port(
    String name,
    PortDirection direction, {
    bool clock = false,
  }) => SchematicPort(
    id: 'u_dff:$name',
    name: name,
    direction: direction,
    side: direction == PortDirection.input
        ? SchematicPortSide.west
        : SchematicPortSide.east,
    clock: clock,
  );
  return LaidOutGraph(
    graph: SchematicGraph(
      moduleName: 'top',
      cells: <SchematicCell>[
        SchematicCell(
          id: 'u_dff',
          kind: CellKind.flipFlop,
          type: markClock ? 'DFF_X1' : r'$dff',
          ports: <SchematicPort>[
            port('D', PortDirection.input),
            port('CLK', PortDirection.input, clock: markClock),
            port('Q', PortDirection.output),
          ],
        ),
      ],
      boundaryPorts: const <SchematicBoundaryPort>[],
      edges: const <SchematicEdge>[],
    ),
    layout: const NetlistLayout(
      nodes: <NodePosition>[
        NodePosition(
          id: 'u_dff',
          bounds: BoundingBox(x: 100, y: 100, width: 80, height: 60),
          ports: <String, BoundingBox>{
            'u_dff:D': BoundingBox(x: -4, y: 18, width: 4, height: 4),
            'u_dff:CLK': BoundingBox(x: -4, y: 38, width: 4, height: 4),
            'u_dff:Q': BoundingBox(x: 80, y: 28, width: 4, height: 4),
          },
        ),
      ],
      edges: <EdgeRoute>[],
      bounds: BoundingBox(x: 0, y: 0, width: 400, height: 300),
    ),
    symbolCells: symbolCells,
  );
}

/// The bounds, in design units, of every path the canvas draws inside the
/// flip-flop's node.
List<Rect> _pathsInCell(LaidOutGraph graph) {
  final renderObject = SchematicCanvasRenderObject(
    laidOut: graph,
    transform: const ViewportTransform(zoom: 2, offset: Offset.zero),
    theme: ThemeData.light(),
    statsSink: const NoopRenderStatsSink(),
  )..layout(BoxConstraints.tight(const Size(1200, 800)));
  final context = TestRecordingPaintingContext(TestRecordingCanvas());
  renderObject.paint(context, Offset.zero);
  var origin = Offset.zero;
  var scale = 1.0;
  final stack = <(Offset, double)>[];
  final rects = <Rect>{};
  for (final recorded in (context.canvas as TestRecordingCanvas).invocations) {
    final args = recorded.invocation.positionalArguments;
    switch (recorded.invocation.memberName) {
      case #save:
        stack.add((origin, scale));
      case #restore:
        (origin, scale) = stack.removeLast();
      case #translate:
        origin += Offset(args[0] as double, args[1] as double) * scale;
      case #scale:
        scale *= args[0] as double;
      case #drawPath:
        final b = (args[0] as Path).getBounds();
        final r = Rect.fromLTRB(
          (origin.dx + b.left * scale) / 2,
          (origin.dy + b.top * scale) / 2,
          (origin.dx + b.right * scale) / 2,
          (origin.dy + b.bottom * scale) / 2,
        );
        if (_dffRect.inflate(1).contains(r.center)) rects.add(r);
    }
  }
  return rects.toList();
}

void main() {
  testWidgets('a marked clock pin gets a wedge at its own height, and no '
      'wedge sits at the fixed place', (tester) async {
    final paths = _pathsInCell(_graph(markClock: true));
    expect(paths, hasLength(1), reason: '$paths');
    final wedge = paths.single;
    // CLK's centre: 100 + 38 + 2.
    expect(wedge.center.dy, closeTo(140, 0.01));
    expect(wedge.left, closeTo(_dffRect.left + 80 * 0.06, 0.01));
  });

  testWidgets('a Yosys flip-flop keeps its wedge at the fixed place', (
    tester,
  ) async {
    final paths = _pathsInCell(_graph(markClock: false));
    expect(paths, hasLength(1), reason: '$paths');
    expect(paths.single.center.dy, closeTo(100 + 60 * 0.78, 0.01));
  });

  testWidgets('a cell drawn with a custom symbol gets no wedge', (
    tester,
  ) async {
    final paths = _pathsInCell(
      _graph(
        markClock: true,
        symbolCells: const <String, Set<String>>{'u_dff': <String>{}},
      ),
    );
    expect(paths, isEmpty);
  });
}
