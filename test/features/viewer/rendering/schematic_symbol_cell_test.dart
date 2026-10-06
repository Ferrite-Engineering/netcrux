// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// A cell drawn with a custom symbol keeps its name outside the drawing and
// names the pins its symbol anchors, beside them. Every other cell paints
// exactly as before.

import 'dart:ui' as ui;

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

/// The symbol cell's node: 120 by 90 at (100, 100).
const _uartRect = Rect.fromLTWH(100, 100, 120, 90);

/// The ordinary cell's node: 80 by 60 at (400, 100).
const _andRect = Rect.fromLTWH(400, 100, 80, 60);

SchematicPort _port(String cell, String name, PortDirection direction) =>
    SchematicPort(
      id: '$cell:$name',
      name: name,
      direction: direction,
      side: direction == PortDirection.input
          ? SchematicPortSide.west
          : SchematicPortSide.east,
    );

NodePosition _nodeAt(
  String id,
  Rect rect, [
  Map<String, BoundingBox> ports = const <String, BoundingBox>{},
]) => NodePosition(
  id: id,
  bounds: BoundingBox(
    x: rect.left,
    y: rect.top,
    width: rect.width,
    height: rect.height,
  ),
  ports: ports,
);

/// `u_uart` (type `uart_tx`) has pins on the west (`clk`, `we`), east
/// (`tx`) and north (`irq`) faces where the symbol layout puts them; its
/// symbol anchors `clk`, `tx` and `irq` but not `we`. `u_and` is an
/// ordinary cell. [symbolCells] says which cells have a symbol; [extra]
/// adds cells, such as one parked under `u_uart`.
LaidOutGraph _graph({
  Map<String, Set<String>> symbolCells = const <String, Set<String>>{
    'u_uart': <String>{'clk', 'tx', 'irq'},
  },
  List<(SchematicCell, Rect)> extra = const <(SchematicCell, Rect)>[],
}) {
  final uart = SchematicCell(
    id: 'u_uart',
    kind: CellKind.generic,
    type: 'uart_tx',
    ports: <SchematicPort>[
      _port('u_uart', 'clk', PortDirection.input),
      _port('u_uart', 'we', PortDirection.input),
      _port('u_uart', 'tx', PortDirection.output),
      _port('u_uart', 'irq', PortDirection.output),
    ],
  );
  final and = SchematicCell(
    id: 'u_and',
    kind: CellKind.andGate,
    type: r'$and',
    ports: <SchematicPort>[
      _port('u_and', 'A', PortDirection.input),
      _port('u_and', 'Y', PortDirection.output),
    ],
  );
  return LaidOutGraph(
    graph: SchematicGraph(
      moduleName: 'soc_top',
      cells: <SchematicCell>[uart, and, for (final (cell, _) in extra) cell],
      boundaryPorts: const <SchematicBoundaryPort>[],
      edges: const <SchematicEdge>[],
    ),
    layout: NetlistLayout(
      nodes: <NodePosition>[
        _nodeAt('u_uart', _uartRect, const <String, BoundingBox>{
          'u_uart:clk': BoundingBox(x: -4, y: 18, width: 4, height: 4),
          'u_uart:we': BoundingBox(x: -4, y: 58, width: 4, height: 4),
          'u_uart:tx': BoundingBox(x: 120, y: 38, width: 4, height: 4),
          'u_uart:irq': BoundingBox(x: 58, y: -4, width: 4, height: 4),
        }),
        _nodeAt('u_and', _andRect, const <String, BoundingBox>{
          'u_and:A': BoundingBox(x: -4, y: 28, width: 4, height: 4),
          'u_and:Y': BoundingBox(x: 80, y: 28, width: 4, height: 4),
        }),
        for (final (cell, rect) in extra) _nodeAt(cell.id, rect),
      ],
      edges: const <EdgeRoute>[],
      bounds: const BoundingBox(x: 0, y: 0, width: 600, height: 400),
    ),
    symbolCells: symbolCells,
  );
}

/// Paints [graph] at [zoom] with no pan and returns where every paragraph
/// (every piece of text) landed, in design units.
List<Rect> _paragraphRects(LaidOutGraph graph, {double zoom = 1}) {
  final renderObject = SchematicCanvasRenderObject(
    laidOut: graph,
    transform: ViewportTransform(zoom: zoom, offset: Offset.zero),
    theme: ThemeData.light(),
    statsSink: const NoopRenderStatsSink(),
  )..layout(BoxConstraints.tight(const Size(1200, 800)));
  final context = TestRecordingPaintingContext(TestRecordingCanvas());
  renderObject.paint(context, Offset.zero);
  // Replay the translate / scale / save / restore stack the painter uses.
  var origin = Offset.zero;
  var scale = 1.0;
  final stack = <(Offset, double)>[];
  final rects = <Rect>[];
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
      case #drawParagraph:
        final paragraph = args[0] as ui.Paragraph;
        final at = origin + (args[1] as Offset) * scale;
        rects.add(
          Rect.fromLTWH(
                at.dx,
                at.dy,
                paragraph.longestLine * scale,
                paragraph.height * scale,
              ) /
              zoom,
        );
    }
  }
  return rects;
}

extension on Rect {
  Rect operator /(double factor) => Rect.fromLTRB(
    left / factor,
    top / factor,
    right / factor,
    bottom / factor,
  );
}

bool _inside(Rect inner, Rect outer) =>
    inner.left >= outer.left - 1e-6 &&
    inner.top >= outer.top - 1e-6 &&
    inner.right <= outer.right + 1e-6 &&
    inner.bottom <= outer.bottom + 1e-6;

void main() {
  group('custom-symbol cell label', () {
    testWidgets('is outside the drawing, centred below it', (tester) async {
      final rects = _paragraphRects(_graph());
      final outside = <Rect>[
        for (final r in rects)
          if (!_uartRect.overlaps(r) && !_andRect.overlaps(r)) r,
      ];
      expect(outside, hasLength(1), reason: 'one label outside, got $rects');
      final label = outside.single;
      expect(label.top, greaterThanOrEqualTo(_uartRect.bottom));
      expect(label.center.dx, closeTo(_uartRect.center.dx, 0.5));
      // Nothing but pin names inside the drawing: no centred cell label.
      for (final r in rects.where(_uartRect.overlaps)) {
        expect(
          (r.center - _uartRect.center).distance,
          greaterThan(10),
          reason: 'text painted over the middle of the drawing at $r',
        );
      }
    });

    testWidgets('goes above when a cell occupies the space below', (
      tester,
    ) async {
      const blocker = SchematicCell(
        id: 'u_below',
        kind: CellKind.andGate,
        type: r'$and',
        ports: <SchematicPort>[],
      );
      const blockerRect = Rect.fromLTWH(110, 195, 100, 40);
      final rects = _paragraphRects(
        _graph(extra: const <(SchematicCell, Rect)>[(blocker, blockerRect)]),
      );
      final above = rects.where((r) => r.bottom <= _uartRect.top).toList();
      expect(above, hasLength(1), reason: '$rects');
      expect(above.single.overlaps(blockerRect), isFalse);
    });

    testWidgets('an ordinary cell keeps its centred label', (tester) async {
      final rects = _paragraphRects(_graph());
      final inAnd = rects.where(_andRect.overlaps).toList();
      expect(inAnd, hasLength(1), reason: 'no pin names on an ordinary cell');
      expect(inAnd.single.center.dx, closeTo(_andRect.center.dx, 0.5));
      expect(inAnd.single.center.dy, closeTo(_andRect.center.dy, 0.5));
      // The same cell paints the same text with or without a symbol elsewhere.
      final without = _paragraphRects(
        _graph(symbolCells: const <String, Set<String>>{}),
      );
      expect(without.where(_andRect.overlaps).toList(), inAnd);
    });

    testWidgets('without a symbol, the cell label is centred as before', (
      tester,
    ) async {
      final rects = _paragraphRects(
        _graph(symbolCells: const <String, Set<String>>{}),
      );
      final inUart = rects.where(_uartRect.overlaps).toList();
      expect(inUart, hasLength(1));
      expect(inUart.single.center.dx, closeTo(_uartRect.center.dx, 0.5));
      expect(inUart.single.center.dy, closeTo(_uartRect.center.dy, 0.5));
    });
  });

  group('custom-symbol pin names', () {
    testWidgets('name exactly the anchored pins, inside the drawing, each on '
        "its pin's face", (tester) async {
      final rects = _paragraphRects(_graph());
      final pins = rects.where(_uartRect.overlaps).toList();
      expect(pins, hasLength(3), reason: 'clk, tx and irq; not we: $pins');
      for (final r in pins) {
        expect(_inside(r, _uartRect), isTrue, reason: '$r');
      }
      // clk: west face, left-aligned against the edge, level with the pin.
      final clk = pins.where((r) => (r.center.dy - 120).abs() < 1).toList();
      expect(clk, hasLength(1));
      expect(clk.single.left, closeTo(_uartRect.left + 3, 0.01));
      // tx: east face, right-aligned against the edge.
      final tx = pins.where((r) => (r.center.dy - 140).abs() < 1).toList();
      expect(tx, hasLength(1));
      expect(tx.single.right, closeTo(_uartRect.right - 3, 0.5));
      // irq: north face, centred under the pin, against the top edge.
      final irq = pins.where((r) => (r.top - (_uartRect.top + 3)).abs() < 0.01);
      expect(irq, hasLength(1));
      expect(irq.single.center.dx, closeTo(_uartRect.left + 60, 0.5));
      // we (y = 160) has no anchor and so no name.
      expect(pins.where((r) => (r.center.dy - 160).abs() < 4), isEmpty);
    });

    testWidgets('a symbol that anchors no pin names none', (tester) async {
      final rects = _paragraphRects(
        _graph(
          symbolCells: const <String, Set<String>>{'u_uart': <String>{}},
        ),
      );
      expect(rects.where(_uartRect.overlaps), isEmpty);
    });

    testWidgets('are not drawn in the mid or overview band', (tester) async {
      for (final zoom in <double>[0.5, 0.1]) {
        final rects = _paragraphRects(_graph(), zoom: zoom);
        expect(rects, isEmpty, reason: 'zoom $zoom painted text: $rects');
      }
    });
  });

  test('outsideLabelRect never lands inside the cell', () {
    const cell = Rect.fromLTWH(0, 0, 100, 50);
    const size = Size(60, 12);
    final below = SchematicCanvasRenderObject.outsideLabelRect(
      cell,
      size,
      isFree: (_) => true,
    );
    expect(below.top, cell.bottom + 2);
    final above = SchematicCanvasRenderObject.outsideLabelRect(
      cell,
      size,
      isFree: (r) => r.top < cell.top,
    );
    expect(above.bottom, cell.top - 2);
    final neither = SchematicCanvasRenderObject.outsideLabelRect(
      cell,
      size,
      isFree: (_) => false,
    );
    expect(neither, below);
    for (final r in <Rect>[below, above, neither]) {
      expect(r.overlaps(cell), isFalse);
    }
  });
}
