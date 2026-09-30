// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/netlist/hierarchy_node.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/netlist/port_direction.dart';
import 'package:netcrux/domain/models/schematic/cell_kind.dart';
import 'package:netcrux/domain/models/schematic/schematic_graph.dart';
import 'package:netcrux/services/schematic/schematic_graph_builder.dart';
import 'package:netcrux/services/yosys/yosys_json_parser.dart';

NetlistModel _loadFixture(String name) {
  final raw = File(
    'test/fixtures/verilog/$name.expected.json',
  ).readAsStringSync();
  return const YosysJsonParser().parse(raw);
}

void main() {
  const builder = SchematicGraphBuilder();

  group('SchematicGraphBuilder.build — empty / missing scope', () {
    test('returns empty graph when node fails to resolve', () {
      final model = _loadFixture('and2');
      const stale = HierarchyNode(
        path: <String>['gone'],
        moduleName: 'nonexistent',
      );
      expect(builder.build(model, stale), SchematicGraph.empty);
    });
  });

  group('SchematicGraphBuilder.build — and2 fixture', () {
    test('one AND cell with three ports, three boundary ports, two edges', () {
      final model = _loadFixture('and2');
      final root = HierarchyNode.rootOf(model)!;
      final graph = builder.build(model, root);

      expect(graph.moduleName, 'and2');
      expect(graph.cells, hasLength(1));
      final cell = graph.cells.single;
      expect(cell.id, 'u_and');
      expect(cell.type, r'$and');
      expect(cell.kind, CellKind.andGate);
      expect(cell.ports, hasLength(3));

      // A, B → west (inputs); Y → east (output).
      final byName = <String, SchematicPort>{
        for (final p in cell.ports) p.name: p,
      };
      expect(byName['A']!.side, SchematicPortSide.west);
      expect(byName['B']!.side, SchematicPortSide.west);
      expect(byName['Y']!.side, SchematicPortSide.east);
      expect(byName['Y']!.direction, PortDirection.output);

      // Three boundary ports.
      expect(graph.boundaryPorts, hasLength(3));
      final boundaryNames = graph.boundaryPorts.map((p) => p.name).toSet();
      expect(boundaryNames, containsAll(<String>{'a', 'b', 'y'}));

      // Edges: a→u_and:A, b→u_and:B, u_and:Y→y. The intersection
      // approach gives one edge per driver/sink pairing.
      final edgePairs = graph.edges
          .map((e) => '${e.sourcePortId}→${e.targetPortId}')
          .toSet();
      expect(edgePairs, contains('port:a→u_and:A'));
      expect(edgePairs, contains('port:b→u_and:B'));
      expect(edgePairs, contains('u_and:Y→port:y'));
    });
  });

  group('SchematicGraphBuilder.build — fsm fixture', () {
    test(r'classifies the $adff state register as a flipFlop', () {
      final model = _loadFixture('fsm');
      final root = HierarchyNode.rootOf(model)!;
      final graph = builder.build(model, root);

      expect(graph.moduleName, 'fsm');

      final byId = <String, SchematicCell>{
        for (final c in graph.cells) c.id: c,
      };
      expect(byId['state_reg']!.kind, CellKind.flipFlop);
      expect(byId['done_eq']!.kind, CellKind.generic);
      expect(byId['next_logic']!.kind, CellKind.mux);
    });

    test('produces non-empty boundary port set and at least one edge', () {
      final model = _loadFixture('fsm');
      final root = HierarchyNode.rootOf(model)!;
      final graph = builder.build(model, root);

      expect(
        graph.boundaryPorts.map((p) => p.name).toSet(),
        containsAll(<String>{'clk', 'rst', 'go', 'done'}),
      );
      expect(graph.edges, isNotEmpty);

      // Specifically: the clk net (id 2) reaches state_reg's CLK pin.
      final clkEdges = graph.edges
          .where(
            (e) =>
                e.sourcePortId == 'port:clk' &&
                e.targetPortId == 'state_reg:CLK',
          )
          .toList();
      expect(clkEdges, hasLength(1));
    });

    test('skips self-loop edges (constant bits never connect)', () {
      final model = _loadFixture('fsm');
      final root = HierarchyNode.rootOf(model)!;
      final graph = builder.build(model, root);
      // No edge should have identical endpoints.
      for (final edge in graph.edges) {
        expect(
          edge.sourcePortId,
          isNot(edge.targetPortId),
          reason: 'edge ${edge.id} is a self-loop',
        );
      }
    });
  });

  group('SchematicGraphBuilder.build — adder4 fixture', () {
    test(r'two $add cells, both classified generic, multi-bit edges', () {
      final model = _loadFixture('adder4');
      final root = HierarchyNode.rootOf(model)!;
      final graph = builder.build(model, root);

      expect(graph.moduleName, 'adder4');
      final addCells = graph.cells.where((c) => c.type == r'$add').toList();
      expect(addCells, hasLength(2));
      for (final c in addCells) {
        expect(c.kind, CellKind.generic);
      }

      // Boundary port widths reflect the source declaration: a/b/sum
      // are 4-bit, cin/cout are 1-bit.
      final boundary = <String, SchematicBoundaryPort>{
        for (final p in graph.boundaryPorts) p.name: p,
      };
      expect(boundary['a']!.width, 4);
      expect(boundary['sum']!.width, 4);
      expect(boundary['cin']!.width, 1);
    });
  });
}
