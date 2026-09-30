// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/schematic/cone_of_influence_seam_test.dart
//
// Verification driver for the cone-of-influence extension-point seam
// (Open-Core Guide §7.1): boots the real open-core app, seeds a loaded
// design (Yosys-free, via the design-seed helper), selects a cell, and
// dispatches a cone-of-influence request the same way
// `WorkspaceActionDispatcher._dispatchConeOfInfluence` does. Asserts the
// `coneOfInfluenceServiceProvider` seam resolves to the open-core
// `NoopConeOfInfluenceService` default and that both the sync and async
// (`computeAsync`, the isolate-offload seam) entry points complete
// cleanly against a real laid-out graph, producing the documented no-op
// result: `TraceOverlay.empty`.
//
// Inverted counterpart of the Pro overlay's activation test
// (which asserts the seam resolves to the Pro implementation in a Pro
// build): this asserts the open-core no-op default resolves and dispatches
// cleanly with nothing else loaded.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:netcrux/domain/interfaces/cone_of_influence_service.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/domain/models/trace/trace_overlay.dart';
import 'package:netcrux/features/project/providers/current_laid_out_graph_provider.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/services/schematic/cone_of_influence_service_provider.dart';

import '../fixtures/design_seed_netlist.dart';
import '../helpers/app_driver.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets(
    'cone-of-influence seam resolves to the open-core no-op default and '
    'dispatches cleanly against a loaded design',
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
      bool graphHasCell(String id) {
        final graph = tab.read(currentLaidOutGraphProvider).value;
        if (graph == null) return false;
        return graph.graph.cells.any((c) => c.id == id);
      }

      final topLaidOut = await pumpUntil(
        tester,
        () => graphHasCell('u_cpu'),
        timeout: const Duration(seconds: 30),
      );
      expect(topLaidOut, isTrue, reason: 'top scope never laid out');

      // The seam provider is root-scoped (never re-bound per tab — see
      // `netcrux_tab_overrides.dart`), matching every other extension-point
      // Provider documented in CLAUDE.md.
      final root = rootContainer(tester);
      final service = root.read(coneOfInfluenceServiceProvider);
      expect(
        service,
        isA<NoopConeOfInfluenceService>(),
        reason:
            'open-core resolves coneOfInfluenceServiceProvider to the '
            'no-op default until a Pro overlay registers a concrete '
            'implementation',
      );

      // Select a real cell in the seeded design so the request carries a
      // non-empty selection, matching the dispatcher's guard clause.
      tab
          .read(selectedElementProvider.notifier)
          .select(const SelectedElement.cell(cellId: 'u_cpu'));
      await tester.pump();

      final laidOut = tab.read(currentLaidOutGraphProvider).value;
      expect(laidOut, isNotNull, reason: 'seeded design must be laid out');
      expect(laidOut!.isEmpty, isFalse);

      final selection = tab.read(selectedElementProvider);
      expect(selection.isEmpty, isFalse);

      final faninRequest = ConeOfInfluenceRequest(
        laidOut: laidOut,
        selection: selection.primary,
        mode: ConeOfInfluenceMode.fanin,
        depth: null,
      );

      // Sync seam.
      expect(service.compute(faninRequest), TraceOverlay.empty);
      // Async seam — the isolate-offload variant the dispatcher
      // actually calls; the open-core default just runs compute() inline.
      final faninOverlay = await service.computeAsync(faninRequest);
      expect(faninOverlay, TraceOverlay.empty);

      // Fanout too, for coverage of the mode enum's other branch.
      final fanoutOverlay = await service.computeAsync(
        ConeOfInfluenceRequest(
          laidOut: laidOut,
          selection: selection.primary,
          mode: ConeOfInfluenceMode.fanout,
          depth: null,
        ),
      );
      expect(fanoutOverlay, TraceOverlay.empty);

      expect(tester.takeException(), isNull);
    },
  );
}
