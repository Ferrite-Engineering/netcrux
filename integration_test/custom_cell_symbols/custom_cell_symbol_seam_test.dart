// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/custom_cell_symbols/custom_cell_symbol_seam_test.dart
//
// Verification driver for the custom cell symbols extension-point seam
// (Open-Core Guide §7.7): boots the real open-core app, seeds a loaded
// design (Yosys-free, via the design-seed helper), and dispatches every
// `CustomCellSymbolRegistry` operation against a real module type from
// the loaded design (`u_cpu`, Yosys type `cpu`). Asserts the
// `customCellSymbolRegistryProvider` seam resolves to the open-core
// `NoopCustomCellSymbolRegistry` default and that every read/write
// completes cleanly, producing the documented no-op result: `lookup`
// always returns `null` (so the schematic renderer falls through to the
// built-in cell painters), `listAll` / `snapshot` are always empty, and
// `changed` never emits.
//
// Inverted counterpart of the Pro overlay's activation test
// (which asserts the seam resolves to the Pro implementation in a Pro
// build): this asserts the open-core no-op default resolves and dispatches
// cleanly with nothing else loaded.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:netcrux/domain/interfaces/custom_cell_symbol_registry.dart';
import 'package:netcrux/domain/models/custom_cell_symbol/custom_cell_symbol.dart';
import 'package:netcrux/features/project/providers/current_laid_out_graph_provider.dart';
import 'package:netcrux/services/custom_cell_symbols/custom_cell_symbol_registry_provider.dart';

import '../fixtures/design_seed_netlist.dart';
import '../helpers/app_driver.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets(
    'custom cell symbols seam resolves to the open-core no-op registry '
    'and dispatches cleanly against a loaded design',
    (tester) async {
      await bootNetcrux(tester, extraOverrides: designSeedBootOverrides());

      final seeded = await seedDesignIntoNewTab(
        tester,
        netlistJson: designSeedNetlistJson,
      );
      final tab = seeded.tab;

      // The top scope lays out asynchronously (elkjs) after the model is
      // injected — wait for it, mirroring
      // `design/seeded_design_journey_test.dart`.
      final topLaidOut = await pumpUntil(
        tester,
        () {
          final graph = tab.read(currentLaidOutGraphProvider).value;
          if (graph == null) return false;
          return graph.graph.cells.any((c) => c.id == 'u_cpu');
        },
        timeout: const Duration(seconds: 30),
      );
      expect(topLaidOut, isTrue, reason: 'top scope never laid out');

      final laidOut = tab.read(currentLaidOutGraphProvider).value;
      expect(laidOut, isNotNull, reason: 'seeded design must be laid out');
      expect(laidOut!.isEmpty, isFalse);
      final cpuCell = laidOut.graph.cells.firstWhere((c) => c.id == 'u_cpu');
      final moduleType = cpuCell.type;
      expect(moduleType, 'cpu');

      // The seam provider is root-scoped (never re-bound per tab — see
      // `netcrux_tab_overrides.dart`), matching every other extension-point
      // Provider documented in CLAUDE.md.
      final root = rootContainer(tester);
      final registry = root.read(customCellSymbolRegistryProvider);
      expect(
        registry,
        isA<NoopCustomCellSymbolRegistry>(),
        reason:
            'open-core resolves customCellSymbolRegistryProvider to the '
            'no-op default until a Pro overlay registers a concrete '
            'implementation',
      );
      expect(registry.snapshot, isEmpty);

      // Lookup against a module type that really exists on the loaded
      // schematic — the documented no-op contract still returns null, so
      // the renderer falls through to the built-in painter for cpu.
      final match = await registry.lookup(moduleType);
      expect(match, isNull);
      expect(await registry.listAll(), isEmpty);

      final symbol = CustomCellSymbol(
        id: 'seam-test-symbol',
        moduleType: moduleType,
        kind: CustomCellSymbolKind.path,
        content: 'M0 0 L10 0 L10 10 L0 10 Z',
        width: 10,
        height: 10,
        portAnchors: const {},
        createdAt: '2026-07-19T00:00:00Z',
        updatedAt: '2026-07-19T00:00:00Z',
      );

      // Mutating calls must complete without throwing and must not change
      // the observable registry contents — the documented no-op contract.
      await registry.addOrUpdate(symbol);
      expect(registry.snapshot, isEmpty);
      expect(await registry.listAll(), isEmpty);
      expect(await registry.lookup(moduleType), isNull);
      await registry.remove(symbol.id);
      expect(registry.snapshot, isEmpty);

      // The change stream never emits — no subscriber ever wakes up.
      await expectLater(registry.changed, emitsDone);

      // The convenience snapshot provider watches the same seam and must
      // resolve to the empty map, matching the renderer's fallback path.
      final snapshot = await root.read(customCellSymbolSnapshotProvider.future);
      expect(snapshot, isEmpty);

      expect(tester.takeException(), isNull);
    },
  );
}
