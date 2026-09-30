// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/tabs/missing_engine_recovery_test.dart
//
// Verification driver for Open-Core Guide §4.1.7 (missing-file /
// missing-engine recovery surfaces): opens a real project whose
// elaboration cannot run because the Yosys engine is unavailable — the
// same `LoadedNetlistException(kind: yosysUnavailable)` a project
// pointed at a vanished source file's Yosys dependency would also hit —
// and asserts the three surfaces the guide names all recover cleanly
// instead of crashing:
//
//  1. Canvas — `SchematicErrorView` renders the localized "elaboration
//     failed" envelope.
//  2. Hierarchy panel — falls back to the "elaboration failed" empty
//     message instead of the "no design" placeholder.
//  3. Tab Diagnostics drawer — `_FatalErrorBanner` surfaces the raw
//     exception message.
//
// The engine-unavailable path is used (rather than deleting a source
// file out from under an open tab) because it is deterministic on any
// host — CI and dev machines may or may not have Yosys on PATH, but
// pinning `yosysAvailabilityProvider` to `YosysAvailability.notFound`
// (the same override `helpers/app_driver.dart`'s
// `designSeedBootOverrides` uses) guarantees the same
// `LoadedNetlistErrorKind.yosysUnavailable` failure on every run, and
// exercises the identical fatal-error rendering path a missing-file
// failure (a Yosys non-zero exit, `LoadedNetlistErrorKind.nonZeroExit`)
// would hit downstream of the same `loadedAsync.hasError` branches.

import 'dart:io';

import 'package:crux_yosys/crux_yosys.dart' show YosysAvailability;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:netcrux/domain/models/workspace/netcrux_tab_payload.dart';
import 'package:netcrux/features/diagnostics/widgets/tab_diagnostics_drawer.dart';
import 'package:netcrux/features/hierarchy/widgets/hierarchy_tree_panel.dart';
import 'package:netcrux/features/project/providers/current_project_provider.dart';
import 'package:netcrux/features/project/providers/loaded_netlist_provider.dart';
import 'package:netcrux/features/viewer/providers/panel_layout_provider.dart';
import 'package:netcrux/features/workspace/widgets/project_tab_content.dart';
import 'package:netcrux/features/workspace/widgets/schematic_error_view.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_notifier.dart';
import 'package:netcrux/services/yosys/yosys_availability_provider.dart';

import '../helpers/app_driver.dart';

const _kUnavailableReason = 'missing-engine-recovery-test';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets(
    'missing-engine elaboration failure recovers cleanly on canvas, '
    'hierarchy, and diagnostics surfaces (Guide §4.1.7)',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync(
        'netcrux_missing_engine_',
      );
      addTearDown(() => dir.deleteSync(recursive: true));
      final sourcePath = '${dir.path}/top.v';
      File(sourcePath).writeAsStringSync('module top(); endmodule\n');

      await bootNetcrux(
        tester,
        extraOverrides: <Override>[
          yosysAvailabilityProvider.overrideWith(
            (ref) async => const YosysAvailability.notFound(
              reason: _kUnavailableReason,
            ),
          ),
        ],
      );

      // Open the project the same way the welcome-screen "Open Source
      // Files…" flow and `_openSourceFilesByPaths` do: a real tab whose
      // payload points at a real (existing) source file.
      final root = rootContainer(tester);
      await root
          .read(netcruxWorkspaceProvider.notifier)
          .openTab(
            displayName: 'top',
            payload: NetcruxTabPayload.empty,
          );
      await pumpUntil(tester, () => activeTabId(tester) != null);
      final mounted = await pumpUntil(
        tester,
        () => tester.any(find.byType(ProjectTabContent)),
      );
      expect(mounted, isTrue, reason: 'the opened tab never mounted');
      final tab = activeTabContainer(tester);
      tab.read(currentProjectProvider.notifier).setSourceFiles(
        <String>[sourcePath],
      );

      // The elaboration pipeline settles on the pinned yosys-unavailable
      // failure — deterministic, no real subprocess spawned.
      final settled = await pumpUntil(
        tester,
        () => tab.read(loadedNetlistProvider).hasError,
        timeout: const Duration(seconds: 20),
      );
      expect(
        settled,
        isTrue,
        reason:
            'elaboration never settled on an error; state: '
            '${tab.read(loadedNetlistProvider)}',
      );
      final error = tab.read(loadedNetlistProvider).error;
      expect(error, isA<LoadedNetlistException>());
      final exception = error! as LoadedNetlistException;
      expect(exception.kind, LoadedNetlistErrorKind.yosysUnavailable);
      expect(exception.detail, _kUnavailableReason);

      // Flush the frame(s) so every watcher (canvas / hierarchy / status
      // bar) rebuilds against the settled error state.
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      final context = tester.element(find.byType(ProjectTabContent).first);
      final l10n = L10N.of(context);

      // ── 1. Canvas: SchematicErrorView renders the localized envelope
      // instead of crashing on the null laid-out graph.
      expect(find.byType(SchematicErrorView), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(SchematicErrorView),
          matching: find.text(l10n.elaborationErrorYosysUnavailable),
        ),
        findsOneWidget,
        reason: 'canvas must show the localized yosys-unavailable message',
      );

      // ── 2. Hierarchy panel: "elaboration failed" fallback, not the
      // generic "no design loaded" placeholder.
      expect(
        find.descendant(
          of: find.byType(HierarchyTreePanel),
          matching: find.text(
            l10n.hierarchyEmptyElaborationFailed(exception.message),
          ),
        ),
        findsOneWidget,
        reason:
            'hierarchy panel must distinguish elaboration failure from '
            'an empty tab',
      );

      // ── 3. Tab Diagnostics drawer: the fatal-error banner. The panel
      // is collapsed by default, so make it visible first (the same
      // mutation the View-menu toggle / drag-to-expand handle drives).
      await root
          .read(panelLayoutProvider.notifier)
          .setDiagnosticsVisible(visible: true);
      await tester.pump();
      await tester.pump();

      expect(find.byType(TabDiagnosticsDrawer), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(TabDiagnosticsDrawer),
          matching: find.text(l10n.elaborationDiagnosticsFatal),
        ),
        findsOneWidget,
        reason: 'diagnostics drawer must show the fatal-error banner title',
      );
      expect(
        find.descendant(
          of: find.byType(TabDiagnosticsDrawer),
          matching: find.text(exception.message),
        ),
        findsOneWidget,
        reason: 'diagnostics drawer must show the raw exception message',
      );

      expect(tester.takeException(), isNull);
    },
  );
}
