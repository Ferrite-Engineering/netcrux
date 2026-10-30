// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/netlist/hierarchy_node.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/schematic/schematic_graph.dart';
import 'package:netcrux/services/schematic/net_edge_enumeration.dart';
import 'package:netcrux/services/schematic/netlist_element_lookup.dart';
import 'package:netcrux/services/schematic/schematic_graph_builder.dart';
import 'package:netcrux/services/schematic/wire_selection_builder.dart';

/// A scope with what tells a netlist lookup from a graph lookup apart:
///
/// * `u_init`, a `$meminit_v2`, and `u_tie`, whose every bit is a constant:
///   cells the schematic leaves out;
/// * `u_mux`, a `$mux` that connects `A`, `B` and `Y` and declares `S`: a pin
///   the netlist leaves out and the schematic draws;
/// * `data`, a two-bit bus on distinct nets, only one of which is read (by
///   the output port `out`);
/// * `clk`, a module input that reaches two flops;
/// * `pad`, an inout that is the only thing on its net besides a cell pin;
/// * `lonely`, a net nothing reads.
NetlistModel _model() => NetlistModel.fromJson(<String, Object?>{
  'modules': <String, Object?>{
    'm': <String, Object?>{
      'attributes': <String, Object?>{'top': '1'},
      'ports': <String, Object?>{
        'clk': <String, Object?>{
          'direction': 'input',
          'bits': <Object>[2],
        },
        'pad': <String, Object?>{
          'direction': 'inout',
          'bits': <Object>[9],
        },
        'q': <String, Object?>{
          'direction': 'output',
          'bits': <Object>[10],
        },
        'out': <String, Object?>{
          'direction': 'output',
          'bits': <Object>[7],
        },
      },
      'cells': <String, Object?>{
        'ff_0': <String, Object?>{
          'type': r'$_DFF_P_',
          'port_directions': <String, Object?>{
            'C': 'input',
            'D': 'input',
            'Q': 'output',
          },
          'connections': <String, Object?>{
            'C': <Object>[2],
            'D': <Object>[3],
            'Q': <Object>[10],
          },
        },
        'ff_1': <String, Object?>{
          'type': r'$_DFF_P_',
          'port_directions': <String, Object?>{
            'C': 'input',
            'D': 'input',
            'Q': 'output',
          },
          'connections': <String, Object?>{
            'C': <Object>[2],
            'D': <Object>[10],
            'Q': <Object>[11],
          },
        },
        'u_mux': <String, Object?>{
          'type': r'$mux',
          'port_directions': <String, Object?>{
            'A': 'input',
            'B': 'input',
            'Y': 'output',
          },
          'connections': <String, Object?>{
            'A': <Object>[3, 4],
            'B': <Object>[5, 6],
            'Y': <Object>[7, 8],
          },
        },
        'u_pad': <String, Object?>{
          'type': 'pad_cell',
          'port_directions': <String, Object?>{'IO': 'inout'},
          'connections': <String, Object?>{
            'IO': <Object>[9],
          },
        },
        'u_init': <String, Object?>{
          'type': r'$meminit_v2',
          'port_directions': <String, Object?>{},
          'connections': <String, Object?>{
            'ADDR': <Object>['0', '0'],
          },
        },
        'u_tie': <String, Object?>{
          'type': r'$and',
          'port_directions': <String, Object?>{'A': 'input', 'B': 'input'},
          'connections': <String, Object?>{
            'A': <Object>['1'],
            'B': <Object>['0'],
          },
        },
      },
      'netnames': <String, Object?>{
        'clk': <String, Object?>{
          'hide_name': 0,
          'bits': <Object>[2],
        },
        'data': <String, Object?>{
          'hide_name': 0,
          'bits': <Object>[7, 8],
        },
        'pad': <String, Object?>{
          'hide_name': 0,
          'bits': <Object>[9],
        },
        'q': <String, Object?>{
          'hide_name': 0,
          'bits': <Object>[10],
        },
        'lonely': <String, Object?>{
          'hide_name': 0,
          'bits': <Object>[11],
        },
        'absent': <String, Object?>{
          'hide_name': 0,
          'bits': <Object>[99],
        },
      },
    },
  },
});

void main() {
  final model = _model();
  final top = HierarchyNode.rootOf(model)!;
  final module = top.resolve(model)!;
  final graph = const SchematicGraphBuilder().build(model, top);

  group('a lookup in the netlist module agrees with the schematic graph', () {
    test('about which cells are drawn', () {
      final names = <String>{...module.cells.keys, 'u_missing'};
      expect(
        graph.cells.map((c) => c.id),
        isNot(containsAll(<String>['u_init', 'u_tie'])),
        reason: 'the fixture must hold cells the schematic hides',
      );
      for (final name in names) {
        expect(
          schematicDrawsCell(module, name),
          graph.cells.any((c) => c.id == name),
          reason: name,
        );
      }
    });

    test('about which pins are drawn, declared and unconnected ones too', () {
      final pins = <String>{'A', 'B', 'S', 'Y', 'C', 'D', 'Q', 'IO', 'NOPE'};
      for (final cell in <String>[...module.cells.keys, 'u_missing']) {
        for (final pin in pins) {
          expect(
            schematicDrawsCellPort(model, module, cell, pin),
            graph.cells.any(
              (c) => c.id == cell && c.ports.any((p) => p.name == pin),
            ),
            reason: '$cell.$pin',
          );
        }
      }
      expect(schematicDrawsCellPort(model, module, 'u_mux', 'S'), isTrue);
    });

    test('about boundary ports', () {
      for (final name in <String>['clk', 'pad', 'q', 'nope']) {
        expect(
          schematicDrawsBoundaryPort(module, name),
          graph.boundaryPorts.any((p) => p.name == name),
          reason: name,
        );
      }
    });

    test('about the wires of every net, with the same ids and primary', () {
      expect(module.nets, isNotEmpty);
      for (final net in module.nets.values) {
        final fromGraph = buildWholeNetWireSelection(net, graph);
        final fromNetlist = wholeNetWireSelection(module, net);
        expect(fromNetlist, fromGraph, reason: net.name);
        expect(fromNetlist?.primary, fromGraph?.primary, reason: net.name);
      }
    });

    test('and some of those nets have wires and some have none', () {
      final drawn = <String, bool>{
        for (final net in module.nets.values)
          net.name: wholeNetWireSelection(module, net) != null,
      };
      expect(drawn['clk'], isTrue);
      expect(drawn['data'], isTrue);
      expect(drawn['lonely'], isFalse);
      expect(drawn['absent'], isFalse);
    });
  });

  group('enumerateNetEdges restricted to some nets', () {
    test('gives each of them exactly the edges the full list gives it', () {
      final full = enumerateNetEdges(module, skipHiddenCells: true);
      final some = enumerateNetEdges(
        module,
        onlyNetIds: <int>{2, 7},
        skipHiddenCells: true,
      );
      expect(some.map((g) => g.netId).toSet(), <int>{2, 7});
      for (final group in some) {
        final expected = full.singleWhere((g) => g.netId == group.netId);
        expect(
          group.edges
              .map((e) => (e.id, e.sourcePortId, e.targetPortId))
              .toList(),
          expected.edges
              .map((e) => (e.id, e.sourcePortId, e.targetPortId))
              .toList(),
        );
      }
    });

    test('with no restriction is the list as before', () {
      expect(
        enumerateNetEdges(module).map((g) => g.netId),
        enumerateNetEdges(module, onlyNetIds: null).map((g) => g.netId),
      );
    });
  });
}
