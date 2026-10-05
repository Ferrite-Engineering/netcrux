// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/netlist/bit_ref.dart';
import 'package:netcrux/domain/models/netlist/cell.dart';
import 'package:netcrux/domain/models/netlist/module.dart';
import 'package:netcrux/domain/models/netlist/net.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/netlist/port.dart';
import 'package:netcrux/domain/models/netlist/port_direction.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/viewer/providers/reveal_request_notifier.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/features/viewer/services/analysis_selection_probe.dart';

/// Two-level design:
///
/// ```text
/// top (attributes.top = 1)
///   cells: u_src ($dff, drives Q → net 5), u_sync (instance of sync,
///          sinks D ← net 5)
///   nets:  async_data = [NetBit(5)]
/// sync
///   ports: D (input, [NetBit(9)])
///   cells: ff1 ($dff, sinks D ← net 9)
///   nets:  meta = [NetBit(9)]
/// ```
///
/// `async_data` has a rendered edge in top's scope (u_src:Q → u_sync:D);
/// `meta` has one in sync's scope (port:D → ff1:D).
NetlistModel _model() {
  const top = Module(
    name: 'top',
    attributes: <String, String>{'top': '1'},
    ports: <String, Port>{},
    cells: <String, Cell>{
      'u_src': Cell(
        name: 'u_src',
        type: r'$dff',
        parameters: {},
        attributes: {},
        portDirections: {'Q': PortDirection.output},
        connections: {
          'Q': [NetBit(5)],
        },
      ),
      'u_sync': Cell(
        name: 'u_sync',
        type: 'sync',
        parameters: {},
        attributes: {},
        portDirections: {'D': PortDirection.input},
        connections: {
          'D': [NetBit(5)],
        },
      ),
    },
    nets: <String, Net>{
      'async_data': Net(
        name: 'async_data',
        bits: [NetBit(5)],
        attributes: {},
      ),
    },
  );
  const sync = Module(
    name: 'sync',
    attributes: <String, String>{},
    ports: <String, Port>{
      'D': Port(
        name: 'D',
        direction: PortDirection.input,
        bits: [NetBit(9)],
      ),
    },
    cells: <String, Cell>{
      'ff1': Cell(
        name: 'ff1',
        type: r'$dff',
        parameters: {},
        attributes: {},
        portDirections: {'D': PortDirection.input},
        connections: {
          'D': [NetBit(9)],
        },
      ),
    },
    nets: <String, Net>{
      'meta': Net(name: 'meta', bits: [NetBit(9)], attributes: {}),
    },
  );
  return const NetlistModel(
    creator: 'probe-test',
    modules: <String, Module>{'top': top, 'sync': sync},
  );
}

void main() {
  ProviderContainer makeContainer() {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(hierarchyTreeProvider.notifier).setModel(_model());
    return container;
  }

  group('selectCell', () {
    test('selects a leaf cell in the current scope without navigating', () {
      final container = makeContainer();
      final probe = AnalysisSelectionProbe(container);
      expect(probe.selectCell('u_src'), isTrue);
      expect(
        container.read(selectedElementProvider).primary,
        const SelectedElement.cell(cellId: 'u_src'),
      );
      expect(container.read(hierarchyTreeProvider).selected!.isRoot, isTrue);
    });

    test('module-qualified path navigates the scope, then selects', () {
      final container = makeContainer();
      final probe = AnalysisSelectionProbe(container);
      // `sync.ff1` — the analyzers' `moduleName.cellName` form. The cell
      // lives inside the u_sync instance, so the probe must move the
      // scope there before selecting.
      expect(probe.selectCell('sync.ff1'), isTrue);
      final tree = container.read(hierarchyTreeProvider);
      expect(tree.selected!.path, <String>['u_sync']);
      expect(tree.selected!.moduleName, 'sync');
      expect(
        container.read(selectedElementProvider).primary,
        const SelectedElement.cell(cellId: 'ff1'),
      );
    });

    test('unknown cell selects nothing and reports false', () {
      final container = makeContainer();
      final probe = AnalysisSelectionProbe(container);
      expect(probe.selectCell('nope.missing'), isFalse);
      expect(container.read(selectedElementProvider).isEmpty, isTrue);
    });

    test('no loaded model is a safe no-op', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(AnalysisSelectionProbe(container).selectCell('u_src'), isFalse);
    });
  });

  group('selectNet', () {
    test('selects the wire of a net declared in the current scope', () {
      final container = makeContainer();
      final probe = AnalysisSelectionProbe(container);
      expect(probe.selectNet('async_data'), isTrue);
      final primary = container.read(selectedElementProvider).primary;
      expect(primary, isA<SelectedElementWire>());
      expect((primary as SelectedElementWire).netId, 5);
    });

    test('module-qualified net path navigates the scope, then selects', () {
      final container = makeContainer();
      final probe = AnalysisSelectionProbe(container);
      expect(probe.selectNet('sync.meta'), isTrue);
      final tree = container.read(hierarchyTreeProvider);
      expect(tree.selected!.path, <String>['u_sync']);
      final primary = container.read(selectedElementProvider).primary;
      expect(primary, isA<SelectedElementWire>());
      expect((primary as SelectedElementWire).netId, 9);
    });

    test('unknown net selects nothing and reports false', () {
      final container = makeContainer();
      final probe = AnalysisSelectionProbe(container);
      expect(probe.selectNet('ghost_net'), isFalse);
      expect(container.read(selectedElementProvider).isEmpty, isTrue);
    });

    test(
      'multi-bit bus selects a bit that HAS an edge when bit 0 has none '
      '(Bug A regression)',
      () {
        // `bus` = [NetBit(100), NetBit(101)]. Only bit 101 is wired between a
        // driver and a sink, so only 101 has a rendered edge; bit 0 (100) is
        // dangling. The old bit-0-only probe gave up here and returned false
        // → the CDC crossing row highlighted nothing. The fix scans every
        // bit and selects the first with an edge.
        const top = Module(
          name: 'top',
          attributes: <String, String>{'top': '1'},
          ports: <String, Port>{},
          cells: <String, Cell>{
            'u_drv': Cell(
              name: 'u_drv',
              type: r'$dff',
              parameters: {},
              attributes: {},
              portDirections: {'Q': PortDirection.output},
              connections: {
                'Q': [NetBit(101)],
              },
            ),
            'u_rcv': Cell(
              name: 'u_rcv',
              type: r'$dff',
              parameters: {},
              attributes: {},
              portDirections: {'D': PortDirection.input},
              connections: {
                'D': [NetBit(101)],
              },
            ),
          },
          nets: <String, Net>{
            'bus': Net(
              name: 'bus',
              bits: [NetBit(100), NetBit(101)],
              attributes: {},
            ),
          },
        );
        const model = NetlistModel(
          creator: 'probe-test',
          modules: <String, Module>{'top': top},
        );
        final container = ProviderContainer();
        addTearDown(container.dispose);
        container.read(hierarchyTreeProvider.notifier).setModel(model);
        final probe = AnalysisSelectionProbe(container);

        expect(probe.selectNet('bus'), isTrue);
        final primary = container.read(selectedElementProvider).primary;
        expect(primary, isA<SelectedElementWire>());
        expect((primary as SelectedElementWire).netId, 101);
      },
    );
  });

  group('exact-name probes (the Netlist Diff View)', () {
    test('revealCellIn navigates, selects and reveals', () {
      final container = makeContainer();
      final probe = AnalysisSelectionProbe(container);
      expect(probe.revealCellIn('sync', 'ff1'), isTrue);
      expect(container.read(hierarchyTreeProvider).selected!.path, <String>[
        'u_sync',
      ]);
      expect(
        container.read(selectedElementProvider).primary,
        const SelectedElement.cell(cellId: 'ff1'),
      );
      expect(container.read(revealRequestProvider), 'ff1');
    });

    test('revealCellIn takes a generated name whole', () {
      // A Yosys-generated name holds dots and slashes; `selectCell` would
      // split it and look for `v:3$1`.
      const name = r'$add$/home/me/rtl/counter.v:3$1';
      const top = Module(
        name: 'top',
        attributes: <String, String>{'top': '1'},
        ports: <String, Port>{},
        cells: <String, Cell>{
          name: Cell(
            name: name,
            type: r'$add',
            parameters: {},
            attributes: {},
            portDirections: {},
            connections: {},
          ),
        },
        nets: <String, Net>{},
      );
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(hierarchyTreeProvider.notifier)
          .setModel(
            const NetlistModel(
              creator: 'probe-test',
              modules: <String, Module>{'top': top},
            ),
          );
      final probe = AnalysisSelectionProbe(container);
      expect(probe.revealCellIn('top', name), isTrue);
      expect(
        container.read(selectedElementProvider).primary,
        const SelectedElement.cell(cellId: name),
      );
      expect(container.read(revealRequestProvider), name);
    });

    test('revealCellIn is false for a cell no scope declares', () {
      final container = makeContainer();
      final probe = AnalysisSelectionProbe(container);
      expect(probe.revealCellIn('top', 'ff1'), isFalse);
      expect(container.read(selectedElementProvider).isEmpty, isTrue);
      expect(container.read(revealRequestProvider), isNull);
    });

    test('revealNetIn selects the wire and reveals its driver', () {
      final container = makeContainer();
      final probe = AnalysisSelectionProbe(container);
      expect(probe.revealNetIn('top', 'async_data'), isTrue);
      final primary = container.read(selectedElementProvider).primary;
      expect(primary, isA<SelectedElementWire>());
      expect((primary as SelectedElementWire).netId, 5);
      expect(container.read(revealRequestProvider), 'u_src');
    });

    test('selectPortIn selects the boundary port of the module scope', () {
      final container = makeContainer();
      final probe = AnalysisSelectionProbe(container);
      expect(probe.selectPortIn('sync', 'D'), isTrue);
      expect(
        container.read(hierarchyTreeProvider).selected!.moduleName,
        'sync',
      );
      expect(
        container.read(selectedElementProvider).primary,
        const SelectedElement.boundaryPort(portId: 'port:D', portName: 'D'),
      );
    });

    test('enterModule pushes to a scope of the module', () {
      final container = makeContainer();
      final probe = AnalysisSelectionProbe(container);
      expect(probe.enterModule('sync'), isTrue);
      expect(container.read(hierarchyTreeProvider).selected!.path, <String>[
        'u_sync',
      ]);
      expect(probe.enterModule('nope'), isFalse);
    });
  });
}
