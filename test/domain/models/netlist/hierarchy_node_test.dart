// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/netlist/cell.dart';
import 'package:netcrux/domain/models/netlist/hierarchy_node.dart';
import 'package:netcrux/domain/models/netlist/module.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';

/// Builds a tiny three-level netlist:
///
///   top (module)
///   ├── u_cpu : cpu
///   │   └── u_alu : alu
///   └── u_and : $and          (primitive — not a child module)
NetlistModel _threeLevelModel() {
  Module makeModule({
    required String name,
    required Map<String, Cell> cells,
    bool isTop = false,
  }) {
    return Module(
      name: name,
      attributes: isTop
          ? const <String, String>{'top': '1'}
          : const <String, String>{},
      ports: const {},
      cells: cells,
      nets: const {},
    );
  }

  Cell makeCell({required String name, required String type}) => Cell(
    name: name,
    type: type,
    parameters: const {},
    attributes: const {},
    portDirections: const {},
    connections: const {},
  );

  final alu = makeModule(name: 'alu', cells: const {});
  final cpu = makeModule(
    name: 'cpu',
    cells: <String, Cell>{
      'u_alu': makeCell(name: 'u_alu', type: 'alu'),
    },
  );
  final top = makeModule(
    name: 'top',
    isTop: true,
    cells: <String, Cell>{
      'u_cpu': makeCell(name: 'u_cpu', type: 'cpu'),
      'u_and': makeCell(name: 'u_and', type: r'$and'),
    },
  );
  return NetlistModel(
    creator: 'test',
    modules: <String, Module>{
      'top': top,
      'cpu': cpu,
      'alu': alu,
    },
  );
}

void main() {
  group('HierarchyNode.rootOf', () {
    test('returns a root node pointing at the top module', () {
      final model = _threeLevelModel();
      final root = HierarchyNode.rootOf(model);
      expect(root, isNotNull);
      expect(root!.isRoot, isTrue);
      expect(root.path, isEmpty);
      expect(root.moduleName, 'top');
      expect(root.depth, 0);
      expect(root.displayName, 'top');
      expect(root.canonicalPath(model), 'top');
    });

    test('returns null when there is no top module', () {
      const model = NetlistModel(creator: 'empty', modules: <String, Module>{});
      expect(HierarchyNode.rootOf(model), isNull);
    });
  });

  group('HierarchyNode.child', () {
    test('descends into a user-defined module', () {
      final model = _threeLevelModel();
      final root = HierarchyNode.rootOf(model)!;
      final child = root.child(model, 'u_cpu');
      expect(child, isNotNull);
      expect(child!.path, <String>['u_cpu']);
      expect(child.moduleName, 'cpu');
      expect(child.depth, 1);
      expect(child.displayName, 'u_cpu');
      expect(child.canonicalPath(model), 'top.u_cpu');
    });

    test('returns null for a primitive cell', () {
      final model = _threeLevelModel();
      final root = HierarchyNode.rootOf(model)!;
      expect(root.child(model, 'u_and'), isNull);
    });

    test('returns null for an unknown instance', () {
      final model = _threeLevelModel();
      final root = HierarchyNode.rootOf(model)!;
      expect(root.child(model, 'does_not_exist'), isNull);
    });

    test('descends two levels', () {
      final model = _threeLevelModel();
      final root = HierarchyNode.rootOf(model)!;
      final cpu = root.child(model, 'u_cpu')!;
      final alu = cpu.child(model, 'u_alu');
      expect(alu, isNotNull);
      expect(alu!.path, <String>['u_cpu', 'u_alu']);
      expect(alu.moduleName, 'alu');
      expect(alu.canonicalPath(model), 'top.u_cpu.u_alu');
    });
  });

  group('HierarchyNode.parent', () {
    test('returns null at the root', () {
      final model = _threeLevelModel();
      final root = HierarchyNode.rootOf(model)!;
      expect(root.parent(model), isNull);
    });

    test('one-level parent resolves the top module', () {
      final model = _threeLevelModel();
      final root = HierarchyNode.rootOf(model)!;
      final cpu = root.child(model, 'u_cpu')!;
      final parent = cpu.parent(model);
      expect(parent, isNotNull);
      expect(parent!.isRoot, isTrue);
      expect(parent.moduleName, 'top');
    });

    test('two-level parent walks back through the chain', () {
      final model = _threeLevelModel();
      final root = HierarchyNode.rootOf(model)!;
      final cpu = root.child(model, 'u_cpu')!;
      final alu = cpu.child(model, 'u_alu')!;
      final parent = alu.parent(model);
      expect(parent, isNotNull);
      expect(parent!.path, <String>['u_cpu']);
      expect(parent.moduleName, 'cpu');
    });
  });

  group('HierarchyNode.childInstanceNames', () {
    test('lists only user-defined module instances', () {
      final model = _threeLevelModel();
      final root = HierarchyNode.rootOf(model)!;
      expect(root.childInstanceNames(model), <String>['u_cpu']);
    });

    test('returns empty for a leaf module', () {
      final model = _threeLevelModel();
      final root = HierarchyNode.rootOf(model)!;
      final cpu = root.child(model, 'u_cpu')!;
      final alu = cpu.child(model, 'u_alu')!;
      expect(alu.childInstanceNames(model), isEmpty);
    });
  });

  group('equality and hashing', () {
    test('two nodes with the same path + module compare equal', () {
      const a = HierarchyNode(
        path: <String>['u_cpu', 'u_alu'],
        moduleName: 'alu',
      );
      const b = HierarchyNode(
        path: <String>['u_cpu', 'u_alu'],
        moduleName: 'alu',
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('different paths compare unequal', () {
      const a = HierarchyNode(path: <String>['u_cpu'], moduleName: 'cpu');
      const b = HierarchyNode(path: <String>['u_dma'], moduleName: 'cpu');
      expect(a, isNot(equals(b)));
    });

    test('different module names compare unequal', () {
      const a = HierarchyNode(path: <String>['u_cpu'], moduleName: 'cpu_a');
      const b = HierarchyNode(path: <String>['u_cpu'], moduleName: 'cpu_b');
      expect(a, isNot(equals(b)));
    });
  });

  group('copyWith', () {
    test('replaces individual fields', () {
      const node = HierarchyNode(
        path: <String>['u_cpu'],
        moduleName: 'cpu',
      );
      final copy = node.copyWith(moduleName: 'cpu_v2');
      expect(copy.path, node.path);
      expect(copy.moduleName, 'cpu_v2');
    });
  });

  group('toString', () {
    test('includes path and module name', () {
      const node = HierarchyNode(
        path: <String>['u_cpu', 'u_alu'],
        moduleName: 'alu',
      );
      expect(node.toString(), contains('u_cpu.u_alu'));
      expect(node.toString(), contains('alu'));
    });

    test('handles root cleanly', () {
      const node = HierarchyNode(path: <String>[], moduleName: 'top');
      expect(node.toString(), contains('top'));
    });
  });
}
