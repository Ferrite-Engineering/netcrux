// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/interfaces/cone_of_influence_service.dart';
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

/// The open-core COI/X-trace paths must hold a 100K-cell scope without
/// choking. This drives a 100 000-cell synthetic
/// graph through the open-core default ([NoopConeOfInfluenceService]'s
/// `computeAsync` seam) and the open-core one-hop [TraceService], asserting
/// correctness + termination within a generous `Timeout`. The deep-BFS
/// 100K-scale correctness test lives in the Pro suite (`isolate_coi_service_test`)
/// where the real cone algorithm runs.
void main() {
  late LaidOutGraph hugeGraph;

  setUpAll(() {
    hugeGraph = _chainGraph(100000);
  });

  test(
    'open-core COI seam (Noop) terminates + stays empty on a 100K scope',
    () async {
      const service = NoopConeOfInfluenceService();
      final overlay = await service.computeAsync(
        ConeOfInfluenceRequest(
          laidOut: hugeGraph,
          selection: const SelectedElement.cell(cellId: 'ff0'),
          mode: ConeOfInfluenceMode.fanout,
          depth: null,
        ),
      );
      expect(overlay.isEmpty, isTrue);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'open-core one-hop TraceService terminates + is correct on a 100K scope',
    () {
      const service = TraceService();
      // Fanout from ff0 reaches its single immediate load (ff1) in one hop.
      final overlay = service.compute(
        laidOut: hugeGraph,
        selection: const SelectedElement.cell(cellId: 'ff0'),
        mode: TraceOverlayMode.fanout,
      );
      expect(overlay.isEmpty, isFalse);
      expect(overlay.highlightedCellIds, contains('ff1'));
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}

/// An `n`-cell chain: `ff_i.Q → ff_{i+1}.D`. Minimal objects so building the
/// 100K graph stays fast.
LaidOutGraph _chainGraph(int n) {
  final cells = <SchematicCell>[];
  final nodes = <NodePosition>[];
  final edges = <SchematicEdge>[];
  final routes = <EdgeRoute>[];
  for (var i = 0; i < n; i++) {
    final id = 'ff$i';
    cells.add(
      SchematicCell(
        id: id,
        kind: CellKind.flipFlop,
        type: r'$_DFF_P_',
        ports: <SchematicPort>[
          SchematicPort(
            id: '$id:D',
            name: 'D',
            direction: PortDirection.input,
            side: SchematicPortSide.west,
          ),
          SchematicPort(
            id: '$id:Q',
            name: 'Q',
            direction: PortDirection.output,
            side: SchematicPortSide.east,
          ),
        ],
      ),
    );
    nodes.add(
      NodePosition(
        id: id,
        bounds: BoundingBox(x: i * 80.0, y: 0, width: 60, height: 40),
      ),
    );
    if (i > 0) {
      edges.add(
        SchematicEdge(
          id: 'e$i',
          sourcePortId: 'ff${i - 1}:Q',
          targetPortId: '$id:D',
          netId: i,
        ),
      );
      routes.add(EdgeRoute(id: 'e$i', points: const <LayoutPoint>[]));
    }
  }
  return LaidOutGraph(
    graph: SchematicGraph(
      moduleName: 'chain_$n',
      cells: cells,
      boundaryPorts: const <SchematicBoundaryPort>[],
      edges: edges,
    ),
    layout: NetlistLayout(
      nodes: nodes,
      edges: routes,
      bounds: BoundingBox(x: 0, y: 0, width: n * 80.0, height: 40),
    ),
  );
}
