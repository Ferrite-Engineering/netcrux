// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/schematic/x_trace_seam_test.dart
//
// Verification driver for the X-trace extension-point seam (Open-Core
// Guide §7.4): boots the real open-core app, seeds a loaded design
// (Yosys-free, via the design-seed helper), selects a cell, and dispatches
// an X-trace request the same way
// `WorkspaceActionDispatcher._dispatchXTrace` does. Asserts the
// `xTraceServiceProvider` seam resolves to the open-core `NoopXTraceService`
// default and that both the sync and async (`traceAsync`, the
// isolate-offload seam) entry points complete cleanly against a real
// laid-out graph, producing the documented no-op result:
// `XTraceResult.empty`.
//
// Inverted counterpart of the Pro overlay's activation test
// (which asserts the seam resolves to the Pro implementation in a Pro
// build): this asserts the open-core no-op default resolves and dispatches
// cleanly with nothing else loaded.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:netcrux/domain/interfaces/x_trace_service.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/features/project/providers/current_laid_out_graph_provider.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/services/schematic/x_trace_service_provider.dart';

import '../fixtures/design_seed_netlist.dart';
import '../helpers/app_driver.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets(
    'X-trace seam resolves to the open-core no-op default and dispatches '
    'cleanly against a loaded design',
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
      final service = root.read(xTraceServiceProvider);
      expect(
        service,
        isA<NoopXTraceService>(),
        reason:
            'open-core resolves xTraceServiceProvider to the no-op '
            'default until a Pro overlay registers a concrete '
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

      final request = XTraceRequest(
        laidOut: laidOut,
        selection: selection.primary,
      );

      // Sync seam.
      expect(service.trace(request), XTraceResult.empty);
      // Async seam — the isolate-offload variant the dispatcher
      // actually calls; the open-core default just runs trace() inline.
      final result = await service.traceAsync(request);
      expect(result, XTraceResult.empty);
      expect(result.termination, XTraceTermination.noTraceableSelection);

      expect(tester.takeException(), isNull);
    },
  );
}
