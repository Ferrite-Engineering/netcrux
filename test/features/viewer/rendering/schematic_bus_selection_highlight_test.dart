// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Regression: selecting a multi-bit BUS must accent EVERY drawn strand,
// not just one.
//
// The live bug: AnalysisSelectionProbe.selectNet selected a single
// SelectedElement.wire for the FIRST bit of the net, so the painter (which
// accents edges by net id) lit only 1 of a bus's parallel strands — a
// selected 8-bit bus like cdc_capture.sample_a read as one faint wire the
// user had to zoom in to see. The fix builds a whole-net multi-element
// wire Selection (one wire per drawn bit) via buildWholeNetWireSelection,
// so the painter lights all strands. This test drives the builder + the
// real painter with a synthetic 3-strand bus and a 1-bit net.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/theme/netcrux_colors.dart';
import 'package:netcrux/domain/models/layout/bounding_box.dart';
import 'package:netcrux/domain/models/layout/edge_route.dart';
import 'package:netcrux/domain/models/layout/netlist_layout.dart';
import 'package:netcrux/domain/models/layout/node_position.dart';
import 'package:netcrux/domain/models/netlist/bit_ref.dart';
import 'package:netcrux/domain/models/netlist/net.dart';
import 'package:netcrux/domain/models/netlist/port_direction.dart';
import 'package:netcrux/domain/models/schematic/cell_kind.dart';
import 'package:netcrux/domain/models/schematic/laid_out_graph.dart';
import 'package:netcrux/domain/models/schematic/schematic_graph.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/domain/models/selection/selection.dart';
import 'package:netcrux/features/viewer/rendering/schematic_painter.dart';
import 'package:netcrux/services/schematic/wire_selection_builder.dart';

/// Net ids of the three drawn strands of the synthetic `sample_a` bus.
const _busNetIds = <int>[10, 11, 12];

/// Net id of the unrelated single-bit `req_b0` net.
const _singleNetId = 20;

/// Builds a [SchematicGraph] with one driver cell and one edge per net id
/// in [_busNetIds] plus the single-bit net — the fresh-build graph the
/// probe/inbound handler resolve a wire against.
SchematicGraph _graph() {
  final ports = <SchematicPort>[
    for (final id in <int>[..._busNetIds, _singleNetId])
      SchematicPort(
        id: 'u_ff:Q$id',
        name: 'Q$id',
        direction: PortDirection.output,
        side: SchematicPortSide.east,
      ),
  ];
  final cell = SchematicCell(
    id: 'u_ff',
    kind: CellKind.flipFlop,
    type: r'$dff',
    ports: ports,
  );
  final edges = <SchematicEdge>[
    for (final id in <int>[..._busNetIds, _singleNetId])
      SchematicEdge(
        id: 'e_${id}_0',
        sourcePortId: 'u_ff:Q$id',
        targetPortId: 'sink:$id',
        netId: id,
      ),
  ];
  return SchematicGraph(
    moduleName: 'cdc_capture',
    cells: <SchematicCell>[cell],
    boundaryPorts: const <SchematicBoundaryPort>[],
    edges: edges,
  );
}

/// Builds the laid-out graph the painter renders. Every bus strand and the
/// single-bit net get a routed polyline whose id encodes its net id (the
/// `e_<netId>_<counter>` scheme [EdgeRoute.netId] parses).
LaidOutGraph _laidOut() {
  final routes = <EdgeRoute>[
    for (final id in <int>[..._busNetIds, _singleNetId])
      EdgeRoute(
        id: 'e_${id}_7',
        points: <LayoutPoint>[
          LayoutPoint(80, 20.0 + id),
          LayoutPoint(160, 20.0 + id),
        ],
      ),
  ];
  final layout = NetlistLayout(
    nodes: const <NodePosition>[
      NodePosition(
        id: 'u_ff',
        bounds: BoundingBox(x: 20, y: 20, width: 60, height: 60),
      ),
    ],
    edges: routes,
    bounds: const BoundingBox(x: 0, y: 0, width: 200, height: 120),
  );
  return LaidOutGraph(graph: _graph(), layout: layout);
}

/// The 3-bit `sample_a` bus: three [NetBit]s plus a constant bit that has
/// no drawn edge (proving constants are skipped, not counted).
Net _busNet() => Net(
  name: 'sample_a',
  bits: <BitRef>[
    for (final id in _busNetIds) NetBit(id),
    const ConstantBit(ConstantBitValue.zero),
  ],
  attributes: const <String, String>{},
);

/// A 1-bit net.
Net _singleNet() => const Net(
  name: 'req_b0',
  bits: <BitRef>[NetBit(_singleNetId)],
  attributes: <String, String>{},
);

/// Paints [laidOut] with [selection] through the real render object and
/// counts how many edges were stroked with the bright selected-wire CORE
/// color — i.e. how many strands got the selection accent.
int _accentedEdgeCount(LaidOutGraph laidOut, Selection selection) {
  final renderObject = SchematicCanvasRenderObject(
    laidOut: laidOut,
    transform: ViewportTransform.identity,
    theme: ThemeData.light(),
    selection: selection,
    statsSink: const NoopRenderStatsSink(),
  )..layout(BoxConstraints.tight(const Size(400, 200)));
  final context = TestRecordingPaintingContext(TestRecordingCanvas());
  renderObject.paint(context, Offset.zero);
  final canvas = context.canvas as TestRecordingCanvas;
  final core = NetcruxColors.selectedWireCore.toARGB32();
  var count = 0;
  for (final recorded in canvas.invocations) {
    final invocation = recorded.invocation;
    if (invocation.memberName == #drawPath) {
      final paint = invocation.positionalArguments[1] as Paint;
      if (paint.color.toARGB32() == core) count++;
    }
  }
  return count;
}

void main() {
  group('whole-net (bus) selection highlight', () {
    test('selecting an 8-bit-style bus accents EVERY drawn strand', () {
      final selection = buildWholeNetWireSelection(_busNet(), _graph());
      expect(selection, isNotNull);
      // One wire element per drawn bit — the constant bit is dropped.
      expect(selection!.length, _busNetIds.length);
      // The primary is the first drawn bit (what the CXP name resolver
      // reverse-resolves to `cdc_capture.sample_a`).
      expect(selection.primary, isA<SelectedElementWire>());
      expect(
        (selection.primary as SelectedElementWire).netId,
        _busNetIds.first,
      );
      // The painter lights all three strands, not one.
      expect(_accentedEdgeCount(_laidOut(), selection), _busNetIds.length);
    });

    test('selecting a single-bit net accents exactly one edge', () {
      final selection = buildWholeNetWireSelection(_singleNet(), _graph());
      expect(selection, isNotNull);
      expect(selection!.length, 1);
      expect(_accentedEdgeCount(_laidOut(), selection), 1);
    });

    test('a net with no drawn edge yields no selection', () {
      const undrawn = Net(
        name: 'dangling',
        bits: <BitRef>[NetBit(999)],
        attributes: <String, String>{},
      );
      expect(buildWholeNetWireSelection(undrawn, _graph()), isNull);
    });

    test('selected strands use the bright core color, not the old amber '
        'selectionAccent', () {
      final selection = buildWholeNetWireSelection(_busNet(), _graph())!;
      final renderObject = SchematicCanvasRenderObject(
        laidOut: _laidOut(),
        transform: ViewportTransform.identity,
        theme: ThemeData.light(),
        selection: selection,
        statsSink: const NoopRenderStatsSink(),
      )..layout(BoxConstraints.tight(const Size(400, 200)));
      final context = TestRecordingPaintingContext(TestRecordingCanvas());
      renderObject.paint(context, Offset.zero);
      final canvas = context.canvas as TestRecordingCanvas;
      final core = NetcruxColors.selectedWireCore.toARGB32();
      final glow = NetcruxColors.selectedWireGlow.toARGB32();
      final oldAccent = NetcruxColors.selectionAccent.toARGB32();
      var sawCore = false;
      var sawGlow = false;
      var maxSelectedStroke = 0.0;
      for (final recorded in canvas.invocations) {
        final invocation = recorded.invocation;
        if (invocation.memberName != #drawPath) continue;
        final paint = invocation.positionalArguments[1] as Paint;
        final argb = paint.color.toARGB32();
        // No wire should be stroked with the old low-contrast amber accent.
        expect(argb == oldAccent, isFalse);
        if (argb == core) {
          sawCore = true;
          maxSelectedStroke = maxSelectedStroke > paint.strokeWidth
              ? maxSelectedStroke
              : paint.strokeWidth;
        }
        if (argb == glow) sawGlow = true;
      }
      expect(sawCore, isTrue, reason: 'bright core stroke must be drawn');
      expect(sawGlow, isTrue, reason: 'glow underlay must be drawn');
      // The selected core is far wider than the 1.2 base wire stroke.
      expect(maxSelectedStroke, greaterThan(3.0));
    });
  });
}
