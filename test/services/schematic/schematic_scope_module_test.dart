// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/netlist/hierarchy_node.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/schematic/pin_tie.dart';
import 'package:netcrux/services/layout/elk_layout_service.dart';
import 'package:netcrux/services/schematic/schematic_graph_builder.dart';
import 'package:netcrux/services/schematic/schematic_scope_module.dart';

Map<String, Object?> _cell(
  String type,
  Map<String, String> directions,
  Map<String, List<Object>> connections,
) => <String, Object?>{
  'hide_name': 0,
  'type': type,
  'parameters': <String, Object?>{},
  'attributes': <String, Object?>{},
  'port_directions': directions,
  'connections': connections,
};

Map<String, Object?> _meminit(String type, String address, String data) =>
    _cell(
      type,
      <String, String>{},
      <String, List<Object>>{
        'ADDR': address.split(''),
        'DATA': data.split(''),
        if (type == r'$meminit_v2') 'EN': <Object>['1', '1'],
      },
    );

/// A register file as Yosys leaves it before `memory_collect`: one memory
/// read through a `$memrd_v2`, two `$meminit_v2` cells and one `$meminit`
/// holding its initial words, a `$mux` whose every pin is a constant, and an
/// `$and` and a `$not` that are wired.
final Map<String, Object?> _json = <String, Object?>{
  'creator': 'hand-built',
  'modules': <String, Object?>{
    'regfile': <String, Object?>{
      'attributes': <String, Object?>{'top': '1'},
      'ports': <String, Object?>{
        'a': <String, Object?>{
          'direction': 'input',
          'bits': <Object>[2],
        },
        'b': <String, Object?>{
          'direction': 'input',
          'bits': <Object>[3],
        },
        'y': <String, Object?>{
          'direction': 'output',
          'bits': <Object>[5],
        },
      },
      'cells': <String, Object?>{
        'init_0': _meminit(r'$meminit_v2', '00', '01'),
        'init_1': _meminit(r'$meminit_v2', '01', '10'),
        // A `$meminit` whose address is still a wire: hidden by its type,
        // not only for being all constants.
        'init_2': _cell(
          r'$meminit',
          <String, String>{},
          <String, List<Object>>{
            'ADDR': <Object>[2],
            'DATA': <Object>['1', '1'],
          },
        ),
        'u_tied': _cell(
          r'$mux',
          <String, String>{
            'A': 'input',
            'B': 'input',
            'S': 'input',
            'Y': 'output',
          },
          <String, List<Object>>{
            'A': <Object>['0'],
            'B': <Object>['1'],
            'S': <Object>['0'],
            'Y': <Object>['x'],
          },
        ),
        'u_and': _cell(
          r'$and',
          <String, String>{'A': 'input', 'B': 'input', 'Y': 'output'},
          <String, List<Object>>{
            'A': <Object>[2],
            'B': <Object>['1'],
            'Y': <Object>[4],
          },
        ),
        'u_not': _cell(
          r'$not',
          <String, String>{'A': 'input', 'Y': 'output'},
          <String, List<Object>>{
            'A': <Object>[4],
            'Y': <Object>[5],
          },
        ),
        'u_empty': _cell('MYSTERY', <String, String>{}, <String, List<Object>>{
          'Z': <Object>[],
        }),
      },
      'netnames': <String, Object?>{},
    },
  },
};

void main() {
  final model = NetlistModel.fromJson(_json);
  final top = model.modules['regfile']!;
  final node = HierarchyNode.rootOf(model)!;

  group('isHiddenFromSchematic', () {
    test('hides every memory-init cell, wired or not', () {
      for (final name in <String>['init_0', 'init_1', 'init_2']) {
        expect(isHiddenFromSchematic(top.cells[name]!), isTrue, reason: name);
      }
    });

    test('hides a cell whose every connected bit is a constant', () {
      expect(isHiddenFromSchematic(top.cells['u_tied']!), isTrue);
    });

    test('keeps a cell with any wired bit', () {
      expect(isHiddenFromSchematic(top.cells['u_and']!), isFalse);
      expect(isHiddenFromSchematic(top.cells['u_not']!), isFalse);
    });

    test('keeps a cell with no connected bit at all', () {
      expect(isHiddenFromSchematic(top.cells['u_empty']!), isFalse);
    });
  });

  group('the graph and the layout input agree', () {
    final graph = const SchematicGraphBuilder().build(model, node);
    final input = buildElkInput(schematicScopeModule(model, top));
    final elkCells = <String>{
      for (final child
          in (input['children']! as List<Object?>).cast<Map<String, Object?>>())
        if (!(child['id']! as String).startsWith('port:'))
          child['id']! as String,
    };

    test('neither draws nor places a hidden cell', () {
      final drawn = <String>{for (final c in graph.cells) c.id};
      expect(drawn, <String>{'u_and', 'u_not', 'u_empty'});
      expect(elkCells, drawn);
    });

    test('every edge the graph draws ends on a placed cell or port', () {
      final placed = <String>{
        for (final child
            in (input['children']! as List<Object?>)
                .cast<Map<String, Object?>>()) ...<String>[
          child['id']! as String,
          for (final port
              in ((child['ports'] as List<Object?>?) ?? const <Object?>[])
                  .cast<Map<String, Object?>>())
            port['id']! as String,
        ],
      };
      for (final edge in graph.edges) {
        expect(placed, contains(edge.sourcePortId), reason: edge.id);
        expect(placed, contains(edge.targetPortId), reason: edge.id);
      }
    });

    test('the model keeps the hidden cells', () {
      expect(model.modules['regfile']!.cells.keys, contains('init_0'));
      expect(model.modules['regfile']!.cells.keys, contains('u_tied'));
    });
  });

  group('withoutHiddenCells', () {
    test('returns the module itself when nothing is hidden', () {
      final plain = top.copyWith(
        cells: {
          for (final entry in top.cells.entries)
            if (!isHiddenFromSchematic(entry.value)) entry.key: entry.value,
        },
      );
      expect(identical(withoutHiddenCells(plain), plain), isTrue);
    });
  });

  group('SchematicGraphBuilder.cellOf', () {
    test('describes a hidden cell from the model', () {
      final cell = const SchematicGraphBuilder().cellOf(model, top, 'u_tied')!;
      expect(cell.type, r'$mux');
      expect(
        <String>[for (final p in cell.ports) p.name],
        <String>[
          'A',
          'B',
          'S',
          'Y',
        ],
      );
      expect(cell.ports.first.tie, const PinTie.constant('0'));
    });

    test('describes every drawn cell as the graph does, again and again', () {
      final graph = const SchematicGraphBuilder().build(
        model,
        HierarchyNode.rootOf(model)!,
      );
      expect(graph.cells, isNotEmpty);
      // Twice over: the second round reads the tables kept for the module.
      for (var round = 0; round < 2; round++) {
        for (final drawn in graph.cells) {
          expect(
            const SchematicGraphBuilder().cellOf(model, top, drawn.id),
            drawn,
            reason: '${drawn.id}, round $round',
          );
        }
      }
    });

    test('is null for a cell the module does not have', () {
      expect(const SchematicGraphBuilder().cellOf(model, top, 'nope'), isNull);
    });
  });
}
