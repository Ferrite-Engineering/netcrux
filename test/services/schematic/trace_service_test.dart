// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/layout/bounding_box.dart';
import 'package:netcrux/domain/models/layout/edge_route.dart';
import 'package:netcrux/domain/models/layout/netlist_layout.dart';
import 'package:netcrux/domain/models/layout/node_position.dart';
import 'package:netcrux/domain/models/netlist/port_direction.dart';
import 'package:netcrux/domain/models/schematic/cell_kind.dart';
import 'package:netcrux/domain/models/schematic/laid_out_graph.dart';
import 'package:netcrux/domain/models/schematic/schematic_graph.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/domain/models/trace/trace_overlay.dart';
import 'package:netcrux/services/schematic/trace_service.dart';

// ── Test fixture: A → C ← B (two drivers, one sink). ──────────────
// Cells: cA (Y -> n1), cB (Y -> n1), cC (A <- n1). Boundary port:
// port:out drives nothing (we don't exercise boundary here).
LaidOutGraph _fixture() {
  final cells = <SchematicCell>[
    const SchematicCell(
      id: 'cA',
      kind: CellKind.generic,
      type: 'driverA',
      ports: <SchematicPort>[
        SchematicPort(
          id: 'cA:Y',
          name: 'Y',
          direction: PortDirection.output,
          side: SchematicPortSide.east,
        ),
      ],
    ),
    const SchematicCell(
      id: 'cB',
      kind: CellKind.generic,
      type: 'driverB',
      ports: <SchematicPort>[
        SchematicPort(
          id: 'cB:Y',
          name: 'Y',
          direction: PortDirection.output,
          side: SchematicPortSide.east,
        ),
      ],
    ),
    const SchematicCell(
      id: 'cC',
      kind: CellKind.generic,
      type: 'sinkC',
      ports: <SchematicPort>[
        SchematicPort(
          id: 'cC:A',
          name: 'A',
          direction: PortDirection.input,
          side: SchematicPortSide.west,
        ),
      ],
    ),
  ];
  const edges = <SchematicEdge>[
    SchematicEdge(
      id: 'e_1_0',
      sourcePortId: 'cA:Y',
      targetPortId: 'cC:A',
      netId: 1,
    ),
    SchematicEdge(
      id: 'e_1_1',
      sourcePortId: 'cB:Y',
      targetPortId: 'cC:A',
      netId: 1,
    ),
  ];
  const layout = NetlistLayout(
    bounds: BoundingBox(x: 0, y: 0, width: 300, height: 200),
    nodes: <NodePosition>[
      NodePosition(
        id: 'cA',
        bounds: BoundingBox(x: 0, y: 0, width: 60, height: 40),
      ),
      NodePosition(
        id: 'cB',
        bounds: BoundingBox(x: 0, y: 80, width: 60, height: 40),
      ),
      NodePosition(
        id: 'cC',
        bounds: BoundingBox(x: 200, y: 40, width: 60, height: 40),
      ),
    ],
    edges: <EdgeRoute>[
      EdgeRoute(
        id: 'e_1_0',
        points: [LayoutPoint(60, 20), LayoutPoint(200, 60)],
        sourceNodeId: 'cA',
        targetNodeId: 'cC',
      ),
      EdgeRoute(
        id: 'e_1_1',
        points: [LayoutPoint(60, 100), LayoutPoint(200, 60)],
        sourceNodeId: 'cB',
        targetNodeId: 'cC',
      ),
    ],
  );
  return LaidOutGraph(
    graph: SchematicGraph(
      moduleName: 'top',
      cells: cells,
      boundaryPorts: const [],
      edges: edges,
    ),
    layout: layout,
  );
}

void main() {
  group('TraceService', () {
    test('returns empty overlay on none selection', () {
      final overlay = const TraceService().compute(
        laidOut: _fixture(),
        selection: const SelectedElement.none(),
        mode: TraceOverlayMode.fanin,
      );
      expect(overlay.isEmpty, isTrue);
    });

    test('fanin of cC includes both drivers and both edges', () {
      final overlay = const TraceService().compute(
        laidOut: _fixture(),
        selection: const SelectedElement.cell(cellId: 'cC'),
        mode: TraceOverlayMode.fanin,
      );
      expect(overlay.mode, TraceOverlayMode.fanin);
      expect(
        overlay.highlightedCellIds,
        containsAll(<String>['cA', 'cB', 'cC']),
      );
      expect(
        overlay.highlightedEdgeIds,
        containsAll(<String>['e_1_0', 'e_1_1']),
      );
    });

    test('fanout of cA includes cC and the edge from cA', () {
      final overlay = const TraceService().compute(
        laidOut: _fixture(),
        selection: const SelectedElement.cell(cellId: 'cA'),
        mode: TraceOverlayMode.fanout,
      );
      expect(overlay.highlightedCellIds, contains('cA'));
      expect(overlay.highlightedCellIds, contains('cC'));
      expect(overlay.highlightedEdgeIds, contains('e_1_0'));
      // cB is NOT a fanout of cA — it's a co-driver but doesn't sink
      // anything that cA reaches.
      expect(overlay.highlightedCellIds.contains('cB'), isFalse);
    });

    test('selecting a port returns that side of the trace', () {
      final overlay = const TraceService().compute(
        laidOut: _fixture(),
        selection: const SelectedElement.port(
          cellId: 'cA',
          portId: 'cA:Y',
          portName: 'Y',
        ),
        mode: TraceOverlayMode.fanout,
      );
      expect(overlay.highlightedEdgeIds, contains('e_1_0'));
    });
  });

  group('TraceService with Yosys-generated cell names', () {
    // A Yosys cell name carries its source location, colons included.
    const and = r'$and$alu.v:42$7';
    const mux = r'$procmux$1851';
    const laidOut = LaidOutGraph(
      graph: SchematicGraph(
        moduleName: 'alu',
        cells: <SchematicCell>[
          SchematicCell(
            id: and,
            kind: CellKind.andGate,
            type: r'$and',
            ports: <SchematicPort>[
              SchematicPort(
                id: '$and:Y',
                name: 'Y',
                direction: PortDirection.output,
                side: SchematicPortSide.east,
              ),
            ],
          ),
          SchematicCell(
            id: mux,
            kind: CellKind.mux,
            type: r'$mux',
            ports: <SchematicPort>[
              SchematicPort(
                id: '$mux:A',
                name: 'A',
                direction: PortDirection.input,
                side: SchematicPortSide.west,
              ),
            ],
          ),
        ],
        boundaryPorts: <SchematicBoundaryPort>[],
        edges: <SchematicEdge>[
          SchematicEdge(
            id: 'e_9_0',
            sourcePortId: '$and:Y',
            targetPortId: '$mux:A',
            netId: 9,
          ),
        ],
      ),
      layout: NetlistLayout(
        nodes: <NodePosition>[
          NodePosition(
            id: and,
            bounds: BoundingBox(x: 0, y: 0, width: 60, height: 40),
          ),
          NodePosition(
            id: mux,
            bounds: BoundingBox(x: 200, y: 0, width: 60, height: 40),
          ),
        ],
        edges: <EdgeRoute>[],
        bounds: BoundingBox(x: 0, y: 0, width: 260, height: 40),
      ),
    );

    test('a fanin lights the driver by its whole name', () {
      final overlay = const TraceService().compute(
        laidOut: laidOut,
        selection: const SelectedElement.cell(cellId: mux),
        mode: TraceOverlayMode.fanin,
      );
      expect(overlay.highlightedCellIds, <String>{mux, and});
    });

    test('a wire lights both of its cells', () {
      final overlay = const TraceService().compute(
        laidOut: laidOut,
        selection: const SelectedElement.wire(edgeId: 'e_9_0', netId: 9),
        mode: TraceOverlayMode.fanout,
      );
      expect(overlay.highlightedCellIds, <String>{mux, and});
    });
  });

  group('TraceOverlay', () {
    test('empty equals empty', () {
      expect(TraceOverlay.empty == TraceOverlay.empty, isTrue);
      expect(TraceOverlay.empty.hashCode, TraceOverlay.empty.hashCode);
    });

    test('highlightsCell / Edge / BoundaryPort respect the sets', () {
      const overlay = TraceOverlay(
        mode: TraceOverlayMode.fanin,
        highlightedCellIds: <String>{'a', 'b'},
        highlightedEdgeIds: <String>{'e1'},
        highlightedBoundaryPortIds: <String>{'port:clk'},
      );
      expect(overlay.highlightsCell('a'), isTrue);
      expect(overlay.highlightsCell('z'), isFalse);
      expect(overlay.highlightsEdge('e1'), isTrue);
      expect(overlay.highlightsBoundaryPort('port:clk'), isTrue);
      expect(overlay.isEmpty, isFalse);
    });
  });
}
