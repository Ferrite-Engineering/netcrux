// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/domain/models/trace/cone_view.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/viewer/providers/cone_view_notifier.dart';

NetlistModel _vexriscv() => NetlistModel.fromJson(
  jsonDecode(
        utf8.decode(
          gzip.decode(
            File(
              'test/fixtures/netlist/vexriscv/captured/vexriscv.netlist.json.gz',
            ).readAsBytesSync(),
          ),
        ),
      )
      as Map<String, Object?>,
);

void main() {
  late ProviderContainer container;
  late NetlistModel model;

  ConeViewRequest request() => ConeViewRequest(
    scope: container.read(hierarchyTreeProvider).selected!,
    root: const SelectedElement.cell(cellId: 'u_x'),
  );

  setUp(() {
    model = _vexriscv();
    container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(hierarchyTreeProvider.notifier).setModel(model);
    // Listen so the notifier's own scope listener stays subscribed.
    final sub = container.listen<ConeViewRequest?>(
      coneViewProvider,
      (previous, next) {},
    );
    addTearDown(sub.close);
  });

  test('starts with no cone view', () {
    expect(container.read(coneViewProvider), isNull);
  });

  test('show, adjust and exit', () {
    final notifier = container.read(coneViewProvider.notifier)..show(request());
    expect(container.read(coneViewProvider), request());
    notifier.setDirection(ConeViewDirection.fanInAndFanOut);
    expect(
      container.read(coneViewProvider)?.direction,
      ConeViewDirection.fanInAndFanOut,
    );
    notifier.setDepth(null);
    expect(container.read(coneViewProvider)?.isTransitive, isTrue);
    notifier.setDepth(4);
    expect(container.read(coneViewProvider)?.depth, 4);
    notifier.exit();
    expect(container.read(coneViewProvider), isNull);
  });

  test('adjusting with no cone on show does nothing', () {
    container.read(coneViewProvider.notifier)
      ..setDepth(3)
      ..setDirection(ConeViewDirection.fanInAndFanOut)
      ..exit();
    expect(container.read(coneViewProvider), isNull);
  });

  test('selecting another scope ends the cone view', () {
    container.read(coneViewProvider.notifier).show(request());
    final top = model.topModule!;
    final instance = top.cells.values.firstWhere((c) => c.type == 'DataCache');
    container.read(hierarchyTreeProvider.notifier).selectByPath(<String>[
      instance.name,
    ]);
    expect(container.read(coneViewProvider), isNull);
  });

  test('a hierarchy change that keeps the scope keeps the cone view', () {
    final shown = request();
    container.read(coneViewProvider.notifier).show(shown);
    container.read(hierarchyTreeProvider.notifier).selectByPath(const []);
    expect(container.read(coneViewProvider), shown);
  });
}
