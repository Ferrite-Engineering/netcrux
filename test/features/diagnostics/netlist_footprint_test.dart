// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/netlist/bit_ref.dart';
import 'package:netcrux/domain/models/netlist/cell.dart';
import 'package:netcrux/domain/models/netlist/module.dart';
import 'package:netcrux/domain/models/netlist/net.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/netlist/port.dart';
import 'package:netcrux/domain/models/netlist/port_direction.dart';
import 'package:netcrux/features/diagnostics/providers/netlist_footprint_provider.dart';
import 'package:netcrux/features/project/providers/loaded_netlist_provider.dart';
import 'package:netcrux/features/statistics/providers/layout_timing_provider.dart';
import 'package:netcrux/services/workspace/netcrux_tab_overrides.dart';

Module _module(String name, {int cells = 0, int nets = 0}) {
  return Module(
    name: name,
    attributes: const <String, String>{},
    ports: const <String, Port>{},
    cells: <String, Cell>{
      for (var i = 0; i < cells; i++)
        'c$i': Cell(
          name: 'c$i',
          type: 'AND',
          attributes: const <String, String>{},
          parameters: const <String, String>{},
          portDirections: const <String, PortDirection>{},
          connections: const <String, List<BitRef>>{},
        ),
    },
    nets: <String, Net>{
      for (var i = 0; i < nets; i++)
        'n$i': Net(
          name: 'n$i',
          bits: const <BitRef>[],
          attributes: const <String, String>{},
        ),
    },
  );
}

NetlistModel _model(Map<String, Module> modules) =>
    NetlistModel(creator: 'test', modules: modules);

/// A tab container built the way the app builds one.
ProviderContainer _tab(ProviderContainer root) {
  final container = ProviderContainer(
    parent: root,
    overrides: netcruxTabOverridesFactory(TabId.generate()),
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('netlistFootprintProvider', () {
    test('reports zeros with no design', () {
      final root = ProviderContainer();
      addTearDown(root.dispose);
      final tab = _tab(root);

      expect(tab.read(netlistFootprintProvider), NetlistFootprint.empty);
      expect(tab.read(netlistFootprintProvider).hasDesign, isFalse);
    });

    test('sums cells and nets across every module', () {
      final root = ProviderContainer();
      addTearDown(root.dispose);
      final tab = _tab(root);

      tab
          .read(loadedNetlistProvider.notifier)
          .setModel(
            _model({
              'top': _module('top', cells: 3, nets: 5),
              'sub': _module('sub', cells: 7, nets: 2),
            }),
          );

      final footprint = tab.read(netlistFootprintProvider);
      expect(footprint.modules, 2);
      expect(footprint.cells, 10);
      expect(footprint.nets, 7);
      expect(footprint.hasDesign, isTrue);
    });

    test('two tabs report their own designs — the whole point of the '
        'per-tab breakdown table is that the rows differ', () {
      final root = ProviderContainer();
      addTearDown(root.dispose);
      final a = _tab(root);
      final b = _tab(root);

      a
          .read(loadedNetlistProvider.notifier)
          .setModel(_model({'top': _module('top', cells: 100, nets: 200)}));
      b
          .read(loadedNetlistProvider.notifier)
          .setModel(_model({'top': _module('top', cells: 1, nets: 2)}));

      expect(a.read(netlistFootprintProvider).cells, 100);
      expect(b.read(netlistFootprintProvider).cells, 1);
    });

    test('clearing the design clears the footprint rather than leaving the '
        'previous run stale', () {
      final root = ProviderContainer();
      addTearDown(root.dispose);
      final tab = _tab(root);

      tab
          .read(loadedNetlistProvider.notifier)
          .setModel(_model({'top': _module('top', cells: 4, nets: 4)}));
      expect(tab.read(netlistFootprintProvider).cells, 4);

      tab.read(loadedNetlistProvider.notifier).setModel(null);
      expect(tab.read(netlistFootprintProvider), NetlistFootprint.empty);
    });
  });

  group('layoutTimingProvider scope', () {
    test('is per-tab — left at root, a slow layout in tab A showed in tab '
        "B's statistics strip for a design B never laid out", () {
      final root = ProviderContainer();
      addTearDown(root.dispose);
      final a = _tab(root);
      final b = _tab(root);

      a
          .read(layoutTimingProvider.notifier)
          .completed(const Duration(seconds: 2));

      expect(a.read(layoutTimingProvider).lastMicroseconds, 2000000);
      expect(b.read(layoutTimingProvider).hasSample, isFalse);
    });
  });
}
