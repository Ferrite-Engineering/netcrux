// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// A wide case statement elaborates to one comparator per case item, every one
// of them feeding the select input of one `$pmux`. Laid out as they are, the
// comparators fill one layer: a single column many thousands of units tall.
// These tests hold the selector bank to drawing them as a grid, with every
// cell and every wire still in the layout.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/layout/bounding_box.dart';
import 'package:netcrux/domain/models/layout/netlist_layout.dart';
import 'package:netcrux/domain/models/netlist/module.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/services/layout/elk_ffi_library_io.dart';
import 'package:netcrux/services/layout/elk_layout_service.dart';
import 'package:netcrux/services/layout/native_elk_solver.dart';
import 'package:netcrux/services/layout/selector_bank.dart';
import 'package:netcrux/services/schematic/net_edge_enumeration.dart';
import 'package:netcrux/services/schematic/schematic_scope_module.dart';

import '../../helpers/elk_ffi_library_gate.dart';

/// The Yosys-elaborated wide case statement
/// (`test/fixtures/netlist/case_decoder/captured/`).
Module _caseDecoder() {
  final model = NetlistModel.fromJson(
    jsonDecode(
          File(
            'test/fixtures/netlist/case_decoder/captured/'
            'case_decoder.netlist.json',
          ).readAsStringSync(),
        )
        as Map<String, Object?>,
  );
  return schematicScopeModule(model, model.modules['case_decoder']!);
}

/// A module whose `$pmux` select input is fed by [count] comparators of
/// constants (so no wire enters them), plus, with [fedComparator], one more
/// comparator whose input is a module port.
Module _selector(int count, {bool fedComparator = false}) {
  const eqPorts = <String, Object?>{
    'A': 'input',
    'B': 'input',
    'Y': 'output',
  };
  final cells = <String, Object?>{
    for (var i = 0; i < count; i++)
      'cmp$i': <String, Object?>{
        'type': r'$eq',
        'port_directions': eqPorts,
        'connections': <String, Object?>{
          'A': <Object>['0', '1'],
          'B': <Object>[if (i.isEven) '0' else '1', '1'],
          'Y': <Object>[100 + i],
        },
      },
    if (fedComparator)
      'fed': <String, Object?>{
        'type': r'$eq',
        'port_directions': eqPorts,
        'connections': <String, Object?>{
          'A': <Object>[3],
          'B': <Object>['1'],
          'Y': <Object>[99],
        },
      },
    'sel': <String, Object?>{
      'type': r'$pmux',
      'port_directions': const <String, Object?>{
        'A': 'input',
        'B': 'input',
        'S': 'input',
        'Y': 'output',
      },
      'connections': <String, Object?>{
        'A': <Object>[4],
        'B': <Object>[for (var i = 0; i <= count; i++) 5],
        'S': <Object>[
          if (fedComparator) 99,
          for (var i = 0; i < count; i++) 100 + i,
        ],
        'Y': <Object>[2],
      },
    },
  };
  final model = NetlistModel.fromJson(<String, Object?>{
    'creator': 'Yosys test',
    'modules': <String, Object?>{
      'top': <String, Object?>{
        'attributes': const <String, Object?>{'top': '1'},
        'ports': const <String, Object?>{
          'y': <String, Object?>{
            'direction': 'output',
            'bits': <Object>[2],
          },
          'a': <String, Object?>{
            'direction': 'input',
            'bits': <Object>[3],
          },
          'd': <String, Object?>{
            'direction': 'input',
            'bits': <Object>[4],
          },
          'e': <String, Object?>{
            'direction': 'input',
            'bits': <Object>[5],
          },
        },
        'cells': cells,
        'netnames': const <String, Object?>{},
      },
    },
  });
  return schematicScopeModule(model, model.modules['top']!);
}

bool _overlaps(BoundingBox a, BoundingBox b) =>
    a.x < b.x + b.width &&
    b.x < a.x + a.width &&
    a.y < b.y + b.height &&
    b.y < a.y + a.height;

/// Whether the axis-aligned segment from ([x1], [y1]) to ([x2], [y2]) passes
/// through the inside of [box].
bool _crosses(double x1, double y1, double x2, double y2, BoundingBox box) {
  final left = x1 < x2 ? x1 : x2;
  final right = x1 < x2 ? x2 : x1;
  final top = y1 < y2 ? y1 : y2;
  final bottom = y1 < y2 ? y2 : y1;
  return left < box.x + box.width &&
      right > box.x &&
      top < box.y + box.height &&
      bottom > box.y;
}

void main() {
  group('findSelectorBanks', () {
    test('the 64 comparators of the case statement are one bank', () {
      // case_decoder.v has 64 case items; Yosys makes 63 `$eq` cells and,
      // for item 0, one `$logic_not`, all feeding the `$pmux` select input.
      final (:input, :banks) = buildElkLayoutInput(_caseDecoder());
      expect(banks, hasLength(1));
      final bank = banks.single;
      expect(bank.cells, hasLength(64));
      expect(bank.wires, hasLength(64));
      expect(bank.selectPortId, endsWith(':S'));
      // About as wide as tall: 7 columns of 10 rows (sqrt(64 * 82 / 110)
      // rounds to 7; 64 / 7 rounds up to 10).
      expect((bank.columns, bank.rows), (7, 10));

      final children = (input['children']! as List<Object?>)
          .cast<Map<String, Object?>>();
      final ids = {for (final child in children) child['id']};
      for (final cell in bank.cells) {
        expect(ids, isNot(contains(cell.id)));
      }
      final node = children.singleWhere((c) => c['id'] == bank.nodeId);
      // Whole numbers, as every other size in the input: the input's text
      // must be the same on desktop and in the browser.
      expect(node['width'], isA<int>());
      expect(node['height'], isA<int>());
      final edges = (input['edges']! as List<Object?>)
          .cast<Map<String, Object?>>();
      final edgeIds = {for (final edge in edges) edge['id']};
      for (final wire in bank.wires) {
        expect(edgeIds, isNot(contains(wire.id)));
      }
      expect(edgeIds, contains(bank.wireId));
    });

    test('fewer than the bank size keep their own nodes', () {
      expect(
        buildElkLayoutInput(_selector(minSelectorBankSize - 1)).banks,
        isEmpty,
      );
      final banks = buildElkLayoutInput(_selector(minSelectorBankSize)).banks;
      expect(banks.single.cells, hasLength(minSelectorBankSize));
    });

    test('a comparator a routed wire enters is not in the bank', () {
      final bank = buildElkLayoutInput(
        _selector(minSelectorBankSize, fedComparator: true),
      ).banks.single;
      expect(bank.cells.map((c) => c.id), isNot(contains('fed')));
      expect(bank.cells, hasLength(minSelectorBankSize));
    });

    test('the grid reads in select-bit order', () {
      final bank = buildElkLayoutInput(_selector(20)).banks.single;
      expect(bank.cells.map((c) => c.id), [
        for (var i = 0; i < 20; i++) 'cmp$i',
      ]);
    });

    test('a cone view without the whole bank has none', () {
      final module = _selector(minSelectorBankSize);
      final routed = [
        for (final group in enumerateNetEdges(module)) ...group.edges,
      ];
      final keep = {'sel', for (var i = 0; i < 4; i++) 'cmp$i'};
      final (:input, :banks) = buildElkLayoutInput(
        module,
        only: ElkSubgraph(
          cellIds: keep,
          boundaryPortIds: const {},
          edgeIds: {
            for (final edge in routed)
              if (keep.any((c) => edge.sourcePortId.startsWith('$c:')) &&
                  edge.targetPortId.startsWith('sel:'))
                edge.id,
          },
        ),
      );
      expect(banks, isEmpty);
      expect(input['children']! as List<Object?>, hasLength(keep.length));
    });

    // A scope with no bank keeps its ELK input byte for byte: the stored
    // layout references' input fingerprints (native_elk_parity_test.dart)
    // hold every other fixture to that. Its layout is left alone too.
    test('a layout with no bank is returned as it is', () {
      const layout = NetlistLayout(
        nodes: [],
        edges: [],
        bounds: BoundingBox(x: 0, y: 0, width: 1, height: 1),
      );
      expect(identical(expandSelectorBanks(layout, const []), layout), isTrue);
    });

    test('a result without the bank is an error, not a drawing without '
        'its cells', () {
      final banks = buildElkLayoutInput(_selector(minSelectorBankSize)).banks;
      const layout = NetlistLayout(
        nodes: [],
        edges: [],
        bounds: BoundingBox(x: 0, y: 0, width: 1, height: 1),
      );
      expect(
        () => expandSelectorBanks(layout, banks),
        throwsA(isA<LayoutException>()),
      );
    });
  });

  group('the laid-out case statement', () {
    late NetlistLayout layout;
    late SelectorBank bank;
    late Module module;
    setUpAll(() {
      if (elkFfiDevBuildPath() == null) return;
      module = _caseDecoder();
      final request = buildElkLayoutInput(module);
      bank = request.banks.single;
      final solver = NativeElkSolver.open();
      layout = expandSelectorBanks(
        NetlistLayout.fromJson(
          jsonDecode(solver.solve(jsonEncode(request.input)))
              as Map<String, Object?>,
        ),
        request.banks,
      );
    });

    test('is not one tall column', () {
      if (!requireElkFfiLibrary()) return;
      // Before the bank: 531 x 5898, with 72 nodes at one x.
      expect(
        layout.bounds.height,
        lessThan(2 * layout.bounds.width),
        reason: 'the layout is ${layout.bounds}',
      );
      final atX = <double, int>{};
      for (final node in layout.nodes) {
        atX.update(node.bounds.x, (n) => n + 1, ifAbsent: () => 1);
      }
      expect(atX.values.reduce((a, b) => a > b ? a : b), lessThanOrEqualTo(16));
    });

    test('places every cell and routes every wire', () {
      if (!requireElkFfiLibrary()) return;
      final nodeIds = {for (final node in layout.nodes) node.id};
      expect(nodeIds, containsAll(module.cells.keys));
      expect(nodeIds.where((id) => id.startsWith('bank:')), isEmpty);
      final routed = [
        for (final group in enumerateNetEdges(module))
          if (group.edges.length <= highFanoutEdgeCap) ...group.edges,
      ];
      final edgeIds = {for (final edge in layout.edges) edge.id};
      expect(edgeIds, {for (final edge in routed) edge.id});
      for (final cell in bank.cells) {
        final node = layout.findNode(cell.id)!;
        expect(
          node.ports.keys,
          containsAll([...cell.westPorts, ...cell.eastPorts]),
        );
      }
    });

    test('no cell overlaps another', () {
      if (!requireElkFfiLibrary()) return;
      final nodes = layout.nodes;
      for (var i = 0; i < nodes.length; i++) {
        for (var j = i + 1; j < nodes.length; j++) {
          expect(
            _overlaps(nodes[i].bounds, nodes[j].bounds),
            isFalse,
            reason: '${nodes[i].id} overlaps ${nodes[j].id}',
          );
        }
      }
    });

    test('each bank wire runs from its pin to the select pin, clear of '
        'every cell', () {
      if (!requireElkFfiLibrary()) return;
      final select = bank.selectPortId;
      final selector = layout.findNode(
        select.substring(0, select.length - ':S'.length),
      )!;
      final selectPin = selector.ports[select]!;
      for (final wire in bank.wires) {
        final route = layout.findEdge(wire.id)!;
        final cell = layout.findNode(bank.wireCells[wire.id]!)!;
        final pin = cell.ports[wire.sourcePortId]!;
        expect(route.points.first.x, cell.bounds.x + pin.x + pin.width);
        expect(route.points.first.y, cell.bounds.y + pin.y + pin.height / 2);
        expect(route.points.last.x, selector.bounds.x + selectPin.x);
        expect(
          route.points.last.y,
          selector.bounds.y + selectPin.y + selectPin.height / 2,
        );
        for (var i = 1; i < route.points.length; i++) {
          final a = route.points[i - 1];
          final b = route.points[i];
          expect(a.x == b.x || a.y == b.y, isTrue, reason: '${wire.id} bends');
          for (final node in layout.nodes) {
            expect(
              _crosses(a.x, a.y, b.x, b.y, node.bounds),
              isFalse,
              reason: '${wire.id} crosses ${node.id}',
            );
          }
        }
      }
    });
  });
}
