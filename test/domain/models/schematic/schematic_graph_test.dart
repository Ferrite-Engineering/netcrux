// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/netlist/port_direction.dart';
import 'package:netcrux/domain/models/schematic/cell_kind.dart';
import 'package:netcrux/domain/models/schematic/schematic_graph.dart';

void main() {
  group('SchematicPort', () {
    test('equality and hashing compare all observable fields', () {
      const a = SchematicPort(
        id: 'u_and:A',
        name: 'A',
        direction: PortDirection.input,
        side: SchematicPortSide.west,
      );
      const b = SchematicPort(
        id: 'u_and:A',
        name: 'A',
        direction: PortDirection.input,
        side: SchematicPortSide.west,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });

  group('SchematicCell', () {
    test('displayLabel falls back to id when label is null', () {
      const cell = SchematicCell(
        id: 'u_and',
        kind: CellKind.andGate,
        type: r'$and',
        ports: <SchematicPort>[],
      );
      expect(cell.displayLabel, 'u_and');
    });

    test('displayLabel uses label when provided', () {
      const cell = SchematicCell(
        id: 'u_and',
        kind: CellKind.andGate,
        type: r'$and',
        ports: <SchematicPort>[],
        label: 'AND',
      );
      expect(cell.displayLabel, 'AND');
    });

    test('equality covers all fields including ports list', () {
      const portA = SchematicPort(
        id: 'u_and:A',
        name: 'A',
        direction: PortDirection.input,
        side: SchematicPortSide.west,
      );
      const cellA = SchematicCell(
        id: 'u_and',
        kind: CellKind.andGate,
        type: r'$and',
        ports: <SchematicPort>[portA],
      );
      const cellB = SchematicCell(
        id: 'u_and',
        kind: CellKind.andGate,
        type: r'$and',
        ports: <SchematicPort>[portA],
      );
      expect(cellA, cellB);
      expect(cellA.hashCode, cellB.hashCode);
    });
  });

  group('SchematicGraph.empty', () {
    test('isEmpty true for the empty const', () {
      expect(SchematicGraph.empty.isEmpty, isTrue);
      expect(SchematicGraph.empty.moduleName, '');
      expect(SchematicGraph.empty.cells, isEmpty);
      expect(SchematicGraph.empty.boundaryPorts, isEmpty);
      expect(SchematicGraph.empty.edges, isEmpty);
    });

    test('isEmpty false when any list is non-empty', () {
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
      expect(graph.isEmpty, isFalse);
    });
  });

  group('SchematicGraph equality', () {
    test('graphs with the same fields compare equal', () {
      const portA = SchematicBoundaryPort(
        id: 'port:a',
        name: 'a',
        direction: PortDirection.input,
        width: 1,
      );
      const graphA = SchematicGraph(
        moduleName: 'm',
        cells: <SchematicCell>[],
        boundaryPorts: <SchematicBoundaryPort>[portA],
        edges: <SchematicEdge>[],
      );
      const graphB = SchematicGraph(
        moduleName: 'm',
        cells: <SchematicCell>[],
        boundaryPorts: <SchematicBoundaryPort>[portA],
        edges: <SchematicEdge>[],
      );
      expect(graphA, graphB);
      expect(graphA.hashCode, graphB.hashCode);
    });

    test('different module names compare unequal', () {
      const portA = SchematicBoundaryPort(
        id: 'port:a',
        name: 'a',
        direction: PortDirection.input,
        width: 1,
      );
      const graphA = SchematicGraph(
        moduleName: 'm',
        cells: <SchematicCell>[],
        boundaryPorts: <SchematicBoundaryPort>[portA],
        edges: <SchematicEdge>[],
      );
      const graphB = SchematicGraph(
        moduleName: 'n',
        cells: <SchematicCell>[],
        boundaryPorts: <SchematicBoundaryPort>[portA],
        edges: <SchematicEdge>[],
      );
      expect(graphA, isNot(equals(graphB)));
    });
  });

  group('SchematicGraph edge index', () {
    test('findEdge returns the edge by id and null for unknown ids', () {
      const graph = SchematicGraph(
        moduleName: 'm',
        cells: <SchematicCell>[],
        boundaryPorts: <SchematicBoundaryPort>[],
        edges: <SchematicEdge>[
          SchematicEdge(
            id: 'e0',
            sourcePortId: 'a:Y',
            targetPortId: 'b:A',
            netId: 7,
          ),
          SchematicEdge(
            id: 'e1',
            sourcePortId: 'b:Y',
            targetPortId: 'c:A',
            netId: 9,
          ),
        ],
      );
      expect(graph.findEdge('e0')?.netId, 7);
      expect(graph.findEdge('e1')?.netId, 9);
      expect(graph.findEdge('nope'), isNull);
      // The index is memoized per instance — a repeat lookup returns
      // the identical object, not a rebuilt one.
      expect(identical(graph.findEdge('e0'), graph.findEdge('e0')), isTrue);
    });

    test('findEdge keeps the first entry on duplicate ids', () {
      const graph = SchematicGraph(
        moduleName: 'm',
        cells: <SchematicCell>[],
        boundaryPorts: <SchematicBoundaryPort>[],
        edges: <SchematicEdge>[
          SchematicEdge(
            id: 'dup',
            sourcePortId: 'a:Y',
            targetPortId: 'b:A',
            netId: 1,
          ),
          SchematicEdge(
            id: 'dup',
            sourcePortId: 'c:Y',
            targetPortId: 'd:A',
            netId: 2,
          ),
        ],
      );
      expect(graph.findEdge('dup')?.netId, 1);
    });

    test('empty graph has no edges to find', () {
      expect(SchematicGraph.empty.findEdge('e0'), isNull);
    });
  });
}
