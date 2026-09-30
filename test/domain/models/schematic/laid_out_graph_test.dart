// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/layout/bounding_box.dart';
import 'package:netcrux/domain/models/layout/edge_route.dart';
import 'package:netcrux/domain/models/layout/netlist_layout.dart';
import 'package:netcrux/domain/models/layout/node_position.dart';
import 'package:netcrux/domain/models/netlist/port_direction.dart';
import 'package:netcrux/domain/models/schematic/laid_out_graph.dart';
import 'package:netcrux/domain/models/schematic/schematic_graph.dart';

void main() {
  group('LaidOutGraph', () {
    test('empty is empty', () {
      expect(LaidOutGraph.empty.isEmpty, isTrue);
      expect(LaidOutGraph.empty.graph, SchematicGraph.empty);
      expect(LaidOutGraph.empty.layout.nodes, isEmpty);
    });

    test('isEmpty true when layout is empty even with non-empty graph', () {
      const graph = SchematicGraph(
        moduleName: 'm',
        cells: <SchematicCell>[],
        boundaryPorts: <SchematicBoundaryPort>[
          SchematicBoundaryPort(
            id: 'port:a',
            name: 'a',
            direction: PortDirection.input,
            width: 1,
          ),
        ],
        edges: <SchematicEdge>[],
      );
      const empty = NetlistLayout(
        nodes: <NodePosition>[],
        edges: <EdgeRoute>[],
        bounds: BoundingBox(x: 0, y: 0, width: 0, height: 0),
      );
      const pair = LaidOutGraph(graph: graph, layout: empty);
      expect(pair.isEmpty, isTrue);
    });

    test('equality compares both halves', () {
      const layout = NetlistLayout(
        nodes: <NodePosition>[
          NodePosition(
            id: 'u_and',
            bounds: BoundingBox(x: 10, y: 20, width: 60, height: 40),
          ),
        ],
        edges: <EdgeRoute>[],
        bounds: BoundingBox(x: 0, y: 0, width: 100, height: 100),
      );
      const graph = SchematicGraph(
        moduleName: 'm',
        cells: <SchematicCell>[],
        boundaryPorts: <SchematicBoundaryPort>[],
        edges: <SchematicEdge>[],
      );
      const a = LaidOutGraph(graph: graph, layout: layout);
      const b = LaidOutGraph(graph: graph, layout: layout);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('toString carries the module name and counts', () {
      const layout = NetlistLayout(
        nodes: <NodePosition>[
          NodePosition(
            id: 'u_and',
            bounds: BoundingBox(x: 10, y: 20, width: 60, height: 40),
          ),
        ],
        edges: <EdgeRoute>[],
        bounds: BoundingBox(x: 0, y: 0, width: 100, height: 100),
      );
      const graph = SchematicGraph(
        moduleName: 'and2',
        cells: <SchematicCell>[],
        boundaryPorts: <SchematicBoundaryPort>[],
        edges: <SchematicEdge>[],
      );
      const pair = LaidOutGraph(graph: graph, layout: layout);
      expect(pair.toString(), contains('and2'));
      expect(pair.toString(), contains('1 nodes'));
    });
  });
}
