// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:io';

import 'package:crux_license/crux_license.dart';
import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/providers/pro_overlay_installed_provider.dart';
import 'package:netcrux/core/shortcuts/netcrux_action.dart';
import 'package:netcrux/domain/models/workspace/netcrux_tab_payload.dart';
import 'package:netcrux/features/viewer/providers/panel_layout_provider.dart';
import 'package:netcrux/features/workspace/services/workspace_action_dispatcher.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/activity/activity_heatmap_pane_openers.dart';
import 'package:netcrux/services/cdc/cdc_pane_openers.dart';
import 'package:netcrux/services/custom_cell_symbols/custom_cell_symbol_openers.dart';
import 'package:netcrux/services/diff/diff_pane_openers.dart';
import 'package:netcrux/services/fsm/fsm_pane_openers.dart';
import 'package:netcrux/services/reset_domain/reset_domain_pane_openers.dart';
import 'package:netcrux/services/session/bookmark_annotation_openers.dart';
import 'package:netcrux/services/source_pane/source_pane_openers.dart';
import 'package:netcrux/services/workspace/netcrux_pane_overrides.dart';
import 'package:netcrux/services/workspace/netcrux_tab_overrides.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_codec.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_notifier.dart';
import 'package:netcrux/shared/widgets/workspace_managers_scope.dart';
import '../../../helpers/telemetry_test_overrides.dart';

/// How the dispatcher routes an action. Every [NetcruxAction] belongs to
/// exactly one class; the completeness pin below fails when a new action
/// is added without being classified here, which is the same failure mode
/// as the dispatcher's own `default`-free switch.
enum _Routing {
  /// Fans out through a `*OpenerProvider` extension-point callback.
  opener,

  /// Reads the active tab's `ProviderContainer` and no-ops without one.
  tabScoped,

  /// Mutates the panel-layout notifier on the root container.
  panelLayout,

  /// Mutates the workspace notifier (tabs / panes).
  workspaceScoped,

  /// Pushes a dialog, route, or platform picker.
  overlay,

  /// Delegates to a callback the screen injects.
  screenCallback,

  /// Deliberate no-op until the consuming surface ships.
  inert,

  /// Terminates the process; never dispatched from a test.
  processExit,
}

const _routing = <NetcruxAction, _Routing>{
  NetcruxAction.openProject: _Routing.screenCallback,
  NetcruxAction.openSourceFiles: _Routing.screenCallback,
  NetcruxAction.openNetlistJson: _Routing.screenCallback,

  NetcruxAction.toggleHierarchyTree: _Routing.panelLayout,
  NetcruxAction.toggleInspector: _Routing.panelLayout,
  NetcruxAction.toggleDiagnosticsPanel: _Routing.panelLayout,
  // Tab Diagnostics (WaveCrux's chord) reveals the bottom dock's
  // Diagnostics tab: it selects via bottomDockTabProvider and opens the
  // region through the panel-layout notifier — the same root-container
  // layout mutation as the toggles above.
  NetcruxAction.openTabDiagnostics: _Routing.panelLayout,

  NetcruxAction.zoomFitAll: _Routing.tabScoped,
  NetcruxAction.zoomIn: _Routing.tabScoped,
  NetcruxAction.zoomOut: _Routing.tabScoped,
  NetcruxAction.popOutScope: _Routing.tabScoped,
  NetcruxAction.jumpToTop: _Routing.tabScoped,
  NetcruxAction.clearOverlay: _Routing.tabScoped,
  NetcruxAction.clearConeOfInfluence: _Routing.tabScoped,
  NetcruxAction.clearXTrace: _Routing.tabScoped,
  NetcruxAction.showFanin: _Routing.tabScoped,
  NetcruxAction.showFanout: _Routing.tabScoped,
  NetcruxAction.exportPng: _Routing.tabScoped,
  NetcruxAction.exportSvg: _Routing.tabScoped,
  NetcruxAction.exportJson: _Routing.tabScoped,
  NetcruxAction.saveSession: _Routing.tabScoped,
  NetcruxAction.openSession: _Routing.tabScoped,
  NetcruxAction.showConeOfInfluenceFanin: _Routing.tabScoped,
  NetcruxAction.showConeOfInfluenceFanout: _Routing.tabScoped,
  NetcruxAction.showXTrace: _Routing.tabScoped,

  NetcruxAction.splitPaneRight: _Routing.workspaceScoped,
  NetcruxAction.closePane: _Routing.workspaceScoped,
  NetcruxAction.focusOtherPane: _Routing.workspaceScoped,
  NetcruxAction.moveTabToOtherPane: _Routing.workspaceScoped,
  NetcruxAction.closeProject: _Routing.workspaceScoped,
  // Cmd/Ctrl+W (suite keyboard-parity pass) — same close-the-active-tab
  // implementation as closeProject, so the same workspace routing.
  NetcruxAction.closeTab: _Routing.workspaceScoped,
  // The workspace lifecycle and tab-cycling commands in the File / View
  // menus. `newWorkspace` and
  // `resetWorkspace` confirm first, so they are overlay-routed.
  NetcruxAction.saveWorkspaceAs: _Routing.workspaceScoped,
  NetcruxAction.nextTab: _Routing.workspaceScoped,
  NetcruxAction.previousTab: _Routing.workspaceScoped,

  NetcruxAction.openSettings: _Routing.overlay,
  NetcruxAction.newWorkspace: _Routing.overlay,
  NetcruxAction.resetWorkspace: _Routing.overlay,
  // Opens the browser rather than a Flutter surface, but it is the same
  // "leaves the app to show something" class as the dialogs here.
  NetcruxAction.openDocumentation: _Routing.overlay,
  NetcruxAction.openAbout: _Routing.overlay,
  NetcruxAction.openCommandPalette: _Routing.overlay,
  NetcruxAction.openSearch: _Routing.overlay,
  NetcruxAction.showCrossProbePanel: _Routing.overlay,
  NetcruxAction.importFilelist: _Routing.overlay,
  // Beta-release infrastructure. `checkForUpdates` surfaces its
  // outcome as a SnackBar via the root ScaffoldMessenger; `submitIssue`
  // pushes the shared reporter dialog.
  NetcruxAction.checkForUpdates: _Routing.overlay,
  NetcruxAction.submitIssue: _Routing.overlay,
  // App Diagnostics pushes its own dialog and reads the same session-context
  // provider the reporter sends.
  NetcruxAction.openAppDiagnostics: _Routing.overlay,

  // Delegates to the screen's Open Workspace… flow, shared with the
  // empty-canvas button.
  NetcruxAction.openWorkspace: _Routing.screenCallback,

  // Writes the app-settings notifier, not the workspace.
  NetcruxAction.toggleTheme: _Routing.panelLayout,

  NetcruxAction.showXTracePanel: _Routing.inert,
  NetcruxAction.quit: _Routing.processExit,

  NetcruxAction.addBookmark: _Routing.opener,
  NetcruxAction.showBookmarksPanel: _Routing.opener,
  NetcruxAction.addAnnotation: _Routing.opener,
  NetcruxAction.showAnnotationsPanel: _Routing.opener,
  NetcruxAction.showSourcePane: _Routing.opener,
  NetcruxAction.openSourceForElement: _Routing.opener,
  NetcruxAction.closeSourcePane: _Routing.opener,
  NetcruxAction.showDiffPane: _Routing.opener,
  NetcruxAction.loadComparisonNetlist: _Routing.opener,
  NetcruxAction.clearComparisonNetlist: _Routing.opener,
  NetcruxAction.navigateNextDiff: _Routing.opener,
  NetcruxAction.navigatePrevDiff: _Routing.opener,
  NetcruxAction.openSymbolManager: _Routing.opener,
  NetcruxAction.importSymbolFromSvg: _Routing.opener,
  NetcruxAction.editSymbolForCurrentInstance: _Routing.opener,
  NetcruxAction.removeSymbolForCurrentInstance: _Routing.opener,
  NetcruxAction.showFsmBubbleDiagram: _Routing.opener,
  NetcruxAction.detectFsmForCurrentRegister: _Routing.opener,
  NetcruxAction.runFsmDetectionAcrossDesign: _Routing.opener,
  NetcruxAction.clearFsmSelection: _Routing.opener,
  NetcruxAction.showCdcAnalysisPane: _Routing.opener,
  NetcruxAction.runCdcAnalysis: _Routing.opener,
  NetcruxAction.showCdcCrossingForSelectedSignal: _Routing.opener,
  NetcruxAction.clearCdcAnalysisSelection: _Routing.opener,
  NetcruxAction.showResetDomainAnalysisPane: _Routing.opener,
  NetcruxAction.runResetDomainAnalysis: _Routing.opener,
  NetcruxAction.showResetCrossingForSelectedSignal: _Routing.opener,
  NetcruxAction.clearResetAnalysisSelection: _Routing.opener,
  NetcruxAction.openWaveformFile: _Routing.opener,
  NetcruxAction.closeWaveformFile: _Routing.opener,
  NetcruxAction.showActivityHeatmap: _Routing.opener,
  NetcruxAction.runActivityAnalysis: _Routing.opener,
  NetcruxAction.clearActivityColoring: _Routing.opener,
  NetcruxAction.configureActivityScheme: _Routing.opener,
};

Iterable<NetcruxAction> _actionsRouted(_Routing routing) =>
    _routing.entries.where((e) => e.value == routing).map((e) => e.key);

/// Overrides every opener extension point with a recorder that appends
/// its action to [fired]. Dispatching one action must land exactly one
/// entry — a mis-wired case in the dispatcher's switch shows up as the
/// wrong action (or none) being recorded.
List<Override> _recordingOpeners(List<NetcruxAction> fired) {
  void record(NetcruxAction a) => fired.add(a);
  return <Override>[
    addBookmarkDialogOpenerProvider.overrideWithValue(
      (_, _, {target}) => record(NetcruxAction.addBookmark),
    ),
    bookmarksPanelOpenerProvider.overrideWithValue(
      (_) => record(NetcruxAction.showBookmarksPanel),
    ),
    addAnnotationDialogOpenerProvider.overrideWithValue(
      (_, _, {target}) => record(NetcruxAction.addAnnotation),
    ),
    annotationsPanelOpenerProvider.overrideWithValue(
      (_) => record(NetcruxAction.showAnnotationsPanel),
    ),
    showSourcePaneOpenerProvider.overrideWithValue(
      (_) => record(NetcruxAction.showSourcePane),
    ),
    openSourceForElementOpenerProvider.overrideWithValue(
      (_, _, {elementId}) => record(NetcruxAction.openSourceForElement),
    ),
    closeSourcePaneOpenerProvider.overrideWithValue(
      (_) => record(NetcruxAction.closeSourcePane),
    ),
    showDiffPaneOpenerProvider.overrideWithValue(
      (_) => record(NetcruxAction.showDiffPane),
    ),
    loadComparisonNetlistOpenerProvider.overrideWithValue(
      (_, _) => record(NetcruxAction.loadComparisonNetlist),
    ),
    clearComparisonNetlistOpenerProvider.overrideWithValue(
      (_) => record(NetcruxAction.clearComparisonNetlist),
    ),
    navigateNextDiffOpenerProvider.overrideWithValue(
      (_) => record(NetcruxAction.navigateNextDiff),
    ),
    navigatePrevDiffOpenerProvider.overrideWithValue(
      (_) => record(NetcruxAction.navigatePrevDiff),
    ),
    openSymbolManagerOpenerProvider.overrideWithValue(
      (_) => record(NetcruxAction.openSymbolManager),
    ),
    importSymbolFromSvgOpenerProvider.overrideWithValue(
      (_, _) => record(NetcruxAction.importSymbolFromSvg),
    ),
    editSymbolForCurrentInstanceOpenerProvider.overrideWithValue(
      (_, _, {moduleType}) =>
          record(NetcruxAction.editSymbolForCurrentInstance),
    ),
    removeSymbolForCurrentInstanceOpenerProvider.overrideWithValue(
      (_, _, {moduleType}) =>
          record(NetcruxAction.removeSymbolForCurrentInstance),
    ),
    showFsmBubbleDiagramOpenerProvider.overrideWithValue(
      (_) => record(NetcruxAction.showFsmBubbleDiagram),
    ),
    detectFsmForCurrentRegisterOpenerProvider.overrideWithValue(
      (_, _, {stateRegisterId}) =>
          record(NetcruxAction.detectFsmForCurrentRegister),
    ),
    runFsmDetectionAcrossDesignOpenerProvider.overrideWithValue(
      (_, _) => record(NetcruxAction.runFsmDetectionAcrossDesign),
    ),
    clearFsmSelectionOpenerProvider.overrideWithValue(
      (_) => record(NetcruxAction.clearFsmSelection),
    ),
    showCdcAnalysisPaneOpenerProvider.overrideWithValue(
      (_) => record(NetcruxAction.showCdcAnalysisPane),
    ),
    runCdcAnalysisOpenerProvider.overrideWithValue(
      (_, _) => record(NetcruxAction.runCdcAnalysis),
    ),
    showCdcCrossingForSelectedSignalOpenerProvider.overrideWithValue(
      (_, _, {signalPath, signalId}) =>
          record(NetcruxAction.showCdcCrossingForSelectedSignal),
    ),
    clearCdcAnalysisSelectionOpenerProvider.overrideWithValue(
      (_) => record(NetcruxAction.clearCdcAnalysisSelection),
    ),
    showResetDomainAnalysisPaneOpenerProvider.overrideWithValue(
      (_) => record(NetcruxAction.showResetDomainAnalysisPane),
    ),
    runResetDomainAnalysisOpenerProvider.overrideWithValue(
      (_, _) => record(NetcruxAction.runResetDomainAnalysis),
    ),
    showResetCrossingForSelectedSignalOpenerProvider.overrideWithValue(
      (_, _, {signalPath, signalId}) =>
          record(NetcruxAction.showResetCrossingForSelectedSignal),
    ),
    clearResetAnalysisSelectionOpenerProvider.overrideWithValue(
      (_) => record(NetcruxAction.clearResetAnalysisSelection),
    ),
    openWaveformFileOpenerProvider.overrideWithValue(
      (_, _) => record(NetcruxAction.openWaveformFile),
    ),
    closeWaveformFileOpenerProvider.overrideWithValue(
      (_, _) => record(NetcruxAction.closeWaveformFile),
    ),
    showActivityHeatmapOpenerProvider.overrideWithValue(
      (_) => record(NetcruxAction.showActivityHeatmap),
    ),
    runActivityAnalysisOpenerProvider.overrideWithValue(
      (_, _) => record(NetcruxAction.runActivityAnalysis),
    ),
    clearActivityColoringOpenerProvider.overrideWithValue(
      (_, _) => record(NetcruxAction.clearActivityColoring),
    ),
    configureActivitySchemeOpenerProvider.overrideWithValue(
      (_) => record(NetcruxAction.configureActivityScheme),
    ),
  ];
}

void main() {
  test('every action is classified exactly once', () {
    expect(
      _routing.keys.toSet(),
      NetcruxAction.values.toSet(),
      reason:
          'a new NetcruxAction must be classified here at the same time '
          'the dispatcher grows a case for it',
    );
  });

  test('the opener class covers every opener extension point', () {
    // 34 opener providers, 34 opener-routed actions — the recorder list
    // and the routing table have to agree or the per-action assertions
    // below silently stop covering an opener.
    expect(
      _recordingOpeners(<NetcruxAction>[]),
      hasLength(_actionsRouted(_Routing.opener).length),
    );
  });

  test('every Pro-tier action routes through an opener or the tab', () {
    for (final action in NetcruxAction.values) {
      if (action.requiredTier == LicenseTier.openCore) continue;
      expect(
        _routing[action],
        anyOf(_Routing.opener, _Routing.tabScoped),
        reason:
            '$action is tier-gated, so it must dispatch through a seam '
            'the gate wraps',
      );
    }
  });

  /// Pumps a dispatcher inside a workspace scope. When [withTab] is
  /// false the workspace has no tabs, so `activeTabContainerOrNull`
  /// resolves to null — the null-guard path every tab-scoped case
  /// carries.
  Future<(WorkspaceActionDispatcher, BuildContext, ProviderContainer)>
  pumpDispatcher(
    WidgetTester tester, {
    List<Override> overrides = const [],
    bool withTab = false,
    Future<void> Function()? openProject,
    Future<void> Function()? openSourceFiles,
    Future<void> Function()? openNetlistJson,
    Future<void> Function()? openWorkspaceFlow,
  }) async {
    final root = ProviderContainer(
      overrides: <Override>[
        ...netcruxTelemetryTestOverrides(),
        // The workspace's launch gate reads the settings service before it
        // loads the document; the production one would await a platform
        // channel this zone never pumps.
        netcruxWorkspaceProvider.overrideWith(
          () => NetcruxWorkspaceNotifier(
            service: WorkspaceService<NetcruxTabPayload>(
              codec: const NetcruxWorkspaceCodec(),
              directoryFactory: () async =>
                  Directory.systemTemp.createTempSync('nc_dispatch_table_'),
              logger: (_) {},
            ),
            autoSaveDebounce: Duration.zero,
            // Fake-async zone: the settings-backed launch gate's
            // platform-channel reply would never arrive before the first
            // pump, and this test awaits the workspace future first.
            restoreGate: () async => true,
          ),
        ),
        ...overrides,
      ],
    );
    addTearDown(() => tester.pump(const Duration(seconds: 10)));
    final tabs = TabContainerManager(
      rootContainer: root,
      overridesFactory: netcruxTabOverridesFactory,
    );
    final panes = PaneContainerManager(
      rootContainer: root,
      overridesFactory: netcruxPaneOverridesFactory,
    );
    addTearDown(() {
      tabs.dispose();
      panes.dispose();
      root.dispose();
    });
    await root.read(netcruxWorkspaceProvider.future);
    if (withTab) {
      await root
          .read(netcruxWorkspaceProvider.notifier)
          .openTab(
            displayName: 'top',
            payload: const NetcruxTabPayload(
              sourceFiles: <String>[],
              topModule: 'top',
            ),
          );
    }

    late WorkspaceActionDispatcher dispatcher;
    late BuildContext hostContext;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: root,
        child: WorkspaceManagersScope(
          tabContainerManager: tabs,
          paneContainerManager: panes,
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
                  return const SizedBox.expand();
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return (dispatcher, hostContext, root);
  }

  group('opener routing', () {
    for (final action in _actionsRouted(_Routing.opener)) {
      testWidgets('$action reaches exactly its own opener', (tester) async {
        final fired = <NetcruxAction>[];
        final (dispatcher, context, _) = await pumpDispatcher(
          tester,
          overrides: [
            // Beta admits every tier and the Pro overlay is present, so
            // this test observes routing rather than gating (the gate has
            // its own suite).
            betaPeriodProvider.overrideWithValue(true),
            proOverlayInstalledProvider.overrideWithValue(true),
            ..._recordingOpeners(fired),
          ],
        );

        dispatcher.dispatch(context, action);
        await tester.pump();

        expect(
          fired,
          <NetcruxAction>[action],
          reason: '$action must fan out through its own opener, once',
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('tier gating over the opener table', () {
    testWidgets('post-beta open-core denies every Pro-tier opener action', (
      tester,
    ) async {
      final fired = <NetcruxAction>[];
      final (dispatcher, context, _) = await pumpDispatcher(
        tester,
        overrides: [
          betaPeriodProvider.overrideWithValue(false),
          licenseTierProvider.overrideWith((_) => LicenseTier.openCore),
          ..._recordingOpeners(fired),
        ],
      );

      final pro = _actionsRouted(
        _Routing.opener,
      ).where((a) => a.requiredTier == LicenseTier.pro).toList();
      expect(pro, isNotEmpty);
      for (final action in pro) {
        dispatcher.dispatch(context, action);
      }
      await tester.pump();

      expect(
        fired,
        isEmpty,
        reason: 'no Pro opener may fire for an insufficient tier',
      );
    });

    testWidgets('post-beta Pro tier admits every Pro-tier opener action', (
      tester,
    ) async {
      final fired = <NetcruxAction>[];
      final (dispatcher, context, _) = await pumpDispatcher(
        tester,
        overrides: [
          betaPeriodProvider.overrideWithValue(false),
          licenseTierProvider.overrideWith((_) => LicenseTier.pro),
          proOverlayInstalledProvider.overrideWithValue(true),
          ..._recordingOpeners(fired),
        ],
      );

      final pro = _actionsRouted(
        _Routing.opener,
      ).where((a) => a.requiredTier == LicenseTier.pro).toList();
      for (final action in pro) {
        dispatcher.dispatch(context, action);
      }
      await tester.pump();

      expect(fired, pro);
    });

    testWidgets('open-core opener actions dispatch at every tier', (
      tester,
    ) async {
      final fired = <NetcruxAction>[];
      final (dispatcher, context, _) = await pumpDispatcher(
        tester,
        overrides: [
          betaPeriodProvider.overrideWithValue(false),
          licenseTierProvider.overrideWith((_) => LicenseTier.openCore),
          ..._recordingOpeners(fired),
        ],
      );

      final free = _actionsRouted(
        _Routing.opener,
      ).where((a) => a.requiredTier == LicenseTier.openCore).toList();
      expect(free, isNotEmpty);
      for (final action in free) {
        dispatcher.dispatch(context, action);
      }
      await tester.pump();

      expect(fired, free);
    });
  });

  group('tab-scoped null guards', () {
    testWidgets('every tab-scoped action no-ops with no active tab', (
      tester,
    ) async {
      final (dispatcher, context, _) = await pumpDispatcher(
        tester,
        overrides: [betaPeriodProvider.overrideWithValue(true)],
      );

      for (final action in _actionsRouted(_Routing.tabScoped)) {
        dispatcher.dispatch(context, action);
        await tester.pump();
        expect(
          tester.takeException(),
          isNull,
          reason: '$action must null-guard the missing active tab',
        );
      }
    });

    testWidgets('every tab-scoped action survives an active tab', (
      tester,
    ) async {
      final (dispatcher, context, _) = await pumpDispatcher(
        tester,
        overrides: [betaPeriodProvider.overrideWithValue(true)],
        withTab: true,
      );

      for (final action in _actionsRouted(_Routing.tabScoped)) {
        // Export / session actions open platform pickers, which have no
        // mock handler here; they are exercised by their own controller
        // suites.
        if (action == NetcruxAction.exportPng ||
            action == NetcruxAction.exportSvg ||
            action == NetcruxAction.exportJson ||
            action == NetcruxAction.saveSession ||
            action == NetcruxAction.openSession) {
          continue;
        }
        dispatcher.dispatch(context, action);
        await tester.pump();
        expect(
          tester.takeException(),
          isNull,
          reason: '$action must dispatch cleanly against an empty tab',
        );
      }
    });
  });

  group('root-scoped routing', () {
    testWidgets('panel-layout actions toggle their own panel', (tester) async {
      final (dispatcher, context, root) = await pumpDispatcher(tester);
      final before = root.read(panelLayoutProvider);

      dispatcher.dispatch(context, NetcruxAction.toggleHierarchyTree);
      await tester.pump();
      expect(
        root.read(panelLayoutProvider).hierarchyTreeVisible,
        !before.hierarchyTreeVisible,
      );

      dispatcher.dispatch(context, NetcruxAction.toggleInspector);
      await tester.pump();
      expect(
        root.read(panelLayoutProvider).inspectorVisible,
        !before.inspectorVisible,
      );

      dispatcher.dispatch(context, NetcruxAction.toggleDiagnosticsPanel);
      await tester.pump();
      expect(
        root.read(panelLayoutProvider).diagnosticsVisible,
        !before.diagnosticsVisible,
      );
    });

    testWidgets('screen-callback actions route to the injected callbacks', (
      tester,
    ) async {
      var projectCalls = 0;
      var sourceCalls = 0;
      var netlistCalls = 0;
      final (dispatcher, context, _) = await pumpDispatcher(
        tester,
        openProject: () async => projectCalls++,
        openSourceFiles: () async => sourceCalls++,
        openNetlistJson: () async => netlistCalls++,
      );

      dispatcher
        ..dispatch(context, NetcruxAction.openProject)
        ..dispatch(context, NetcruxAction.openSourceFiles)
        ..dispatch(context, NetcruxAction.openNetlistJson);
      await tester.pump();

      expect(projectCalls, 1);
      expect(sourceCalls, 1);
      expect(netlistCalls, 1);
    });

    testWidgets('closeProject closes the active tab', (tester) async {
      final (dispatcher, context, root) = await pumpDispatcher(
        tester,
        withTab: true,
      );
      expect(root.read(netcruxWorkspaceProvider).value!.activeTabId, isNotNull);

      dispatcher.dispatch(context, NetcruxAction.closeProject);
      await tester.pump();

      expect(root.read(netcruxWorkspaceProvider).value!.activeTabId, isNull);
    });

    testWidgets('closeProject with no tabs is a no-op', (tester) async {
      final (dispatcher, context, _) = await pumpDispatcher(tester);

      dispatcher.dispatch(context, NetcruxAction.closeProject);
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('closeTab closes the active tab', (tester) async {
      final (dispatcher, context, root) = await pumpDispatcher(
        tester,
        withTab: true,
      );
      expect(root.read(netcruxWorkspaceProvider).value!.activeTabId, isNotNull);

      dispatcher.dispatch(context, NetcruxAction.closeTab);
      await tester.pump();

      expect(root.read(netcruxWorkspaceProvider).value!.activeTabId, isNull);
    });

    testWidgets('closeTab with no tabs is a no-op', (tester) async {
      final (dispatcher, context, _) = await pumpDispatcher(tester);

      dispatcher.dispatch(context, NetcruxAction.closeTab);
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('split / focus / move pane actions mutate the workspace', (
      tester,
    ) async {
      final (dispatcher, context, root) = await pumpDispatcher(
        tester,
        withTab: true,
      );

      dispatcher.dispatch(context, NetcruxAction.splitPaneRight);
      await tester.pump();
      expect(root.read(netcruxWorkspaceProvider).value!.panes, hasLength(2));

      final firstActive = root
          .read(netcruxWorkspaceProvider)
          .value!
          .activePaneId;
      dispatcher.dispatch(context, NetcruxAction.focusOtherPane);
      await tester.pump();
      expect(
        root.read(netcruxWorkspaceProvider).value!.activePaneId,
        isNot(firstActive),
      );

      dispatcher.dispatch(context, NetcruxAction.moveTabToOtherPane);
      await tester.pump();
      expect(tester.takeException(), isNull);

      dispatcher.dispatch(context, NetcruxAction.closePane);
      await tester.pump();
      expect(root.read(netcruxWorkspaceProvider).value!.panes, hasLength(1));
    });

    testWidgets('single-pane closePane / moveTabToOtherPane are no-ops', (
      tester,
    ) async {
      final (dispatcher, context, root) = await pumpDispatcher(
        tester,
        withTab: true,
      );

      dispatcher
        ..dispatch(context, NetcruxAction.closePane)
        ..dispatch(context, NetcruxAction.moveTabToOtherPane);
      await tester.pump();

      expect(root.read(netcruxWorkspaceProvider).value!.panes, hasLength(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the inert action dispatches without side effects', (
      tester,
    ) async {
      final fired = <NetcruxAction>[];
      final (dispatcher, context, _) = await pumpDispatcher(
        tester,
        overrides: _recordingOpeners(fired),
      );

      dispatcher.dispatch(context, NetcruxAction.showXTracePanel);
      await tester.pump();

      expect(fired, isEmpty);
      expect(tester.takeException(), isNull);
    });
  });
}
