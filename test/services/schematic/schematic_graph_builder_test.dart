// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/netlist/bit_ref.dart';
import 'package:netcrux/domain/models/netlist/hierarchy_node.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/netlist/port_direction.dart';
import 'package:netcrux/domain/models/schematic/cell_kind.dart';
import 'package:netcrux/domain/models/schematic/pin_tie.dart';
import 'package:netcrux/domain/models/schematic/schematic_graph.dart';
import 'package:netcrux/services/schematic/schematic_graph_builder.dart';
import 'package:netcrux/services/yosys/streaming_yosys_json_reader.dart';
import 'package:netcrux/services/yosys/yosys_json_parser.dart';

NetlistModel _loadFixture(String name) {
  final raw = File(
    'test/fixtures/verilog/$name.expected.json',
  ).readAsStringSync();
  return const YosysJsonParser().parse(raw);
}

/// A multiplier whose `B` input reads net 7, which nothing drives: the
/// dangling input behind a nextpnr crash in the beta. `A` is on a module
/// input, and `u_and` has `B` tied to `x` and `A` to `1`.
const _danglingMulJson = <String, Object?>{
  'creator': 'hand-built',
  'modules': <String, Object?>{
    'top': <String, Object?>{
      'attributes': <String, Object?>{'top': '1'},
      'ports': <String, Object?>{
        'a': <String, Object?>{
          'direction': 'input',
          'bits': <Object>[2, 3],
        },
        'p': <String, Object?>{
          'direction': 'output',
          'bits': <Object>[4, 5],
        },
      },
      'cells': <String, Object?>{
        'u_mul': <String, Object?>{
          'hide_name': 0,
          'type': r'$mul',
          'parameters': <String, Object?>{},
          'attributes': <String, Object?>{},
          'port_directions': <String, Object?>{
            'A': 'input',
            'B': 'input',
            'Y': 'output',
          },
          'connections': <String, Object?>{
            'A': <Object>[2, 3],
            'B': <Object>[7, 8],
            'Y': <Object>[4, 5],
          },
        },
        'u_and': <String, Object?>{
          'hide_name': 0,
          'type': r'$and',
          'parameters': <String, Object?>{},
          'attributes': <String, Object?>{},
          'port_directions': <String, Object?>{
            'A': 'input',
            'B': 'input',
            'Y': 'output',
          },
          'connections': <String, Object?>{
            'A': <Object>['1'],
            'B': <Object>['x'],
            'Y': <Object>[9],
          },
        },
      },
      'netnames': <String, Object?>{
        'dangling_b': <String, Object?>{
          'hide_name': 0,
          'bits': <Object>[7, 8],
          'attributes': <String, Object?>{},
        },
      },
    },
  },
};

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

  group('SchematicGraphBuilder.build — pin ties', () {
    Map<String, SchematicPort> portsOf(
      SchematicGraph graph,
      String cellId,
    ) => <String, SchematicPort>{
      for (final port in graph.cells.singleWhere((c) => c.id == cellId).ports)
        port.name: port,
    };

    test('a multiplier input on a net nothing drives is undriven', () {
      final model = NetlistModel.fromJson(_danglingMulJson);
      final graph = builder.build(model, HierarchyNode.rootOf(model)!);
      final mul = portsOf(graph, 'u_mul');
      expect(mul['A']!.tie, PinTie.net);
      expect(mul['B']!.tie, PinTie.undriven);
      expect(mul['Y']!.tie, PinTie.net);
      final and = portsOf(graph, 'u_and');
      expect(and['A']!.tie, const PinTie.constant('1'));
      expect(and['B']!.tie, const PinTie.constant('x'));
      expect(and['B']!.tie.isX, isTrue);
    });

    test('a declared port Yosys left out is drawn, unconnected', () {
      final json =
          jsonDecode(jsonEncode(_danglingMulJson)) as Map<String, Object?>;
      final modules = json['modules']! as Map<String, Object?>;
      final top = modules['top']! as Map<String, Object?>;
      final cells = top['cells']! as Map<String, Object?>;
      final cell = cells['u_mul']! as Map<String, Object?>;
      (cell['connections']! as Map<String, Object?>).remove('B');
      (cell['port_directions']! as Map<String, Object?>).remove('B');
      final model = NetlistModel.fromJson(json);
      final graph = builder.build(model, HierarchyNode.rootOf(model)!);
      final mul = graph.cells.singleWhere((c) => c.id == 'u_mul');
      // Declaration order: A, B, Y.
      expect(mul.ports.map((p) => p.name), <String>['A', 'B', 'Y']);
      final b = mul.ports[1];
      expect(b.tie, PinTie.unconnected);
      expect(b.direction, PortDirection.input);
      expect(b.side, SchematicPortSide.west);
    });

    test('pinTieFor: mixed constants read most-significant first', () {
      expect(
        SchematicGraphBuilder.pinTieFor(
          const <BitRef>[
            ConstantBit(ConstantBitValue.one),
            ConstantBit(ConstantBitValue.zero),
            ConstantBit(ConstantBitValue.zero),
          ],
          direction: PortDirection.input,
          drivenNets: const <int>{},
        ),
        const PinTie.constant('001'),
      );
      // A bus with one constant bit is on nets.
      expect(
        SchematicGraphBuilder.pinTieFor(
          const <BitRef>[NetBit(3), ConstantBit(ConstantBitValue.zero)],
          direction: PortDirection.input,
          drivenNets: const <int>{3},
        ),
        PinTie.net,
      );
      // An output or inout is never undriven.
      for (final direction in <PortDirection>[
        PortDirection.output,
        PortDirection.inout,
      ]) {
        expect(
          SchematicGraphBuilder.pinTieFor(
            const <BitRef>[NetBit(3)],
            direction: direction,
            drivenNets: const <int>{},
          ),
          PinTie.net,
        );
      }
    });

    group('serv_ice40', () {
      late NetlistModel model;
      late SchematicGraph graph;

      setUpAll(() {
        final bytes = File(
          'test/fixtures/netlist/serv_ice40/captured/serv_ice40.netlist.json.gz',
        ).readAsBytesSync();
        model = const StreamingYosysJsonReader().parse(
          utf8.decode(gzip.decode(bytes)),
        );
        graph = builder.build(model, HierarchyNode.rootOf(model)!);
      });

      test('the carry LUT has I0 and I1 tied to 0 and I3 on add_cy_r', () {
        final lut = portsOf(
          graph,
          'servant.servile.cpu.alu.add_cy_r_SB_LUT4_I3_1',
        );
        expect(lut['I0']!.tie, const PinTie.constant('0'));
        expect(lut['I1']!.tie, const PinTie.constant('0'));
        expect(lut['I2']!.tie, PinTie.net);
        expect(lut['I3']!.tie, PinTie.net);
        expect(lut['O']!.tie, PinTie.net);
        final i3 = model
            .modules['service']!
            .cells['servant.servile.cpu.alu.add_cy_r_SB_LUT4_I3_1']!
            .connections['I3']!;
        expect(i3, const <BitRef>[NetBit(576)]);
      });

      test('the RAM MASK bus is x, WDATA is on nets, nothing is undriven', () {
        final rams = graph.cells.where((c) => c.type == 'SB_RAM40_4K');
        expect(rams, hasLength(17));
        for (final ram in rams) {
          final ports = <String, SchematicPort>{
            for (final p in ram.ports) p.name: p,
          };
          expect(ports['MASK']!.tie.isX, isTrue, reason: ram.id);
          // 14 of the 16 WDATA bits are x; the other two carry data.
          expect(ports['WDATA']!.tie, PinTie.net, reason: ram.id);
        }
        // A healthy design: x-tied inputs are not undriven ones.
        final undriven = <String>[
          for (final cell in graph.cells)
            for (final port in cell.ports)
              if (port.tie.kind == PinTieKind.undriven) port.id,
        ];
        expect(undriven, isEmpty);
      });

      test('the PLL draws the seven ports Yosys omitted', () {
        final pll = graph.cells.singleWhere(
          (c) => c.type == 'SB_PLL40_CORE',
        );
        expect(
          pll.ports.map((p) => p.name),
          model.modules['SB_PLL40_CORE']!.ports.keys,
        );
        final unconnected = <String>{
          for (final p in pll.ports)
            if (p.tie == PinTie.unconnected) p.name,
        };
        expect(unconnected, <String>{
          'PLLOUTGLOBAL',
          'EXTFEEDBACK',
          'DYNAMICDELAY',
          'LATCHINPUTVALUE',
          'SDO',
          'SDI',
          'SCLK',
        });
      });
    });
  });
}
