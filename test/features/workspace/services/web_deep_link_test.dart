// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/web/web_launch_params.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/viewer/providers/reveal_request_notifier.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/features/workspace/services/web_deep_link.dart';
import 'package:netcrux/services/yosys/yosys_json_parser.dart';

/// `top` instantiates `u_cpu` (a `cpu`), which instantiates `u_alu`.
NetlistModel _seed() => const YosysJsonParser().parse(
  File(
    'test/fixtures/netlist/design_seed/generated/design_seed.netlist.json',
  ).readAsStringSync(),
);

void main() {
  late ProviderContainer tab;
  late NetlistModel model;
  setUp(() {
    tab = ProviderContainer();
    model = _seed();
  });
  tearDown(() => tab.dispose());

  List<String>? selectedPath() =>
      tab.read(hierarchyTreeProvider).selected?.path;

  test('the scope path drops the top module name the root already is', () {
    expect(WebDeepLink.scopeSegments('top.u_cpu.u_alu', model), <String>[
      'u_cpu',
      'u_alu',
    ]);
    expect(WebDeepLink.scopeSegments('u_cpu', model), <String>['u_cpu']);
    expect(WebDeepLink.scopeSegments('top', model), isEmpty);
  });

  test('#scope= selects the named scope after loading the model', () {
    const WebDeepLink(scope: 'top.u_cpu.u_alu').applyTo(tab, model);
    expect(tab.read(hierarchyTreeProvider).model, same(model));
    expect(selectedPath(), <String>['u_cpu', 'u_alu']);
  });

  test('#sig= naming a cell selects it and asks the canvas to reveal it', () {
    const WebDeepLink(signal: 'u_alu').applyTo(tab, model);
    expect(selectedPath(), <String>['u_cpu']);
    expect(
      tab.read(selectedElementProvider).primary,
      const SelectedElement.cell(cellId: 'u_alu'),
    );
    expect(tab.read(revealRequestProvider), 'u_alu');
  });

  test('#sig= naming a driven net reveals the cell that drives it', () {
    const WebDeepLink(scope: 'top.u_cpu', signal: 'alu_y').applyTo(tab, model);
    expect(selectedPath(), <String>['u_cpu']);
    final revealed = tab.read(revealRequestProvider);
    expect(revealed, 'u_alu');
    expect(
      tab.read(selectedElementProvider).primary,
      const SelectedElement.cell(cellId: 'u_alu'),
    );
  });

  test('hints that name nothing leave the design at its root', () {
    const WebDeepLink(scope: 'top.nope', signal: 'nope').applyTo(tab, model);
    expect(selectedPath(), isEmpty);
    expect(tab.read(revealRequestProvider), isNull);
    expect(tab.read(selectedElementProvider).isEmpty, isTrue);
  });

  test('fromLaunchParams carries both fragment hints', () {
    final link = WebDeepLink.fromLaunchParams(
      WebLaunchParams.parse(fragment: 'scope=top.u_cpu&sig=alu_y'),
    );
    expect(link.scope, 'top.u_cpu');
    expect(link.signal, 'alu_y');
  });
}
