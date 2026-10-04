// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/netlist/hierarchy_node.dart';
import 'package:netcrux/domain/models/netlist/module.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/services/layout/elk_layout_service.dart';
import 'package:netcrux/services/schematic/net_edge_enumeration.dart';
import 'package:netcrux/services/schematic/schematic_graph_builder.dart';

/// A module whose clock (net 2, a module input) reaches [flops] flops, and
/// whose datapath is `d` (net 3) into flop 0 and flop 0's Q (net 10) out to
/// `q` and into `u_buf`, which reads it twice on a two-bit bus.
Map<String, Object?> _json(int flops) {
  final cells = <String, Object?>{
    for (var i = 0; i < flops; i++)
      'ff_$i': <String, Object?>{
        'type': r'$_DFF_P_',
        'port_directions': <String, Object?>{
          'C': 'input',
          'D': 'input',
          'Q': 'output',
        },
        'connections': <String, Object?>{
          'C': <Object>[2],
          'D': <Object>[if (i == 0) 3 else 100 + i],
          'Q': <Object>[if (i == 0) 10 else 200 + i],
        },
      },
    'u_buf': <String, Object?>{
      'type': 'buf2',
      'port_directions': <String, Object?>{'A': 'input', 'Y': 'output'},
      'connections': <String, Object?>{
        'A': <Object>[10, 10],
        'Y': <Object>[11],
      },
    },
  };
  return <String, Object?>{
    'modules': <String, Object?>{
      'm': <String, Object?>{
        'attributes': <String, Object?>{'top': '1'},
        'ports': <String, Object?>{
          'clk': <String, Object?>{
            'direction': 'input',
            'bits': <Object>[2],
          },
          'd': <String, Object?>{
            'direction': 'input',
            'bits': <Object>[3],
          },
          'q': <String, Object?>{
            'direction': 'output',
            'bits': <Object>[10],
          },
        },
        'cells': cells,
        'netnames': <String, Object?>{},
      },
    },
  };
}

Module _module(int flops) => NetlistModel.fromJson(_json(flops)).modules['m']!;

void main() {
  group('enumerateNetEdges', () {
    test('numbers each net from zero, independent of other nets', () {
      final small = enumerateNetEdges(_module(2));
      final large = enumerateNetEdges(_module(40));
      List<String> idsOf(List<NetEdges> groups, int netId) => <String>[
        for (final e in groups.singleWhere((g) => g.netId == netId).edges) e.id,
      ];
      // The clock net's size changes; the Q net's ids do not.
      expect(idsOf(small, 2), <String>['e_2_0', 'e_2_1']);
      expect(idsOf(large, 2), hasLength(40));
      expect(idsOf(small, 10), <String>['e_10_0', 'e_10_1']);
      expect(idsOf(large, 10), idsOf(small, 10));
    });

    test('pairs every driver with every distinct sink', () {
      final q = enumerateNetEdges(
        _module(1),
      ).singleWhere((g) => g.netId == 10);
      // u_buf:A reads net 10 on two bits, but it is one sink.
      expect(
        q.edges.map((e) => '${e.sourcePortId}>${e.targetPortId}'),
        <String>['ff_0:Q>u_buf:A', 'ff_0:Q>port:q'],
      );
      expect(q.edges.every((e) => e.netId == 10), isTrue);
    });

    test('leaves out nets without a driver or a sink', () {
      final netIds = enumerateNetEdges(_module(3)).map((g) => g.netId);
      // ff_1's D (101) has no driver, its Q (201) no sink, u_buf:Y no sink.
      expect(netIds, isNot(contains(101)));
      expect(netIds, isNot(contains(201)));
      expect(netIds, isNot(contains(11)));
      expect(netIds, containsAll(<int>[2, 3, 10]));
    });
  });

  group('the graph and the layout input share the enumeration', () {
    test('a skipped high-fanout net renumbers nothing', () {
      final model = NetlistModel.fromJson(_json(40));
      final graph = const SchematicGraphBuilder().build(
        model,
        HierarchyNode.rootOf(model)!,
      );
      final input = buildElkInput(model.modules['m']!);
      final elkIds = <String>[
        for (final e
            in (input['edges']! as List<Object?>).cast<Map<String, Object?>>())
          e['id']! as String,
      ];
      // The clock's 40 edges exceed the cap and are not routed.
      expect(elkIds.where((id) => id.startsWith('e_2_')), isEmpty);
      expect(
        graph.edges.where((e) => e.netId == 2),
        hasLength(40),
      );
      // Every routed edge is a graph edge with the same endpoints.
      final graphEdges = {for (final e in graph.edges) e.id: e};
      for (final e
          in (input['edges']! as List<Object?>).cast<Map<String, Object?>>()) {
        final match = graphEdges[e['id']]!;
        expect((e['sources']! as List<Object?>).single, match.sourcePortId);
        expect((e['targets']! as List<Object?>).single, match.targetPortId);
      }
      expect(elkIds, containsAll(<String>['e_3_0', 'e_10_0', 'e_10_1']));
    });

    test('the cap counts the edges of one net', () {
      List<String> routed(int flops) => <String>[
        for (final e
            in (buildElkInput(_module(flops))['edges']! as List<Object?>)
                .cast<Map<String, Object?>>())
          if ((e['id']! as String).startsWith('e_2_')) e['id']! as String,
      ];
      expect(routed(highFanoutEdgeCap), hasLength(highFanoutEdgeCap));
      expect(routed(highFanoutEdgeCap + 1), isEmpty);
    });
  });
}
