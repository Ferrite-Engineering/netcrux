// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The pane render-stats popover in the real app: paint readings are per pane,
// layout time is per TAB, so the Layout row has to read the tab showing in the
// pane. The popover tests that put both providers in one container cannot see
// that.

import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/workspace/netcrux_tab_payload.dart';
import 'package:netcrux/features/statistics/providers/layout_timing_provider.dart';
import 'package:netcrux/features/viewer/providers/pane_render_stats.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_notifier.dart';

import '../../helpers/app_boot_overrides.dart';
import '../../helpers/workspace_app_harness.dart';

const _painted = PaneRenderStats(
  frameNumber: 7,
  paintMicroseconds: 1200,
  visibleCells: 3,
  visibleEdges: 4,
  totalCells: 30,
  totalEdges: 40,
);

void main() {
  testWidgets('the Layout row shows the layout time written in the pane tab', (
    tester,
  ) async {
    final h = await WorkspaceAppHarness.boot(
      tester,
      preferences: <String, Object>{
        ...kEulaAcceptedPrefs,
        kTelemetryConsentKey: 'disabled',
      },
    );
    final notifier = h.root.read(netcruxWorkspaceProvider.notifier);
    late TabId a;
    late TabId b;
    await tester.runAsync(() async {
      a = await notifier.openTab(
        displayName: 'a',
        payload: const NetcruxTabPayload(
          sourceFiles: <String>[],
          topModule: 'a',
        ),
      );
      b = await notifier.openTab(
        displayName: 'b',
        payload: const NetcruxTabPayload(
          sourceFiles: <String>[],
          topModule: 'b',
        ),
      );
    });
    await WorkspaceAppHarness.settle(tester);
    await tester.runAsync(() => notifier.setActiveTab(a));
    await WorkspaceAppHarness.settle(tester);

    // Layout ran in tab a only; tab b and the root saw none.
    h.tabs
        .containerFor(a)
        .read(layoutTimingProvider.notifier)
        .completed(const Duration(milliseconds: 250));
    h.tabs
        .containerFor(b)
        .read(layoutTimingProvider.notifier)
        .completed(const Duration(milliseconds: 90));

    final button = find.byKey(const Key('paneRenderStatsButton'));
    expect(button, findsOneWidget);
    ProviderScope.containerOf(
      tester.element(button),
    ).read(paneRenderStatsProvider.notifier).record(_painted);
    await tester.pump();

    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(find.text('250.0 ms'), findsOneWidget);
    expect(find.text('90.0 ms'), findsNothing);
    expect(find.text('—'), findsNothing);

    // A layout pass finishing while the popover is open updates the row.
    h.tabs
        .containerFor(a)
        .read(layoutTimingProvider.notifier)
        .completed(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('400.0 ms'), findsOneWidget);

    await WorkspaceAppHarness.unmount(tester);
  });
}
