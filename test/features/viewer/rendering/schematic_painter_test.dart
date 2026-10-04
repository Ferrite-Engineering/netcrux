// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

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
import 'package:netcrux/features/viewer/providers/pane_render_stats.dart';
import 'package:netcrux/features/viewer/rendering/schematic_painter.dart';
import 'package:netcrux/services/schematic/schematic_crossing_overlay_provider.dart';

LaidOutGraph _twoCellGraph() {
  const portA = SchematicPort(
    id: 'u_and:A',
    name: 'A',
    direction: PortDirection.input,
    side: SchematicPortSide.west,
  );
  const portB = SchematicPort(
    id: 'u_and:B',
    name: 'B',
    direction: PortDirection.input,
    side: SchematicPortSide.west,
  );
  const portY = SchematicPort(
    id: 'u_and:Y',
    name: 'Y',
    direction: PortDirection.output,
    side: SchematicPortSide.east,
  );
  const cell = SchematicCell(
    id: 'u_and',
    kind: CellKind.andGate,
    type: r'$and',
    ports: <SchematicPort>[portA, portB, portY],
  );
  const boundary = SchematicBoundaryPort(
    id: 'port:y',
    name: 'y',
    direction: PortDirection.output,
    width: 1,
  );
  const graph = SchematicGraph(
    moduleName: 'and2',
    cells: <SchematicCell>[cell],
    boundaryPorts: <SchematicBoundaryPort>[boundary],
    edges: <SchematicEdge>[
      SchematicEdge(
        id: 'e0',
        sourcePortId: 'u_and:Y',
        targetPortId: 'port:y',
        netId: 4,
      ),
    ],
  );
  const layout = NetlistLayout(
    nodes: <NodePosition>[
      NodePosition(
        id: 'u_and',
        bounds: BoundingBox(x: 20, y: 30, width: 80, height: 60),
        ports: <String, BoundingBox>{
          'u_and:A': BoundingBox(x: 0, y: 10, width: 4, height: 4),
          'u_and:B': BoundingBox(x: 0, y: 40, width: 4, height: 4),
          'u_and:Y': BoundingBox(x: 76, y: 28, width: 4, height: 4),
        },
      ),
      NodePosition(
        id: 'port:y',
        bounds: BoundingBox(x: 160, y: 30, width: 16, height: 16),
      ),
    ],
    edges: <EdgeRoute>[
      EdgeRoute(
        id: 'e0',
        points: <LayoutPoint>[
          LayoutPoint(100, 60),
          LayoutPoint(130, 60),
          LayoutPoint(130, 38),
          LayoutPoint(160, 38),
        ],
      ),
    ],
    bounds: BoundingBox(x: 0, y: 0, width: 200, height: 100),
  );
  return const LaidOutGraph(graph: graph, layout: layout);
}

/// Builds a graph of [cellCount] cells laid out in a single row, so a
/// paint pass has a design of a controllable size to walk.
LaidOutGraph _rowGraph(int cellCount) {
  final cells = <SchematicCell>[
    for (var i = 0; i < cellCount; i++)
      SchematicCell(
        id: 'c$i',
        kind: CellKind.andGate,
        type: r'$and',
        ports: const <SchematicPort>[],
      ),
  ];
  final nodes = <NodePosition>[
    for (var i = 0; i < cellCount; i++)
      NodePosition(
        id: 'c$i',
        bounds: BoundingBox(x: i * 10.0, y: 0, width: 8, height: 8),
      ),
  ];
  return LaidOutGraph(
    graph: SchematicGraph(
      moduleName: 'row',
      cells: cells,
      boundaryPorts: const <SchematicBoundaryPort>[],
      edges: const <SchematicEdge>[],
    ),
    layout: NetlistLayout(
      nodes: nodes,
      edges: const <EdgeRoute>[],
      bounds: BoundingBox(x: 0, y: 0, width: cellCount * 10.0, height: 8),
    ),
  );
}

/// The rectangles the overview band drew for cells when [graph] is painted
/// at [zoom], in design units on the already-scaled canvas.
List<Rect> _overviewCellRects(LaidOutGraph graph, double zoom) {
  final renderObject = SchematicCanvasRenderObject(
    laidOut: graph,
    transform: ViewportTransform(zoom: zoom, offset: Offset.zero),
    theme: ThemeData.light(),
    statsSink: const NoopRenderStatsSink(),
  )..layout(BoxConstraints.tight(const Size(1400, 900)));
  final context = TestRecordingPaintingContext(TestRecordingCanvas());
  renderObject.paint(context, Offset.zero);
  return <Rect>[
    for (final recorded in (context.canvas as TestRecordingCanvas).invocations)
      // Cells paint at their own translated origin; the one other
      // origin-anchored rect is the viewport background fill.
      if (recorded.invocation.memberName == #drawRect &&
          recorded.invocation.positionalArguments.first is Rect &&
          (recorded.invocation.positionalArguments.first as Rect).topLeft ==
              Offset.zero &&
          (recorded.invocation.positionalArguments.first as Rect).size !=
              const Size(1400, 900))
        recorded.invocation.positionalArguments.first as Rect,
  ];
}

/// Paints [graph] with [overlay] active and returns how many canvas
/// operations the pass issued.
int _paintOpCount(LaidOutGraph graph, SchematicCrossingOverlay? overlay) {
  final renderObject = SchematicCanvasRenderObject(
    laidOut: graph,
    transform: ViewportTransform.identity,
    theme: ThemeData.light(),
    statsSink: const NoopRenderStatsSink(),
    crossingOverlay: overlay,
  )..layout(BoxConstraints.tight(const Size(4000, 400)));
  final context = TestRecordingPaintingContext(TestRecordingCanvas());
  renderObject.paint(context, Offset.zero);
  return (context.canvas as TestRecordingCanvas).invocations.length;
}

void main() {
  group('overview band device-pixel floor', () {
    test('cells never paint smaller than the floor at a far-out zoom', () {
      // At 0.002 the helper's 8 px cells would be 0.016 device pixels.
      const zoom = 0.002;
      final rects = _overviewCellRects(_rowGraph(3), zoom);
      expect(rects, hasLength(3));
      const floor = SchematicViewportLimits.overviewMinCellPx / zoom;
      for (final rect in rects) {
        expect(rect.width, closeTo(floor, 1e-9));
        expect(rect.height, closeTo(floor, 1e-9));
      }
    });

    test('cells above the floor keep their own size', () {
      // At 0.5 (mid band) the same cells are 4 device pixels: no overview
      // painting, and nothing is inflated.
      final rects = _overviewCellRects(_rowGraph(3), 0.5);
      expect(rects.where((r) => r.width == 8 && r.height == 8), isEmpty);
      final overview = _overviewCellRects(_rowGraph(3), 0.3);
      expect(overview, isEmpty);
    });
  });

  group('ViewportTransform', () {
    test('identity has zoom 1 and zero offset', () {
      expect(ViewportTransform.identity.zoom, 1.0);
      expect(ViewportTransform.identity.offset, Offset.zero);
    });

    test('equality compares zoom and offset', () {
      const a = ViewportTransform(zoom: 2, offset: Offset(10, 20));
      const b = ViewportTransform(zoom: 2, offset: Offset(10, 20));
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });

  group('SchematicViewportLimits', () {
    test('clamps below the floor and above the ceiling', () {
      expect(SchematicViewportLimits.clampZoom(0.0001), 0.001);
      expect(SchematicViewportLimits.clampZoom(1), 1.0);
      expect(SchematicViewportLimits.clampZoom(50), 10);
    });
  });

  group('NoopRenderStatsSink', () {
    test('record() is a no-op (no throw, no side-effects)', () {
      const NoopRenderStatsSink().record(PaneRenderStats.empty);
    });
  });

  group('RecordingRenderStatsSink', () {
    test('captures every sample in order', () {
      final sink = RecordingRenderStatsSink()
        ..record(
          const PaneRenderStats(
            frameNumber: 1,
            paintMicroseconds: 10,
            visibleCells: 1,
            visibleEdges: 1,
            totalCells: 1,
            totalEdges: 1,
          ),
        )
        ..record(
          const PaneRenderStats(
            frameNumber: 2,
            paintMicroseconds: 20,
            visibleCells: 2,
            visibleEdges: 2,
            totalCells: 2,
            totalEdges: 2,
          ),
        );
      expect(sink.samples, hasLength(2));
      expect(sink.last!.frameNumber, 2);
    });

    test('last is null before any record() call', () {
      final sink = RecordingRenderStatsSink();
      expect(sink.last, isNull);
    });
  });

  group('crossing overlay paint cost', () {
    const overlay = SchematicCrossingOverlay(
      sourceCellIds: <String>{'c1'},
      destinationCellIds: <String>{'c2'},
      intermediateCellIds: <String>{},
      severityColor: Color(0xFFFF0000),
    );

    test('costs one op per overlay cell, independent of design size', () {
      // The overlay pass must iterate its own id sets, not scan every
      // cell in the design. If it ever regresses to a full scan this
      // delta stays 2 but the base cost explodes, so assert both the
      // delta and that it does not grow with the design.
      final smallDelta =
          _paintOpCount(_rowGraph(50), overlay) -
          _paintOpCount(_rowGraph(50), null);
      final largeDelta =
          _paintOpCount(_rowGraph(400), overlay) -
          _paintOpCount(_rowGraph(400), null);
      expect(smallDelta, 2, reason: 'one stroked rect per named cell');
      expect(largeDelta, smallDelta);
    });

    test('a cell in two roles is stroked exactly once', () {
      const doubled = SchematicCrossingOverlay(
        sourceCellIds: <String>{'c1'},
        destinationCellIds: <String>{'c1'},
        intermediateCellIds: <String>{'c1'},
        severityColor: Color(0xFFFF0000),
      );
      final delta =
          _paintOpCount(_rowGraph(50), doubled) -
          _paintOpCount(_rowGraph(50), null);
      expect(delta, 1);
    });

    test('ids absent from the layout draw nothing', () {
      const absent = SchematicCrossingOverlay(
        sourceCellIds: <String>{'not_a_cell'},
        destinationCellIds: <String>{},
        intermediateCellIds: <String>{},
        severityColor: Color(0xFFFF0000),
      );
      final delta =
          _paintOpCount(_rowGraph(50), absent) -
          _paintOpCount(_rowGraph(50), null);
      expect(delta, 0);
    });
  });

  group('crossing overlay wires', () {
    // Net 4 is a two-strand net (two laid-out edges); net 5 is unrelated.
    LaidOutGraph wiredGraph() {
      EdgeRoute route(String id, double y) => EdgeRoute(
        id: id,
        points: <LayoutPoint>[LayoutPoint(10, y), LayoutPoint(90, y)],
      );
      return LaidOutGraph(
        graph: const SchematicGraph(
          moduleName: 'wired',
          cells: <SchematicCell>[
            SchematicCell(
              id: 'c0',
              kind: CellKind.andGate,
              type: r'$and',
              ports: <SchematicPort>[],
            ),
          ],
          boundaryPorts: <SchematicBoundaryPort>[],
          edges: <SchematicEdge>[],
        ),
        layout: NetlistLayout(
          nodes: const <NodePosition>[
            NodePosition(
              id: 'c0',
              bounds: BoundingBox(x: 0, y: 0, width: 8, height: 8),
            ),
          ],
          edges: <EdgeRoute>[
            route('e_4_0', 20),
            route('e_4_1', 30),
            route('e_5_0', 40),
          ],
          bounds: const BoundingBox(x: 0, y: 0, width: 100, height: 50),
        ),
      );
    }

    const severity = Color(0xFFD32F2F);

    List<Paint> pathPaints(SchematicCrossingOverlay? overlay) {
      final renderObject = SchematicCanvasRenderObject(
        laidOut: wiredGraph(),
        transform: ViewportTransform.identity,
        theme: ThemeData.light(),
        statsSink: const NoopRenderStatsSink(),
        crossingOverlay: overlay,
      )..layout(BoxConstraints.tight(const Size(400, 200)));
      final context = TestRecordingPaintingContext(TestRecordingCanvas());
      renderObject.paint(context, Offset.zero);
      return <Paint>[
        for (final recorded
            in (context.canvas as TestRecordingCanvas).invocations)
          if (recorded.invocation.memberName == #drawPath)
            recorded.invocation.positionalArguments[1] as Paint,
      ];
    }

    test('a net-only overlay is not empty', () {
      const overlay = SchematicCrossingOverlay(
        sourceCellIds: <String>{},
        destinationCellIds: <String>{},
        intermediateCellIds: <String>{},
        severityColor: severity,
        netIds: <int>{4},
      );
      expect(overlay.isEmpty, isFalse);
      expect(overlay == SchematicCrossingOverlay.empty, isFalse);
    });

    test('every strand of the crossing net paints in the severity colour', () {
      const overlay = SchematicCrossingOverlay(
        sourceCellIds: <String>{},
        destinationCellIds: <String>{},
        intermediateCellIds: <String>{},
        severityColor: severity,
        netIds: <int>{4},
      );
      final withOverlay = pathPaints(
        overlay,
      ).where((p) => p.color.toARGB32() == severity.toARGB32()).length;
      final without = pathPaints(
        null,
      ).where((p) => p.color.toARGB32() == severity.toARGB32()).length;
      expect(without, 0);
      expect(withOverlay, 2, reason: 'both net-4 strands, not net 5');
    });

    test('an overlay without net ids paints no wires', () {
      const overlay = SchematicCrossingOverlay(
        sourceCellIds: <String>{'c0'},
        destinationCellIds: <String>{},
        intermediateCellIds: <String>{},
        severityColor: severity,
      );
      expect(pathPaints(overlay).length, pathPaints(null).length);
    });
  });

  group('SchematicCanvas widget', () {
    testWidgets('paints an empty graph without exception', (tester) async {
      final sink = RecordingRenderStatsSink();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 300,
              child: SchematicCanvas(
                laidOut: LaidOutGraph.empty,
                transform: ViewportTransform.identity,
                statsSink: sink,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(sink.last, isNotNull);
      // Empty graph → zero painted cells / edges.
      expect(sink.last!.visibleCells, 0);
      expect(sink.last!.visibleEdges, 0);
    });

    testWidgets('paints a populated graph and records cell/edge counts', (
      tester,
    ) async {
      final sink = RecordingRenderStatsSink();
      final graph = _twoCellGraph();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 300,
              child: SchematicCanvas(
                laidOut: graph,
                transform: ViewportTransform.identity,
                statsSink: sink,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(sink.last, isNotNull);
      expect(sink.last!.visibleCells, 1);
      expect(sink.last!.visibleEdges, 1);
      expect(sink.last!.totalCells, 1);
      expect(sink.last!.totalEdges, 1);
    });

    testWidgets('culls cells/edges panned entirely off-screen', (
      tester,
    ) async {
      final sink = RecordingRenderStatsSink();
      final graph = _twoCellGraph();
      // Pan the design far to the left of the viewport so no element
      // overlaps the visible design rect (even with the cull margin).
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 300,
              child: SchematicCanvas(
                laidOut: graph,
                transform: const ViewportTransform(
                  zoom: 1,
                  offset: Offset(-100000, 0),
                ),
                statsSink: sink,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // Nothing on-screen → nothing drawn, but the graph still has its
      // one cell / one edge.
      expect(sink.last!.visibleCells, 0);
      expect(sink.last!.visibleEdges, 0);
      expect(sink.last!.totalCells, 1);
      expect(sink.last!.totalEdges, 1);
    });

    testWidgets('cullingEnabled: false paints off-screen elements', (
      tester,
    ) async {
      final sink = RecordingRenderStatsSink();
      final graph = _twoCellGraph();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 300,
              child: SchematicCanvas(
                laidOut: graph,
                transform: const ViewportTransform(
                  zoom: 1,
                  offset: Offset(-100000, 0),
                ),
                statsSink: sink,
                cullingEnabled: false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // Same off-screen pan, but culling disabled → every element draws.
      expect(sink.last!.visibleCells, 1);
      expect(sink.last!.visibleEdges, 1);
    });

    testWidgets('changing transform repaints', (tester) async {
      final sink = RecordingRenderStatsSink();
      final graph = _twoCellGraph();
      Widget host(ViewportTransform transform) => MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 300,
            child: SchematicCanvas(
              laidOut: graph,
              transform: transform,
              statsSink: sink,
            ),
          ),
        ),
      );
      await tester.pumpWidget(host(ViewportTransform.identity));
      await tester.pumpAndSettle();
      final framesAfterInitial = sink.samples.length;
      await tester.pumpWidget(
        host(const ViewportTransform(zoom: 2, offset: Offset(10, 5))),
      );
      await tester.pumpAndSettle();
      expect(sink.samples.length, greaterThan(framesAfterInitial));
    });
  });
}
