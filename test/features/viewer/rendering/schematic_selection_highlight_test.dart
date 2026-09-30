// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Regression: a wire selection must paint the schematic selection accent
// even when the selected edge id came from a DIFFERENTLY-NUMBERED graph
// than the one the canvas laid out.
//
// The bug: the laid-out edge ids (from `buildElkInput`) and the schematic
// graph's edge ids (from `SchematicGraphBuilder`) are numbered by two
// independent global counters, so the same net is `e_<netId>_<a>` in one
// and `e_<netId>_<b>` in the other. The CDC row-tap probe and the CXP
// inbound handler both resolve a wire against a freshly-built graph and
// hand the painter that graph's edge id — which is absent from the
// laid-out edges the painter draws, so the accent never appeared. The fix
// matches wire selections by net id (stable across both id counters).
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
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/domain/models/selection/selection.dart';
import 'package:netcrux/features/viewer/rendering/schematic_painter.dart';

/// A one-net design whose LAID-OUT edge id (`e_15_3`) deliberately
/// differs from the SCHEMATIC-GRAPH edge id (`e_15_0`) for the very same
/// net (id 15) — reproducing the two-counter divergence. Both carry the
/// `e_<netId>_<counter>` form the real builders emit, so [EdgeRoute.netId]
/// parses 15 off the laid-out edge.
LaidOutGraph _divergentIdGraph() {
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
    id: 'port:sample_a',
    name: 'sample_a',
    direction: PortDirection.output,
    width: 1,
  );
  const graph = SchematicGraph(
    moduleName: 'cdc_capture',
    cells: <SchematicCell>[cell],
    boundaryPorts: <SchematicBoundaryPort>[boundary],
    edges: <SchematicEdge>[
      // Fresh-build id the probe/inbound handler resolves for net 15.
      SchematicEdge(
        id: 'e_15_0',
        sourcePortId: 'u_ff:Q',
        targetPortId: 'port:sample_a',
        netId: 15,
      ),
    ],
  );
  const layout = NetlistLayout(
    nodes: <NodePosition>[
      NodePosition(
        id: 'u_ff',
        bounds: BoundingBox(x: 20, y: 20, width: 60, height: 40),
        ports: <String, BoundingBox>{
          'u_ff:Q': BoundingBox(x: 56, y: 28, width: 4, height: 4),
        },
      ),
      NodePosition(
        id: 'port:sample_a',
        bounds: BoundingBox(x: 160, y: 24, width: 16, height: 16),
      ),
    ],
    edges: <EdgeRoute>[
      // ELK-numbered id for the SAME net 15 — different counter (`_3`).
      EdgeRoute(
        id: 'e_15_3',
        points: <LayoutPoint>[
          LayoutPoint(80, 40),
          LayoutPoint(120, 40),
          LayoutPoint(160, 32),
        ],
      ),
    ],
    bounds: BoundingBox(x: 0, y: 0, width: 200, height: 100),
  );
  return const LaidOutGraph(graph: graph, layout: layout);
}

/// Paints [graph] with [selection] and reports whether any wire was
/// stroked with the selection accent — i.e. the highlight is visible.
bool _paintsWireAccent(LaidOutGraph graph, Selection selection) {
  final renderObject = SchematicCanvasRenderObject(
    laidOut: graph,
    transform: ViewportTransform.identity,
    theme: ThemeData.light(),
    selection: selection,
    statsSink: const NoopRenderStatsSink(),
  )..layout(BoxConstraints.tight(const Size(400, 200)));
  final context = TestRecordingPaintingContext(TestRecordingCanvas());
  renderObject.paint(context, Offset.zero);
  final canvas = context.canvas as TestRecordingCanvas;
  // A selected wire is drawn with the bright near-white core (over an
  // amber glow underlay). The core color is the selection's identifying
  // stroke, so it is what proves the highlight is visible.
  final core = NetcruxColors.selectedWireCore.toARGB32();
  for (final recorded in canvas.invocations) {
    final invocation = recorded.invocation;
    if (invocation.memberName == #drawPath) {
      final paint = invocation.positionalArguments[1] as Paint;
      if (paint.color.toARGB32() == core) return true;
    }
  }
  return false;
}

void main() {
  group('wire selection highlight', () {
    test(
      'row-tap / inbound path: a selection keyed by the GRAPH edge id '
      '(e_15_0) still paints the accent on the LAID-OUT edge (e_15_3) '
      'via net-id matching',
      () {
        final graph = _divergentIdGraph();
        // This is exactly what AnalysisSelectionProbe.selectNet and the
        // CXP inbound net handler produce: the freshly-built graph edge
        // id, plus the real net id.
        final selection = Selection.single(
          const SelectedElement.wire(edgeId: 'e_15_0', netId: 15),
        );
        expect(_paintsWireAccent(graph, selection), isTrue);
      },
    );

    test(
      'canvas-click path: a selection keyed by the LAID-OUT edge id '
      '(e_15_3) paints the accent directly',
      () {
        final graph = _divergentIdGraph();
        final selection = Selection.single(
          const SelectedElement.wire(edgeId: 'e_15_3', netId: 15),
        );
        expect(_paintsWireAccent(graph, selection), isTrue);
      },
    );

    test('an unrelated net id does not paint any wire accent', () {
      final graph = _divergentIdGraph();
      final selection = Selection.single(
        const SelectedElement.wire(edgeId: 'e_99_0', netId: 99),
      );
      expect(_paintsWireAccent(graph, selection), isFalse);
    });

    test('a negative sentinel net id never matches a real edge', () {
      final graph = _divergentIdGraph();
      final selection = Selection.single(
        const SelectedElement.wire(edgeId: 'nope', netId: -1),
      );
      expect(_paintsWireAccent(graph, selection), isFalse);
    });
  });
}
