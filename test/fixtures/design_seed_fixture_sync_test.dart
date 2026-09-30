// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Pins the generated Dart-const mirror of the design_seed fixture
// (integration_test/fixtures/design_seed_netlist.dart) to the committed
// canonical JSON (test/fixtures/netlist/design_seed/generated/) so the two
// can never drift, and asserts the fixture actually carries the module
// hierarchy the seeded-design journeys navigate.
//
// Regenerate both files with: dart run tool/generate_design_seed_fixture.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/netlist/hierarchy_node.dart';
import 'package:netcrux/services/yosys/yosys_json_parser.dart';

import '../../integration_test/fixtures/design_seed_netlist.dart';

void main() {
  test('Dart const mirrors the committed design_seed.netlist.json', () {
    final committed = File(
      'test/fixtures/netlist/design_seed/generated/design_seed.netlist.json',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    expect(
      designSeedNetlistJson,
      committed,
      reason:
          'integration_test/fixtures/design_seed_netlist.dart drifted from '
          'the committed JSON — run '
          'dart run tool/generate_design_seed_fixture.dart',
    );
  });

  test('fixture parses into the documented 3-level hierarchy', () {
    final model = const YosysJsonParser().parse(designSeedNetlistJson);
    expect(model.modules.keys, containsAll(<String>['top', 'cpu', 'alu']));
    expect(model.topModule?.name, 'top');

    final root = HierarchyNode.rootOf(model);
    expect(root, isNotNull);
    // top → u_cpu (cpu) → u_alu (alu); primitive siblings are excluded.
    expect(root!.childInstanceNames(model), <String>['u_cpu']);
    final cpu = root.child(model, 'u_cpu');
    expect(cpu, isNotNull);
    expect(cpu!.childInstanceNames(model), <String>['u_alu']);
    final alu = cpu.child(model, 'u_alu');
    expect(alu, isNotNull);
    expect(alu!.childInstanceNames(model), isEmpty);
  });
}
