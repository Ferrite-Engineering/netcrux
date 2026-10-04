// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_license/crux_license.dart';
import 'package:crux_settings/crux_settings.dart';
import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/app.dart';
import 'package:netcrux/core/providers/pro_overlay_installed_provider.dart';
import 'package:netcrux/core/shortcuts/netcrux_action.dart';
import 'package:netcrux/core/shortcuts/netcrux_action_descriptors.dart';
import 'package:netcrux/core/shortcuts/shortcut_manager_widget.dart';
import 'package:netcrux/domain/models/app_settings.dart';
import 'package:netcrux/domain/models/workspace/netcrux_tab_payload.dart';
import 'package:netcrux/features/settings/providers/app_settings_provider.dart';
import 'package:netcrux/services/activity/activity_heatmap_pane_openers.dart';
import 'package:netcrux/services/cdc/cdc_pane_openers.dart';
import 'package:netcrux/services/custom_cell_symbols/custom_cell_symbol_openers.dart';
import 'package:netcrux/services/diff/diff_pane_openers.dart';
import 'package:netcrux/services/fsm/fsm_pane_openers.dart';
import 'package:netcrux/services/reset_domain/reset_domain_pane_openers.dart';
import 'package:netcrux/services/session/bookmark_annotation_openers.dart';
import 'package:netcrux/services/settings/netcrux_settings_codec.dart';
import 'package:netcrux/services/source_pane/source_pane_openers.dart';
import 'package:netcrux/services/workspace/netcrux_pane_overrides.dart';
import 'package:netcrux/services/workspace/netcrux_tab_overrides.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_codec.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_notifier.dart';
import 'package:netcrux/shared/widgets/workspace_managers_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/app_boot_overrides.dart';

/// Verifies that `WorkspaceActionDispatcher.dispatch` (driven here through the real screen) routes every Pro-tier
/// action through the single `_proActionAllowed` tier gate, so a Pro
/// opener never fires for an insufficient license tier.
///
/// This is the regression test for the 2026-07-16 review finding: nine
/// Pro-tier actions (bookmark / annotation / source-pane / waveform /
/// activity) dispatched their openers UNGUARDED, so post-beta an
/// open-core-tier user could invoke the full Pro UI from the command
/// palette. The fix collapsed the five duplicate `_xxxActionAllowed`
/// helpers into one `_proActionAllowed(NetcruxAction)` (reading the
/// action's `requiredTier`) and applied it to every Pro dispatch case,
/// including the nine that were ungated.
///
/// `_proActionAllowed` consults the overridable `betaPeriodProvider`
/// rather than the compile-time `kBetaPeriod` constant, so the three
/// scenarios below exercise the real gate both
/// ways: post-beta + Pro admits, post-beta + open-core denies (the
/// shipping behavior at the beta flip), and beta short-circuits to admit
/// every tier.
///
/// The opener-backed Pro actions asserted below cover all nine
/// previously-ungated actions plus one-or-more from each of the five
/// collapsed helper groups (diff / custom-cell-symbol / fsm / cdc /
/// reset-domain). The three service-backed Pro actions
/// (`showConeOfInfluenceFanin` / `showConeOfInfluenceFanout` /
/// `showXTrace`) route through the same `_proActionAllowed(action)` gate
/// at the same switch site, but their dispatch reads the active-tab
/// selection + laid-out graph and early-returns on the empty canvas, so
/// they can't be observed through an opener spy in this harness.
void main() {
  // Every Pro dispatch case that fans out through an opener provider,
  // paired with the action it should record when the gate permits it.
  // These are exactly the actions `_dispatchAction` wraps in
  // `if (_proActionAllowed(action))`.
  const gatedOpenerActions = <NetcruxAction>[
    // The nine that shipped UNGATED (the review finding).
    NetcruxAction.addBookmark,
    NetcruxAction.addAnnotation,
    NetcruxAction.showSourcePane,
    // The two panels only the Pro overlay provides.
    NetcruxAction.showBookmarksPanel,
    NetcruxAction.showAnnotationsPanel,
    NetcruxAction.openSourceForElement,
    NetcruxAction.openWaveformFile,
    NetcruxAction.closeWaveformFile,
    NetcruxAction.showActivityHeatmap,
    NetcruxAction.runActivityAnalysis,
    NetcruxAction.configureActivityScheme,
    // Diff group (was `_diffActionAllowed`).
    NetcruxAction.showDiffPane,
    NetcruxAction.loadComparisonNetlist,
    NetcruxAction.navigateNextDiff,
    NetcruxAction.navigatePrevDiff,
    // Custom-cell-symbol group (was `_customCellSymbolActionAllowed`).
    NetcruxAction.openSymbolManager,
    NetcruxAction.importSymbolFromSvg,
    NetcruxAction.editSymbolForCurrentInstance,
    NetcruxAction.removeSymbolForCurrentInstance,
    // FSM group (was `_fsmActionAllowed`).
    NetcruxAction.showFsmBubbleDiagram,
    NetcruxAction.detectFsmForCurrentRegister,
    NetcruxAction.runFsmDetectionAcrossDesign,
    // CDC group (was `_cdcActionAllowed`).
    NetcruxAction.showCdcAnalysisPane,
    NetcruxAction.runCdcAnalysis,
    NetcruxAction.showCdcCrossingForSelectedSignal,
    // Reset-domain group (was `_resetDomainActionAllowed`).
    NetcruxAction.showResetDomainAnalysisPane,
    NetcruxAction.runResetDomainAnalysis,
    NetcruxAction.showResetCrossingForSelectedSignal,
  ];

  test('every gated opener action is declared Pro-tier', () {
    // Guards the list above against drift: if one of these were ever
    // relabelled to open-core, gating it would be wrong (and vice versa).
    for (final action in gatedOpenerActions) {
      expect(
        action.requiredTier,
        LicenseTier.pro,
        reason: '$action must be Pro-tier for the dispatch gate to apply',
      );
    }
  });

  testWidgets(
    'every Pro action reaches its opener when the tier is satisfied',
    (tester) async {
      final fired = <NetcruxAction>{};
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        await _bootApp(
          extraOverrides: <Override>[
            // Post-beta + Pro tier: the gate admits (Pro satisfies the Pro
            // requirement via featureEquivalent), so every opener fires.
            licenseTierProvider.overrideWithValue(LicenseTier.pro),
            betaPeriodProvider.overrideWithValue(false),
            proOverlayInstalledProvider.overrideWithValue(true),
            ..._spyOpenerOverrides(fired),
          ],
        ),
      );
      await tester.pumpAndSettle();

      _dispatchAll(tester, gatedOpenerActions);
      await tester.pump();

      expect(fired, gatedOpenerActions.toSet());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'no Pro action reaches its opener when the tier is insufficient',
    (tester) async {
      final fired = <NetcruxAction>{};
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        await _bootApp(
          extraOverrides: <Override>[
            // Open-core tier + post-beta: the gate must deny every Pro
            // action, so no opener records. This is the shipping behavior at
            // the beta flip. It exercises the real denial branch because
            // `_proActionAllowed` reads the overridable
            // `betaPeriodProvider` rather than the compile-time
            // `kBetaPeriod` constant.
            licenseTierProvider.overrideWithValue(LicenseTier.openCore),
            betaPeriodProvider.overrideWithValue(false),
            ..._spyOpenerOverrides(fired),
          ],
        ),
      );
      await tester.pumpAndSettle();

      _dispatchAll(tester, gatedOpenerActions);
      await tester.pump();

      expect(fired, isEmpty);
      // Each denial surfaces the upgrade dialog (one per dispatched
      // action here — the dialogs stack because the harness fires all 26
      // without dismissing).
      expect(find.byType(CruxUpgradeDialog), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'beta short-circuit admits every Pro action even at open-core tier',
    (tester) async {
      final fired = <NetcruxAction>{};
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        await _bootApp(
          extraOverrides: <Override>[
            // During the public beta every gate admits regardless of tier —
            // badges communicate the future pricing model but never block.
            licenseTierProvider.overrideWithValue(LicenseTier.openCore),
            betaPeriodProvider.overrideWithValue(true),
            proOverlayInstalledProvider.overrideWithValue(true),
            ..._spyOpenerOverrides(fired),
          ],
        ),
      );
      await tester.pumpAndSettle();

      _dispatchAll(tester, gatedOpenerActions);
      await tester.pump();

      expect(fired, gatedOpenerActions.toSet());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'without the Pro overlay every Pro action says it requires NetCrux Pro',
    (tester) async {
      // An open-core build during the beta: the tier gate admits, but
      // nothing is installed behind the action. Before, each dispatched to
      // the open-core no-op and nothing happened at all.
      final fired = <NetcruxAction>{};
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        await _bootApp(
          extraOverrides: <Override>[
            licenseTierProvider.overrideWithValue(LicenseTier.openCore),
            betaPeriodProvider.overrideWithValue(true),
            ..._spyOpenerOverrides(fired),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final shortcuts = tester.widget<ShortcutManagerWidget>(
        find.byType(ShortcutManagerWidget),
      );
      for (final action in gatedOpenerActions) {
        shortcuts.handlers[action]!();
        await tester.pump();
        expect(
          find.textContaining('requires NetCrux Pro'),
          findsOneWidget,
          reason: '$action must explain itself',
        );
        // Clear the snackbar so the next action's own message is the one
        // found.
        ScaffoldMessenger.of(
          tester.element(find.byType(ShortcutManagerWidget)),
        ).removeCurrentSnackBar();
        await tester.pump();
      }
      expect(fired, isEmpty);
      expect(find.byType(CruxUpgradeDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'the mounted keyboard surface consults the real descriptor context',
    (tester) async {
      // Pins the production wiring: WorkspaceScreen must hand
      // ShortcutManagerWidget a resolver over the shared context
      // provider, so a chord for a context-dependent action is inert on
      // the empty workspace while an always-available action stays live.
      // The chord-level blocking behavior itself is unit-tested in
      // shortcut_manager_widget_test.dart.
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(await _bootApp());
      await tester.pumpAndSettle();

      final shortcuts = tester.widget<ShortcutManagerWidget>(
        find.byType(ShortcutManagerWidget),
      );
      final resolver = shortcuts.actionContextResolver;
      expect(
        resolver,
        isNotNull,
        reason: 'the workspace shell must gate the keyboard surface',
      );
      final ctx = resolver!();
      expect(ctx.hasOpenTab, isFalse, reason: 'harness starts tab-less');
      expect(isActionEnabled(NetcruxAction.closeProject, ctx), isFalse);
      expect(isActionEnabled(NetcruxAction.openProject, ctx), isTrue);
    },
  );
}

/// Invokes each [actions] entry through the mounted `ShortcutManagerWidget`
/// handler map — the exact closures `WorkspaceScreen.build` installs, one
/// per action, that call `_dispatchAction(context, action)`.
void _dispatchAll(WidgetTester tester, List<NetcruxAction> actions) {
  final shortcuts = tester.widget<ShortcutManagerWidget>(
    find.byType(ShortcutManagerWidget),
  );
  for (final action in actions) {
    shortcuts.handlers[action]!();
  }
}

/// Recording spies for every opener a gated Pro dispatch case fans out
/// to. Each spy adds its action to [fired] so the tests can assert which
/// openers the dispatcher actually reached.
List<Override> _spyOpenerOverrides(Set<NetcruxAction> fired) => <Override>[
  bookmarksPanelOpenerProvider.overrideWithValue(
    (_) => fired.add(NetcruxAction.showBookmarksPanel),
  ),
  annotationsPanelOpenerProvider.overrideWithValue(
    (_) => fired.add(NetcruxAction.showAnnotationsPanel),
  ),
  addBookmarkDialogOpenerProvider.overrideWithValue(
    (_, _, {target}) => fired.add(NetcruxAction.addBookmark),
  ),
  addAnnotationDialogOpenerProvider.overrideWithValue(
    (_, _, {target}) => fired.add(NetcruxAction.addAnnotation),
  ),
  showSourcePaneOpenerProvider.overrideWithValue(
    (_) => fired.add(NetcruxAction.showSourcePane),
  ),
  openSourceForElementOpenerProvider.overrideWithValue(
    (_, _, {elementId}) => fired.add(NetcruxAction.openSourceForElement),
  ),
  showDiffPaneOpenerProvider.overrideWithValue(
    (_) => fired.add(NetcruxAction.showDiffPane),
  ),
  loadComparisonNetlistOpenerProvider.overrideWithValue(
    (_, _) => fired.add(NetcruxAction.loadComparisonNetlist),
  ),
  navigateNextDiffOpenerProvider.overrideWithValue(
    (_) => fired.add(NetcruxAction.navigateNextDiff),
  ),
  navigatePrevDiffOpenerProvider.overrideWithValue(
    (_) => fired.add(NetcruxAction.navigatePrevDiff),
  ),
  openSymbolManagerOpenerProvider.overrideWithValue(
    (_) => fired.add(NetcruxAction.openSymbolManager),
  ),
  importSymbolFromSvgOpenerProvider.overrideWithValue(
    (_, _) => fired.add(NetcruxAction.importSymbolFromSvg),
  ),
  editSymbolForCurrentInstanceOpenerProvider.overrideWithValue(
    (_, _, {moduleType}) =>
        fired.add(NetcruxAction.editSymbolForCurrentInstance),
  ),
  removeSymbolForCurrentInstanceOpenerProvider.overrideWithValue(
    (_, _, {moduleType}) =>
        fired.add(NetcruxAction.removeSymbolForCurrentInstance),
  ),
  showFsmBubbleDiagramOpenerProvider.overrideWithValue(
    (_) => fired.add(NetcruxAction.showFsmBubbleDiagram),
  ),
  detectFsmForCurrentRegisterOpenerProvider.overrideWithValue(
    (_, _, {stateRegisterId}) =>
        fired.add(NetcruxAction.detectFsmForCurrentRegister),
  ),
  runFsmDetectionAcrossDesignOpenerProvider.overrideWithValue(
    (_, _) => fired.add(NetcruxAction.runFsmDetectionAcrossDesign),
  ),
  showCdcAnalysisPaneOpenerProvider.overrideWithValue(
    (_) => fired.add(NetcruxAction.showCdcAnalysisPane),
  ),
  runCdcAnalysisOpenerProvider.overrideWithValue(
    (_, _) => fired.add(NetcruxAction.runCdcAnalysis),
  ),
  showCdcCrossingForSelectedSignalOpenerProvider.overrideWithValue(
    (_, _, {signalPath, signalId, target}) =>
        fired.add(NetcruxAction.showCdcCrossingForSelectedSignal),
  ),
  showResetDomainAnalysisPaneOpenerProvider.overrideWithValue(
    (_) => fired.add(NetcruxAction.showResetDomainAnalysisPane),
  ),
  runResetDomainAnalysisOpenerProvider.overrideWithValue(
    (_, _) => fired.add(NetcruxAction.runResetDomainAnalysis),
  ),
  showResetCrossingForSelectedSignalOpenerProvider.overrideWithValue(
    (_, _, {signalPath, signalId, target}) =>
        fired.add(NetcruxAction.showResetCrossingForSelectedSignal),
  ),
  openWaveformFileOpenerProvider.overrideWithValue(
    (_, _) => fired.add(NetcruxAction.openWaveformFile),
  ),
  closeWaveformFileOpenerProvider.overrideWithValue(
    (_, _) => fired.add(NetcruxAction.closeWaveformFile),
  ),
  showActivityHeatmapOpenerProvider.overrideWithValue(
    (_) => fired.add(NetcruxAction.showActivityHeatmap),
  ),
  runActivityAnalysisOpenerProvider.overrideWithValue(
    (_, _) => fired.add(NetcruxAction.runActivityAnalysis),
  ),
  configureActivitySchemeOpenerProvider.overrideWithValue(
    (_) => fired.add(NetcruxAction.configureActivityScheme),
  ),
];

/// Boots [NetcruxApp] with an in-memory workspace + settings service, plus
/// any [extraOverrides]. Mirrors the harness in `test/widget_test.dart`.
Future<Widget> _bootApp({List<Override> extraOverrides = const []}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final root = ProviderContainer(
    overrides: <Override>[
      // The two crux_shared packages NetcruxApp mounts from
      // MaterialApp.builder ship throwing defaults; without these the app
      // fails to build with an unrelated-looking provider exception.
      ...netcruxAppTestOverrides(),
      settingsServiceProvider.overrideWithValue(
        SettingsService<AppSettings>(
          const NetcruxSettingsCodec(),
          prefsOverride: prefs,
        ),
      ),
      // Use an in-memory workspace service so the test never touches the
      // host's getApplicationSupportDirectory().
      netcruxWorkspaceProvider.overrideWith(
        () => NetcruxWorkspaceNotifier(
          service: WorkspaceService<NetcruxTabPayload>(
            codec: const NetcruxWorkspaceCodec(),
            directoryFactory: () async =>
                Directory.systemTemp.createTempSync('netcrux_gating_test_'),
            logger: (_) {},
          ),
          autoSaveDebounce: const Duration(milliseconds: 50),
        ),
      ),
      ...extraOverrides,
    ],
  );
  addTearDown(root.dispose);
  final tabs = TabContainerManager(
    rootContainer: root,
    overridesFactory: netcruxTabOverridesFactory,
  );
  addTearDown(tabs.dispose);
  final panes = PaneContainerManager(
    rootContainer: root,
    overridesFactory: netcruxPaneOverridesFactory,
  );
  addTearDown(panes.dispose);
  return UncontrolledProviderScope(
    container: root,
    child: WorkspaceManagersScope(
      tabContainerManager: tabs,
      paneContainerManager: panes,
      child: const NetcruxApp(),
    ),
  );
}
