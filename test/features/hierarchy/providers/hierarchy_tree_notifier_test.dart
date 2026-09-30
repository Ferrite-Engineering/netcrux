// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/netlist/cell.dart';
import 'package:netcrux/domain/models/netlist/hierarchy_node.dart';
import 'package:netcrux/domain/models/netlist/module.dart';
import 'package:netcrux/domain/models/netlist/net.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/netlist/port.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';

NetlistModel _model() {
  Cell cell(String name, String type) => Cell(
    name: name,
    type: type,
    parameters: const {},
    attributes: const {},
    portDirections: const {},
    connections: const {},
  );

  const alu = Module(
    name: 'alu',
    attributes: <String, String>{},
    ports: <String, Port>{},
    cells: <String, Cell>{},
    nets: <String, Net>{},
  );
  final cpu = Module(
    name: 'cpu',
    attributes: const {},
    ports: const {},
    cells: <String, Cell>{'u_alu': cell('u_alu', 'alu')},
    nets: const {},
  );
  final top = Module(
    name: 'top',
    attributes: const <String, String>{'top': '1'},
    ports: const {},
    cells: <String, Cell>{
      'u_cpu': cell('u_cpu', 'cpu'),
      'u_dma': cell('u_dma', r'$mux'),
    },
    nets: const {},
  );
  return NetlistModel(
    creator: 'test',
    modules: <String, Module>{'top': top, 'cpu': cpu, 'alu': alu},
  );
}

void main() {
  ProviderContainer makeContainer() {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    return container;
  }

  group('initial state', () {
    test('starts empty before setModel is called', () {
      final container = makeContainer();
      final state = container.read(hierarchyTreeProvider);
      expect(state.model, isNull);
      expect(state.root, isNull);
      expect(state.selected, isNull);
      expect(state.expandedKeys, isEmpty);
      expect(state.filterText, isEmpty);
    });
  });

  group('setModel', () {
    test('loads the model, derives the root, expands and selects it', () {
      final container = makeContainer();
      final model = _model();
      container.read(hierarchyTreeProvider.notifier).setModel(model);
      final state = container.read(hierarchyTreeProvider);
      expect(state.model, same(model));
      expect(state.root, isNotNull);
      expect(state.root!.moduleName, 'top');
      expect(state.selected, state.root);
      expect(state.expandedKeys, hasLength(1));
      expect(state.isExpanded(state.root!), isTrue);
    });

    test('setModel(null) resets to empty', () {
      final container = makeContainer();
      final notifier = container.read(hierarchyTreeProvider.notifier)
        ..setModel(_model())
        ..setModel(null);
      final state = container.read(hierarchyTreeProvider);
      expect(state, HierarchyTreeState.empty);
      expect(notifier, isNotNull);
    });

    test('setModel with no top module produces an empty expansion set', () {
      final container = makeContainer();
      const model = NetlistModel(creator: 'empty', modules: <String, Module>{});
      container.read(hierarchyTreeProvider.notifier).setModel(model);
      final state = container.read(hierarchyTreeProvider);
      expect(state.root, isNull);
      expect(state.selected, isNull);
      expect(state.expandedKeys, isEmpty);
    });
  });

  group('expandScope / collapseScope / toggleScope', () {
    test('expandScope adds the key; collapseScope removes it', () {
      final container = makeContainer();
      final model = _model();
      final notifier = container.read(hierarchyTreeProvider.notifier)
        ..setModel(model);
      final root = container.read(hierarchyTreeProvider).root!;
      final cpu = root.child(model, 'u_cpu')!;
      notifier.expandScope(cpu);
      expect(
        container.read(hierarchyTreeProvider).isExpanded(cpu),
        isTrue,
      );
      notifier.collapseScope(cpu);
      expect(
        container.read(hierarchyTreeProvider).isExpanded(cpu),
        isFalse,
      );
    });

    test('collapseScope refuses to collapse the root', () {
      final container = makeContainer();
      final notifier = container.read(hierarchyTreeProvider.notifier)
        ..setModel(_model());
      final root = container.read(hierarchyTreeProvider).root!;
      notifier.collapseScope(root);
      expect(
        container.read(hierarchyTreeProvider).isExpanded(root),
        isTrue,
      );
    });

    test('toggleScope alternates expansion', () {
      final container = makeContainer();
      final model = _model();
      final notifier = container.read(hierarchyTreeProvider.notifier)
        ..setModel(model);
      final root = container.read(hierarchyTreeProvider).root!;
      final cpu = root.child(model, 'u_cpu')!;
      notifier.toggleScope(cpu);
      expect(
        container.read(hierarchyTreeProvider).isExpanded(cpu),
        isTrue,
      );
      notifier.toggleScope(cpu);
      expect(
        container.read(hierarchyTreeProvider).isExpanded(cpu),
        isFalse,
      );
    });

    test('expand/collapse on empty notifier is a no-op', () {
      final container = makeContainer();
      const node = HierarchyNode(path: <String>[], moduleName: 'x');
      container.read(hierarchyTreeProvider.notifier)
        ..expandScope(node)
        ..collapseScope(node);
      expect(
        container.read(hierarchyTreeProvider),
        HierarchyTreeState.empty,
      );
    });
  });

  group('selectScope', () {
    test('updates selected and auto-expands ancestors', () {
      final container = makeContainer();
      final model = _model();
      final notifier = container.read(hierarchyTreeProvider.notifier)
        ..setModel(model);
      final root = container.read(hierarchyTreeProvider).root!;
      final cpu = root.child(model, 'u_cpu')!;
      final alu = cpu.child(model, 'u_alu')!;
      notifier.selectScope(alu);
      final state = container.read(hierarchyTreeProvider);
      expect(state.selected, alu);
      // Ancestor (cpu) auto-expanded so the selection is visible.
      expect(state.isExpanded(cpu), isTrue);
    });

    test('re-selecting the same node is a no-op (object identity)', () {
      final container = makeContainer();
      final notifier = container.read(hierarchyTreeProvider.notifier)
        ..setModel(_model());
      final before = container.read(hierarchyTreeProvider);
      notifier.selectScope(before.selected!);
      final after = container.read(hierarchyTreeProvider);
      expect(identical(before, after), isTrue);
    });
  });

  group('setFilterText', () {
    test('trims whitespace and stores the substring', () {
      final container = makeContainer();
      final notifier = container.read(hierarchyTreeProvider.notifier)
        ..setModel(_model())
        ..setFilterText('  cpu  ');
      expect(
        container.read(hierarchyTreeProvider).filterText,
        'cpu',
      );
      expect(notifier, isNotNull);
    });

    test('setting the same value is a no-op', () {
      final container = makeContainer();
      final notifier = container.read(hierarchyTreeProvider.notifier)
        ..setModel(_model())
        ..setFilterText('cpu');
      final before = container.read(hierarchyTreeProvider);
      notifier.setFilterText('cpu');
      final after = container.read(hierarchyTreeProvider);
      expect(identical(before, after), isTrue);
    });
  });

  group('HierarchyTreeState', () {
    test('equality compares all observable fields', () {
      final model = _model();
      final stateA = HierarchyTreeState(
        model: model,
        root: HierarchyNode.rootOf(model),
        selected: HierarchyNode.rootOf(model),
        expandedKeys: const <String>{''},
        filterText: 'cpu',
      );
      final stateB = HierarchyTreeState(
        model: model,
        root: HierarchyNode.rootOf(model),
        selected: HierarchyNode.rootOf(model),
        expandedKeys: const <String>{''},
        filterText: 'cpu',
      );
      expect(stateA, stateB);
      expect(stateA.hashCode, stateB.hashCode);
    });

    test('copyWith clearSelection drops the selection', () {
      final state = HierarchyTreeState(
        model: _model(),
        root: const HierarchyNode(path: <String>[], moduleName: 'top'),
        selected: const HierarchyNode(path: <String>[], moduleName: 'top'),
        expandedKeys: const <String>{''},
        filterText: '',
      );
      final cleared = state.copyWith(clearSelection: true);
      expect(cleared.selected, isNull);
      expect(cleared.root, isNotNull);
    });
  });

  group('restoreExpanded', () {
    test('sets the saved rows and keeps root and the selection visible', () {
      final container = makeContainer();
      final notifier = container.read(hierarchyTreeProvider.notifier)
        ..setModel(_model())
        ..selectByPath(const <String>['u_cpu', 'u_alu'])
        ..restoreExpanded(const <String>['stale/row']);
      final keys = container.read(hierarchyTreeProvider).expandedKeys;
      expect(keys, containsAll(<String>['', 'u_cpu', 'stale/row']));
      expect(keys, isNot(contains('u_dma')));
      expect(notifier, isNotNull);
    });

    test('is a no-op without a model', () {
      final container = makeContainer();
      container.read(hierarchyTreeProvider.notifier).restoreExpanded(
        const <String>['u_cpu'],
      );
      expect(container.read(hierarchyTreeProvider).expandedKeys, isEmpty);
    });
  });
}
