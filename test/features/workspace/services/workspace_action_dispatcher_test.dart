// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:crux_settings/crux_settings.dart';
import 'package:crux_theme/crux_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/providers/pro_overlay_installed_provider.dart';
import 'package:netcrux/core/shortcuts/netcrux_action.dart';
import 'package:netcrux/domain/models/app_settings.dart';
import 'package:netcrux/features/diagnostics/providers/diagnostics_providers.dart';
import 'package:netcrux/features/diagnostics/widgets/app_diagnostics_dialog.dart';
import 'package:netcrux/features/settings/providers/app_settings_provider.dart';
import 'package:netcrux/features/workspace/services/workspace_action_dispatcher.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/netcrux_color_theme_bootstrap.dart';
import 'package:netcrux/services/diff/diff_pane_openers.dart';
import 'package:netcrux/services/session/bookmark_annotation_openers.dart';
import 'package:netcrux/services/settings/netcrux_settings_codec.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/telemetry_test_overrides.dart';

/// Direct unit coverage for the extracted [WorkspaceActionDispatcher].
/// The deep, all-26-Pro-actions gate matrix lives in
/// `test/features/workspace/screens/workspace_screen_gating_test.dart`,
/// which drives the dispatcher through the real `WorkspaceScreen`; this
/// file pins the collaborator's own contract — callback routing and the
/// tier gate — without the full app harness.
void main() {
  /// Pumps a minimal host and hands the test a dispatcher built from a
  /// live [WidgetRef], mirroring how `_WorkspaceScreenState` constructs
  /// it.
  Future<(WorkspaceActionDispatcher, BuildContext)> pumpDispatcher(
    WidgetTester tester, {
    required List<Override> overrides,
    Future<void> Function()? openProject,
    Future<void> Function()? openSourceFiles,
    Future<void> Function()? openNetlistJson,
    Future<void> Function()? openWorkspaceFlow,
  }) async {
    late WorkspaceActionDispatcher dispatcher;
    late BuildContext hostContext;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [...netcruxTelemetryTestOverrides(), ...overrides],
        child: MaterialApp(
          localizationsDelegates: L10N.localizationsDelegates,
          supportedLocales: L10N.supportedLocales,
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                hostContext = context;
                dispatcher = WorkspaceActionDispatcher(
                  ref: ref,
                  openProject: openProject ?? () async {},
                  openSourceFiles: openSourceFiles ?? () async {},
                  openNetlistJson: openNetlistJson ?? () async {},
                  openWorkspaceFlow: openWorkspaceFlow ?? () async {},
                );
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );
    return (dispatcher, hostContext);
  }

  testWidgets('openProject / openSourceFiles route to the injected '
      'screen callbacks', (tester) async {
    var projectCalls = 0;
    var sourceCalls = 0;
    final (dispatcher, context) = await pumpDispatcher(
      tester,
      overrides: const [],
      openProject: () async => projectCalls++,
      openSourceFiles: () async => sourceCalls++,
    );

    dispatcher
      ..dispatch(context, NetcruxAction.openProject)
      ..dispatch(context, NetcruxAction.openSourceFiles);
    await tester.pump();

    expect(projectCalls, 1);
    expect(sourceCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('post-beta open-core tier blocks a gated Pro opener and '
      'shows the upgrade dialog', (tester) async {
    var openerCalls = 0;
    final (dispatcher, context) = await pumpDispatcher(
      tester,
      overrides: [
        betaPeriodProvider.overrideWithValue(false),
        licenseTierProvider.overrideWith((_) => LicenseTier.openCore),
        addBookmarkDialogOpenerProvider.overrideWithValue(
          (context, ref, {target}) => openerCalls++,
        ),
      ],
    );

    dispatcher.dispatch(context, NetcruxAction.addBookmark);
    await tester.pumpAndSettle();

    expect(openerCalls, 0, reason: 'insufficient tier must not dispatch');
    expect(
      find.byType(CruxUpgradeDialog),
      findsOneWidget,
      reason: 'the deny path must explain itself instead of no-oping',
    );
    final l10n = L10N.of(context);
    expect(find.text(l10n.upgradeDialogTitle), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('beta period never shows the upgrade dialog', (tester) async {
    final (dispatcher, context) = await pumpDispatcher(
      tester,
      overrides: [
        betaPeriodProvider.overrideWithValue(true),
        licenseTierProvider.overrideWith((_) => LicenseTier.openCore),
        proOverlayInstalledProvider.overrideWithValue(true),
        addBookmarkDialogOpenerProvider.overrideWithValue(
          (context, ref, {target}) {},
        ),
      ],
    );

    dispatcher.dispatch(context, NetcruxAction.addBookmark);
    await tester.pumpAndSettle();

    expect(find.byType(CruxUpgradeDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('beta period short-circuits the gate for every tier', (
    tester,
  ) async {
    var openerCalls = 0;
    final (dispatcher, context) = await pumpDispatcher(
      tester,
      overrides: [
        betaPeriodProvider.overrideWithValue(true),
        licenseTierProvider.overrideWith((_) => LicenseTier.openCore),
        proOverlayInstalledProvider.overrideWithValue(true),
        addBookmarkDialogOpenerProvider.overrideWithValue(
          (context, ref, {target}) => openerCalls++,
        ),
      ],
    );

    dispatcher.dispatch(context, NetcruxAction.addBookmark);
    await tester.pump();

    expect(openerCalls, 1, reason: 'beta admits every tier');
    expect(tester.takeException(), isNull);
  });

  testWidgets('ungated clear/dismiss openers dispatch without a tier '
      'check', (tester) async {
    var openerCalls = 0;
    final (dispatcher, context) = await pumpDispatcher(
      tester,
      overrides: [
        betaPeriodProvider.overrideWithValue(false),
        licenseTierProvider.overrideWith((_) => LicenseTier.openCore),
        clearComparisonNetlistOpenerProvider.overrideWithValue(
          (context) => openerCalls++,
        ),
      ],
    );

    dispatcher.dispatch(context, NetcruxAction.clearComparisonNetlist);
    await tester.pump();

    expect(openerCalls, 1, reason: 'clearing is never tier-gated');
    expect(tester.takeException(), isNull);
  });

  testWidgets('App Diagnostics with the gate off names the Settings category '
      'that holds the switch', (tester) async {
    final (dispatcher, context) = await pumpDispatcher(
      tester,
      overrides: [diagnosticsEnabledProvider.overrideWithValue(false)],
    );

    dispatcher.dispatch(context, NetcruxAction.openAppDiagnostics);
    await tester.pump();

    expect(
      find.text(
        'Diagnostics surfaces are turned off. Enable them in '
        'Settings > General.',
      ),
      findsOneWidget,
    );
    expect(find.byType(AppDiagnosticsDialog), findsNothing);
  });

  group('Toggle Theme', () {
    // Brightness follows the active preset (`themeModeFromBrightness` in
    // app.dart), so the toggle has to change the preset for anything to
    // change on screen.
    Future<(WorkspaceActionDispatcher, BuildContext, ProviderContainer)>
    pumpThemed(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final (dispatcher, context) = await pumpDispatcher(
        tester,
        overrides: [
          settingsServiceProvider.overrideWithValue(
            SettingsService<AppSettings>(
              const NetcruxSettingsCodec(),
              prefsOverride: prefs,
            ),
          ),
          netcruxCruxColorThemeOverride,
        ],
      );
      final container = ProviderScope.containerOf(context);
      await container.read(appSettingsProvider.future);
      return (dispatcher, context, container);
    }

    testWidgets('switches Crux Dark to Crux Light and back', (tester) async {
      final (dispatcher, context, container) = await pumpThemed(tester);
      expect(
        themeModeFromBrightness(container.read(cruxColorThemeProvider)),
        ThemeMode.dark,
      );

      dispatcher.dispatch(context, NetcruxAction.toggleTheme);
      await tester.pump();
      expect(container.read(cruxColorThemeProvider).id, cruxLightPresetId);
      expect(
        themeModeFromBrightness(container.read(cruxColorThemeProvider)),
        ThemeMode.light,
      );

      dispatcher.dispatch(context, NetcruxAction.toggleTheme);
      await tester.pump();
      expect(container.read(cruxColorThemeProvider).id, cruxDarkPresetId);
      expect(tester.takeException(), isNull);
    });

    testWidgets('from another dark preset it lands on Crux Light', (
      tester,
    ) async {
      final (dispatcher, context, container) = await pumpThemed(tester);
      final other = builtinPresets().values.firstWhere(
        (t) => t.brightness == Brightness.dark && t.id != cruxDarkPresetId,
      );
      container.read(cruxColorThemeProvider.notifier).activate(other);
      await tester.pump();

      dispatcher.dispatch(context, NetcruxAction.toggleTheme);
      await tester.pump();
      expect(container.read(cruxColorThemeProvider).id, cruxLightPresetId);
    });
  });
}
