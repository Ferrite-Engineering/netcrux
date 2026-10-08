// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:crux_issue_reporter/crux_issue_reporter.dart';
import 'package:crux_license/crux_license.dart';
import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:crux_theme/crux_theme.dart';
import 'package:crux_updates/crux_updates.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/core/help_urls.dart';
import 'package:netcrux/core/netcrux_url_launcher.dart';
import 'package:netcrux/core/policy/netcrux_policy_keys.dart';
import 'package:netcrux/core/shortcuts/netcrux_action.dart';
import 'package:netcrux/core/theme/theme_brightness_toggle.dart';
import 'package:netcrux/domain/enums/netcrux_design_source.dart';
import 'package:netcrux/domain/enums/netcrux_export_kind.dart';
import 'package:netcrux/domain/interfaces/cone_of_influence_service.dart';
import 'package:netcrux/domain/interfaces/x_trace_service.dart';
import 'package:netcrux/domain/models/trace/trace_overlay.dart';
import 'package:netcrux/domain/models/workspace/netcrux_tab_payload.dart';
import 'package:netcrux/features/about/netcrux_about_dialog.dart';
import 'package:netcrux/features/annotations/services/annotation_openers.dart';
import 'package:netcrux/features/command_palette/widgets/command_palette_dialog.dart';
import 'package:netcrux/features/diagnostics/providers/diagnostics_providers.dart';
import 'package:netcrux/features/diagnostics/widgets/app_diagnostics_dialog.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/project/providers/current_project_provider.dart';
import 'package:netcrux/features/remote/providers/cross_probe_visible_provider.dart';
import 'package:netcrux/features/search/widgets/search_dialog.dart';
import 'package:netcrux/features/settings/providers/app_settings_provider.dart';
import 'package:netcrux/features/settings/screens/settings_screen.dart';
import 'package:netcrux/features/viewer/providers/canvas_fit_target_provider.dart';
import 'package:netcrux/features/viewer/providers/panel_layout_provider.dart';
import 'package:netcrux/features/viewer/providers/right_dock_provider.dart';
import 'package:netcrux/features/viewer/providers/schematic_canvas_key_provider.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/features/viewer/providers/trace_overlay_notifier.dart';
import 'package:netcrux/features/viewer/providers/viewport_transform_notifier.dart';
import 'package:netcrux/features/viewer/providers/x_trace_panel_visible_provider.dart';
import 'package:netcrux/features/viewer/services/clear_schematic_paint.dart';
import 'package:netcrux/features/viewer/services/cone_of_influence_controller.dart';
import 'package:netcrux/features/viewer/services/schematic_export_controller.dart';
import 'package:netcrux/features/viewer/services/trace_overlay_controller.dart';
import 'package:netcrux/features/viewer/services/x_trace_controller.dart';
import 'package:netcrux/features/viewer/services/zoom_to_selection_controller.dart';
import 'package:netcrux/features/workspace/services/active_tab_container.dart';
import 'package:netcrux/features/workspace/services/pro_action_gate.dart';
import 'package:netcrux/features/workspace/widgets/netcrux_docks.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/activity/activity_heatmap_pane_openers.dart';
import 'package:netcrux/services/cdc/cdc_pane_openers.dart';
import 'package:netcrux/services/collaboration/collaboration_session_openers.dart';
import 'package:netcrux/services/collaboration/schematic_collaboration_service_provider.dart';
import 'package:netcrux/services/custom_cell_symbols/custom_cell_symbol_openers.dart';
import 'package:netcrux/services/diff/diff_pane_openers.dart';
import 'package:netcrux/services/file_open/file_open_service.dart';
import 'package:netcrux/services/file_open/file_open_service_provider.dart';
import 'package:netcrux/services/filelist/filelist_reader.dart';
import 'package:netcrux/services/fsm/fsm_pane_openers.dart';
import 'package:netcrux/services/reset_domain/reset_domain_pane_openers.dart';
import 'package:netcrux/services/schematic/cone_of_influence_service_provider.dart';
import 'package:netcrux/services/schematic/x_trace_service_provider.dart';
import 'package:netcrux/services/session/session_controller.dart';
import 'package:netcrux/services/source_pane/source_pane_openers.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_notifier.dart';
import 'package:path/path.dart' as p;

/// The single dispatch point for every [NetcruxAction]. Extracted from
/// `WorkspaceScreen` so the exhaustive action switch no longer cohabits
/// a 1,000-line screen widget.
///
/// All three action-discovery surfaces route here: the keyboard handler
/// map, the native menu bar, and the command palette — one
/// implementation serves them all (see the `WorkspaceScreen` build
/// comments). The switch is deliberately `default`-free so adding a new
/// [NetcruxAction] fails compilation until this dispatcher handles it —
/// the same exhaustive-switch property the in-screen switch had.
///
/// The two file-open flows shared with the empty-canvas surface
/// ([openProject] / [openSourceFiles]) stay on the screen and are
/// injected as callbacks; everything else the dispatch needs lives here.
/// Handlers read per-tab state through `ref.activeTabContainerOrNull` so
/// they target the active tab under split-pane / multi-tab (reading a
/// per-tab provider from the root container is the scope-leak defect the
/// static scope-leak guards catch); those routing comments travel with each
/// case below. Post-await lifecycle guards use `context.mounted`, which
/// for the screen's element is the same check as the `State.mounted` the
/// in-screen handlers used.
class WorkspaceActionDispatcher {
  /// Creates the dispatcher for the workspace screen.
  WorkspaceActionDispatcher({
    required this._ref,
    required this._openProject,
    required this._openSourceFiles,
    required this._openNetlistJson,
    required this._openWorkspaceFlow,
  });

  final WidgetRef _ref;

  /// The screen's Open Project… flow (shared with the empty canvas).
  final Future<void> Function() _openProject;

  /// The screen's Open Source Files… flow (shared with the empty canvas).
  final Future<void> Function() _openSourceFiles;

  /// The screen's Open Netlist JSON… flow (shared with the browser build's
  /// empty canvas).
  final Future<void> Function() _openNetlistJson;

  /// The screen's Open Workspace… flow (shared with the empty canvas).
  final Future<void> Function() _openWorkspaceFlow;

  /// Dispatches [action]. Behavior is verbatim from the pre-extraction
  /// `WorkspaceScreen._dispatchAction`.
  void dispatch(BuildContext context, NetcruxAction action) {
    switch (action) {
      case NetcruxAction.toggleHierarchyTree:
        unawaited(
          _ref.read(panelLayoutProvider.notifier).toggleHierarchyTree(),
        );
      case NetcruxAction.toggleInspector:
        unawaited(_ref.read(panelLayoutProvider.notifier).toggleInspector());
      case NetcruxAction.toggleDiagnosticsPanel:
        unawaited(_ref.read(panelLayoutProvider.notifier).toggleDiagnostics());
      case NetcruxAction.openTabDiagnostics:
        // Reveal (never hide) the bottom dock's Diagnostics tab — NetCrux's
        // per-tab diagnostics surface. Open-only semantics mirror WaveCrux's
        // Cmd/Ctrl+Shift+I Tab Diagnostics drawer opener; the dock is
        // non-modal by construction, so the rest of the chrome stays
        // interactive, exactly like WaveCrux's OverlayEntry drawer.
        _ref
            .read(bottomDockTabProvider.notifier)
            .reveal(kBottomDockTabDiagnostics);
      case NetcruxAction.zoomFitAll:
        final c = _ref.activeTabContainerOrNull(context);
        if (c != null) {
          // Frame the whole current scope in the viewport — the same
          // "Fit All" the `0` key performs on the canvas. The canvas
          // publishes its laid-out bounds to `canvasFitTargetProvider`, so
          // this chrome-level action fits against the real design instead
          // of merely resetting to the identity transform (which framed
          // nothing — it left large designs zoomed to their top-left
          // corner). Reading the pushed target (rather than the async
          // `currentLaidOutGraphProvider`) keeps this off the
          // elaboration/layout path.
          //
          // The viewport SIZE, however, is measured LIVE off the canvas'
          // render object here rather than taken from the target: the
          // gesture handler only republishes the target's cached size when
          // it rebuilds (a scope change), so after a window/pane resize or
          // a panel toggle that size is stale. Fitting against a stale
          // (smaller) size never enlarged a small design to fill the now
          // larger pane — the "fit never zooms in" bug. Bounds, by
          // contrast, only change on a scope change (when the handler does
          // rebuild), so the published bounds stay current.
          final target = c.read(canvasFitTargetProvider);
          final notifier = c.read(viewportTransformProvider.notifier);
          if (target != null) {
            final size = _liveCanvasSize(c) ?? target.size;
            notifier.fitToBounds(size, target.bounds);
          } else {
            notifier.reset();
          }
        }
      case NetcruxAction.zoomToSelection:
        final c = _ref.activeTabContainerOrNull(context);
        if (c != null) ZoomToSelectionController(c).run();
      case NetcruxAction.popOutScope:
        final c = _ref.activeTabContainerOrNull(context);
        c?.read(hierarchyTreeProvider.notifier).popOut();
        c?.read(selectedElementProvider.notifier).clear();
        c?.read(traceOverlayProvider.notifier).clear();
      case NetcruxAction.jumpToTop:
        final c = _ref.activeTabContainerOrNull(context);
        c?.read(hierarchyTreeProvider.notifier).selectByPath(const []);
        c?.read(selectedElementProvider.notifier).clear();
        c?.read(traceOverlayProvider.notifier).clear();
      case NetcruxAction.clearOverlay:
        final c = _ref.activeTabContainerOrNull(context);
        if (c != null) clearSchematicPaint(c.read);
      case NetcruxAction.showConeOfInfluenceFanin:
        if (_proActionAllowed(context, action)) {
          unawaited(
            _dispatchConeOfInfluence(context, ConeOfInfluenceMode.fanin),
          );
        }
      case NetcruxAction.showConeOfInfluenceFanout:
        if (_proActionAllowed(context, action)) {
          unawaited(
            _dispatchConeOfInfluence(context, ConeOfInfluenceMode.fanout),
          );
        }
      case NetcruxAction.clearConeOfInfluence:
        _ref
            .activeTabContainerOrNull(context)
            ?.read(traceOverlayProvider.notifier)
            .clear();
      case NetcruxAction.showXTrace:
        if (_proActionAllowed(context, action)) {
          unawaited(_dispatchXTrace(context));
        }
      case NetcruxAction.showXTracePanel:
        _onToggleXTracePanel();
      case NetcruxAction.clearXTrace:
        final c = _ref.activeTabContainerOrNull(context);
        if (c != null) XTraceController.fromContainer(c).clear();
      case NetcruxAction.openSettings:
        unawaited(SettingsScreen.openAdaptive(context));
      case NetcruxAction.openProject:
        unawaited(_openProject());
      case NetcruxAction.openSourceFiles:
        unawaited(_openSourceFiles());
      case NetcruxAction.openNetlistJson:
        unawaited(_openNetlistJson());
      case NetcruxAction.openSearch:
        unawaited(_openSearch(context));
      case NetcruxAction.splitPaneRight:
        unawaited(_onSplitPaneRight());
      case NetcruxAction.closePane:
        unawaited(_onClosePane());
      case NetcruxAction.focusOtherPane:
        unawaited(_onFocusOtherPane());
      case NetcruxAction.moveTabToOtherPane:
        unawaited(_onMoveTabToOtherPane());
      case NetcruxAction.showCrossProbePanel:
        _onToggleCrossProbePanel();
      case NetcruxAction.addAnnotation:
        _ref.read(addAnnotationDialogOpenerProvider)(context, _ref);
      case NetcruxAction.showAnnotationsPanel:
        _ref.read(annotationsPanelOpenerProvider)(context);
      case NetcruxAction.showSourcePane:
        if (_proActionAllowed(context, action)) {
          _ref.read(showSourcePaneOpenerProvider)(context);
        }
      case NetcruxAction.openSourceForElement:
        // Command-palette dispatch passes no elementId — the Pro
        // overlay's opener falls back to the active selection.
        // Schematic context-menu dispatch invokes the opener
        // directly with the right-clicked element's id and never
        // routes through this action handler.
        if (_proActionAllowed(context, action)) {
          _ref.read(openSourceForElementOpenerProvider)(context, _ref);
        }
      case NetcruxAction.closeSourcePane:
        _ref.read(closeSourcePaneOpenerProvider)(context);
      case NetcruxAction.showDiffPane:
        if (_proActionAllowed(context, action)) {
          _ref.read(showDiffPaneOpenerProvider)(context);
        }
      case NetcruxAction.loadComparisonNetlist:
        if (_proActionAllowed(context, action)) {
          _ref.read(loadComparisonNetlistOpenerProvider)(context, _ref);
        }
      case NetcruxAction.clearComparisonNetlist:
        // Clearing is never feature-gated — open-core resolves the
        // opener to a no-op so dispatch is always safe.
        _ref.read(clearComparisonNetlistOpenerProvider)(context);
      case NetcruxAction.navigateNextDiff:
        if (_proActionAllowed(context, action)) {
          _ref.read(navigateNextDiffOpenerProvider)(context);
        }
      case NetcruxAction.navigatePrevDiff:
        if (_proActionAllowed(context, action)) {
          _ref.read(navigatePrevDiffOpenerProvider)(context);
        }
      case NetcruxAction.openSymbolManager:
        if (_proActionAllowed(context, action)) {
          _ref.read(openSymbolManagerOpenerProvider)(context);
        }
      case NetcruxAction.importSymbolFromSvg:
        if (_proActionAllowed(context, action)) {
          _ref.read(importSymbolFromSvgOpenerProvider)(context, _ref);
        }
      case NetcruxAction.editSymbolForCurrentInstance:
        if (_proActionAllowed(context, action)) {
          // Command-palette dispatch passes no moduleType — the Pro
          // overlay's opener falls back to the active selection.
          // Schematic context-menu dispatch invokes the opener
          // directly with the right-clicked cell's `cell.type` and
          // never routes through this action handler.
          _ref.read(editSymbolForCurrentInstanceOpenerProvider)(context, _ref);
        }
      case NetcruxAction.removeSymbolForCurrentInstance:
        if (_proActionAllowed(context, action)) {
          _ref.read(removeSymbolForCurrentInstanceOpenerProvider)(
            context,
            _ref,
          );
        }
      case NetcruxAction.showFsmBubbleDiagram:
        if (_proActionAllowed(context, action)) {
          _ref.read(showFsmBubbleDiagramOpenerProvider)(context);
        }
      case NetcruxAction.detectFsmForCurrentRegister:
        if (_proActionAllowed(context, action)) {
          // Command-palette dispatch passes no register id — the Pro
          // overlay's opener falls back to the active selection.
          // Schematic context-menu dispatch invokes the opener
          // directly with the right-clicked register's id and never
          // routes through this action handler.
          _ref.read(detectFsmForCurrentRegisterOpenerProvider)(context, _ref);
        }
      case NetcruxAction.runFsmDetectionAcrossDesign:
        if (_proActionAllowed(context, action)) {
          _ref.read(runFsmDetectionAcrossDesignOpenerProvider)(context, _ref);
        }
      case NetcruxAction.clearFsmSelection:
        // Clearing is never feature-gated — open-core resolves the
        // opener to a no-op so dispatch is always safe.
        _ref.read(clearFsmSelectionOpenerProvider)(context);
      case NetcruxAction.showCdcAnalysisPane:
        if (_proActionAllowed(context, action)) {
          _ref.read(showCdcAnalysisPaneOpenerProvider)(context);
        }
      case NetcruxAction.runCdcAnalysis:
        if (_proActionAllowed(context, action)) {
          _ref.read(runCdcAnalysisOpenerProvider)(context, _ref);
        }
      case NetcruxAction.showCdcCrossingForSelectedSignal:
        if (_proActionAllowed(context, action)) {
          // Command-palette dispatch passes no signal id — the Pro
          // overlay's opener falls back to the active selection.
          // Schematic context-menu dispatch invokes the opener
          // directly with the right-clicked signal's path and never
          // routes through this action handler.
          _ref.read(showCdcCrossingForSelectedSignalOpenerProvider)(
            context,
            _ref,
          );
        }
      case NetcruxAction.clearCdcAnalysisSelection:
        // Clearing is never feature-gated — open-core resolves the
        // opener to a no-op so dispatch is always safe.
        _ref.read(clearCdcAnalysisSelectionOpenerProvider)(context);
      case NetcruxAction.showResetDomainAnalysisPane:
        if (_proActionAllowed(context, action)) {
          _ref.read(showResetDomainAnalysisPaneOpenerProvider)(context);
        }
      case NetcruxAction.runResetDomainAnalysis:
        if (_proActionAllowed(context, action)) {
          _ref.read(runResetDomainAnalysisOpenerProvider)(context, _ref);
        }
      case NetcruxAction.showResetCrossingForSelectedSignal:
        if (_proActionAllowed(context, action)) {
          // Command-palette dispatch passes no signal id — the Pro
          // overlay's opener falls back to the active selection.
          // Schematic context-menu dispatch invokes the opener
          // directly with the right-clicked signal's path and never
          // routes through this action handler.
          _ref.read(showResetCrossingForSelectedSignalOpenerProvider)(
            context,
            _ref,
          );
        }
      case NetcruxAction.clearResetAnalysisSelection:
        // Clearing is never feature-gated — open-core resolves the
        // opener to a no-op so dispatch is always safe.
        _ref.read(clearResetAnalysisSelectionOpenerProvider)(context);
      case NetcruxAction.openWaveformFile:
        if (_proActionAllowed(context, action)) {
          _ref.read(openWaveformFileOpenerProvider)(context, _ref);
        }
      case NetcruxAction.closeWaveformFile:
        if (_proActionAllowed(context, action)) {
          _ref.read(closeWaveformFileOpenerProvider)(context, _ref);
        }
      case NetcruxAction.showActivityHeatmap:
        if (_proActionAllowed(context, action)) {
          _ref.read(showActivityHeatmapOpenerProvider)(context);
        }
      case NetcruxAction.runActivityAnalysis:
        if (_proActionAllowed(context, action)) {
          _ref.read(runActivityAnalysisOpenerProvider)(context, _ref);
        }
      case NetcruxAction.clearActivityColoring:
        // Clearing is never feature-gated — open-core resolves the
        // opener to a no-op so dispatch is always safe.
        _ref.read(clearActivityColoringOpenerProvider)(context, _ref);
      case NetcruxAction.configureActivityScheme:
        if (_proActionAllowed(context, action)) {
          _ref.read(configureActivitySchemeOpenerProvider)(context);
        }
      case NetcruxAction.openCommandPalette:
        unawaited(
          CommandPaletteDialog.show(
            context,
            onAction: (a) => dispatch(context, a),
          ),
        );
      case NetcruxAction.closeTab:
        // NetCrux tabs *are* projects — closing the active tab is closing
        // the active project, so both close actions share one
        // implementation. closeTab exists for the suite-wide Cmd/Ctrl+W
        // convention (keyboard-parity pass).
        unawaited(_closeActiveTab());
      case NetcruxAction.closeProject:
        unawaited(_closeActiveTab());
      case NetcruxAction.quit:
        exit(0);
      case NetcruxAction.openAbout:
        unawaited(NetcruxAboutDialog.openAdaptive(context, _ref));
      case NetcruxAction.checkForUpdates:
        // Always runs — `checkNow` ignores the Settings → General auto-check
        // toggle. The outcome is a snackbar (up to date / failed) or the
        // UpdateBanner, which renders from the same provider state.
        // ModalGuard because the flow can surface a modal download dialog and
        // the helper lives in the shared `crux_updates` package — guard at
        // the dispatch site, mirroring WaveCrux.
        unawaited(
          ModalGuard.run(
            'checkForUpdates',
            () => runManualUpdateCheck(context, _ref),
          ),
        );
      case NetcruxAction.submitIssue:
        // `openAdaptive` invalidates the session-context provider first, so
        // the snapshot is rebuilt against the tab that is active right now.
        // Guarded at the dispatch site (the opener lives in the shared
        // `crux_issue_reporter` package), mirroring WaveCrux.
        unawaited(
          ModalGuard.run(
            'issueReporter',
            () => CruxIssueReporterDialog.openAdaptive(context),
          ),
        );
      case NetcruxAction.openAppDiagnostics:
        // Reads the same session-context provider the reporter sends, so the
        // dialog and a filed issue always agree.
        //
        // The gate is checked here rather than only inside the dialog so a
        // release build with diagnostics off says where the switch is,
        // instead of flashing a modal that immediately dismisses itself.
        if (!_ref.read(diagnosticsEnabledProvider)) {
          // The category title comes from the same string the Settings rail
          // shows, so the pointer cannot drift from the rail again.
          final l10n = L10N.of(context);
          showCruxInfoSnack(
            context,
            l10n.diagnosticsDisabledSnack(l10n.settingsGeneralSection),
          );
          return;
        }
        unawaited(AppDiagnosticsDialog.show(context));
      case NetcruxAction.zoomIn:
        // Step-zoom 1.25× about the viewport centre, the same anchor the
        // canvas's own `=` key uses. The pinch and wheel paths anchor on the
        // pointer instead (zoomAt in the gesture handler).
        _ref
            .activeTabContainerOrNull(context)
            ?.read(viewportTransformProvider.notifier)
            .zoomAboutCenter(1.25);
      case NetcruxAction.zoomOut:
        _ref
            .activeTabContainerOrNull(context)
            ?.read(viewportTransformProvider.notifier)
            .zoomAboutCenter(1 / 1.25);
      case NetcruxAction.saveSession:
        unawaited(_saveSession(context));
      case NetcruxAction.openSession:
        unawaited(_openSession(context));
      case NetcruxAction.showFanin:
        _dispatchTrace(context, TraceOverlayMode.fanin);
      case NetcruxAction.showFanout:
        _dispatchTrace(context, TraceOverlayMode.fanout);
      case NetcruxAction.exportPng:
        unawaited(_dispatchExport(context, NetcruxExportKind.png));
      case NetcruxAction.exportSvg:
        unawaited(_dispatchExport(context, NetcruxExportKind.svg));
      case NetcruxAction.exportJson:
        unawaited(_dispatchExport(context, NetcruxExportKind.json));
      case NetcruxAction.importFilelist:
        unawaited(_onImportFilelistPressed(context));
      // ── workspace lifecycle ──────────────────────────────────────────
      case NetcruxAction.newWorkspace:
        unawaited(_newWorkspace(context));
      case NetcruxAction.openWorkspace:
        unawaited(_openWorkspace());
      case NetcruxAction.saveWorkspaceAs:
        unawaited(_saveWorkspaceAs(context));
      case NetcruxAction.resetWorkspace:
        unawaited(_resetWorkspace(context));
      // Hosting is the Enterprise step, so Share goes through the Pro-action
      // gate: post-beta an insufficient tier sees the upgrade dialog and
      // records `tier.gate_hit {feature: collaboration}`, and an open-core
      // build says it requires NetCrux Pro. Join and Leave are free and
      // ungated — a guest without a licence is a full participant.
      case NetcruxAction.shareSession:
        if (_proActionAllowed(context, action)) {
          _ref.read(shareSessionOpenerProvider)(context);
        }
      case NetcruxAction.joinSession:
        _ref.read(joinSessionOpenerProvider)(context);
      case NetcruxAction.leaveSession:
        unawaited(
          _ref.read(schematicCollaborationServiceProvider).leaveSession(),
        );
      case NetcruxAction.nextTab:
        unawaited(_switchTabBy(1));
      case NetcruxAction.previousTab:
        unawaited(_switchTabBy(-1));
      case NetcruxAction.toggleTheme:
        toggleThemeBrightness(
          _ref.read(cruxColorThemeProvider.notifier),
          _ref.read(cruxColorThemeProvider),
        );
      case NetcruxAction.openDocumentation:
        unawaited(netcruxLaunchUrl(Uri.parse(HelpUrls.docs)));
    }
  }

  // ── workspace lifecycle ────────────────────────────────────────────────

  /// Discards the current workspace for an empty one, confirming first —
  /// it closes every open tab.
  Future<void> _newWorkspace(BuildContext context) async {
    final l10n = L10N.of(context);
    final confirmed = await _confirmDiscardWorkspace(
      context,
      title: l10n.workspaceResetWorkspaceTitle,
      body: l10n.workspaceResetWorkspaceConfirm,
    );
    if (!confirmed) return;
    await _ref.read(netcruxWorkspaceProvider.notifier).resetWorkspace();
    // New Workspace and Reset Workspace call the *same* notifier method, so
    // the two counters live here rather than on the notifier: emitting from
    // `resetWorkspace` would collapse "I started something new" and "I threw
    // this away" into one number, and they are different answers to different
    // questions. Emitted after the await so a cancelled confirm counts nothing.
    _ref
        .read(telemetryServiceProvider)
        .record(TelemetryEvent('workspace.created'));
  }

  /// Opens a saved `.netcrux-workspace` document. Delegates to the screen's
  /// flow so the menu and the empty-canvas button share one implementation.
  Future<void> _openWorkspace() => _openWorkspaceFlow();

  /// Writes the whole workspace — every tab and pane — to a chosen path.
  Future<void> _saveWorkspaceAs(BuildContext context) async {
    final l10n = L10N.of(context);
    final service = _ref.read(fileOpenServiceProvider);
    final String? path;
    try {
      path = await service.pickWorkspaceSaveAs(
        dialogTitle: l10n.workspaceSaveWorkspaceAsTitle,
      );
    } on Object catch (e) {
      if (!context.mounted) return;
      showCruxErrorSnack(context, l10n.filePickerFailed('$e'));
      return;
    }
    if (path == null) return;
    await _ref.read(netcruxWorkspaceProvider.notifier).saveAs(path);
  }

  /// Closes every open tab and returns to the empty canvas, confirming
  /// first — this is destructive and has no undo.
  Future<void> _resetWorkspace(BuildContext context) async {
    final l10n = L10N.of(context);
    final confirmed = await _confirmDiscardWorkspace(
      context,
      title: l10n.workspaceResetWorkspaceTitle,
      body: l10n.workspaceResetWorkspaceConfirm,
    );
    if (!confirmed) return;
    await _ref.read(netcruxWorkspaceProvider.notifier).resetWorkspace();
    _ref
        .read(telemetryServiceProvider)
        .record(TelemetryEvent('workspace.reset'));
  }

  Future<bool> _confirmDiscardWorkspace(
    BuildContext context, {
    required String title,
    required String body,
  }) {
    final l10n = L10N.of(context);
    // The suite-standard destructive confirm (error-colored, verb-labeled)
    // — this was previously a hand-rolled dialog with a generic "OK".
    return confirmCruxDestructiveAction(
      context,
      title: title,
      body: body,
      confirmLabel: l10n.workspaceResetConfirmButton,
      cancelLabel: l10n.commonCancel,
    );
  }

  /// Activates the tab [delta] positions away in the active pane, wrapping
  /// at both ends. Inert with fewer than two tabs (the descriptor greys the
  /// menu items there, so this is belt-and-braces for the keyboard path).
  Future<void> _switchTabBy(int delta) async {
    final ws = _ref.read(netcruxWorkspaceProvider).value;
    if (ws == null) return;
    final paneTabs = ws.tabsForPane(ws.activePaneId);
    if (paneTabs.length < 2) return;
    final notifier = _ref.read(netcruxWorkspaceProvider.notifier);
    final activeTabId = ws.activeTabId;
    final currentIdx = activeTabId == null
        ? -1
        : paneTabs.indexWhere((t) => t.id == activeTabId);
    if (currentIdx < 0) {
      await notifier.setActiveTab(paneTabs.first.id);
      return;
    }
    final next = (currentIdx + delta) % paneTabs.length;
    await notifier.setActiveTab(
      paneTabs[next < 0 ? next + paneTabs.length : next].id,
    );
  }

  Future<void> _openSearch(BuildContext context) async {
    // The search dialog reads and applies per-tab state (hierarchy,
    // selection, trace overlay). Resolve the active tab's container so
    // it operates on the active tab rather than the empty root scope.
    final container = _ref.activeTabContainerOrNull(context);
    if (container == null) return;
    await SearchDialog.show(context, container: container);
  }

  // ---------------------------------------------------------------------------
  // Split-pane actions
  // ---------------------------------------------------------------------------

  Future<void> _onSplitPaneRight() async {
    await _ref.read(netcruxWorkspaceProvider.notifier).splitPaneRight();
  }

  Future<void> _onClosePane() async {
    final ws = _ref.read(netcruxWorkspaceProvider).value;
    if (ws == null || ws.panes.length < 2) return;
    await _ref
        .read(netcruxWorkspaceProvider.notifier)
        .closePane(ws.activePaneId);
  }

  Future<void> _onFocusOtherPane() async {
    await _ref.read(netcruxWorkspaceProvider.notifier).focusOtherPane();
  }

  Future<void> _onMoveTabToOtherPane() async {
    final ws = _ref.read(netcruxWorkspaceProvider).value;
    if (ws == null || ws.panes.length < 2) return;
    final activeTabId = ws.activeTabId;
    if (activeTabId == null) return;
    final otherPaneId = ws.panes.firstWhere((p) => p.id != ws.activePaneId).id;
    await _ref
        .read(netcruxWorkspaceProvider.notifier)
        .moveTabToPane(activeTabId, otherPaneId);
  }

  /// Toggles the docked cross-probe side-panel.
  ///
  /// The panel is a right-dock tab (`NetcruxRightDock` lists it while
  /// `crossProbeVisibleProvider` is set), so turning it on reveals the tab —
  /// the same reveal path the analysis-dock openers use.
  void _onToggleCrossProbePanel() {
    final notifier = _ref.read(crossProbeVisibleProvider.notifier);
    final willShow = !_ref.read(crossProbeVisibleProvider);
    notifier.toggle();
    // Reveal, dock-style: turning the feature on both opens the right
    // region and brings the Cross-Probe tab frontmost.
    if (willShow) {
      _ref.read(rightDockTabProvider.notifier).reveal(kRightDockTabCrossProbe);
    }
  }

  Future<void> _onImportFilelistPressed(BuildContext context) async {
    final l10n = L10N.of(context);
    final service = _ref.read(fileOpenServiceProvider);
    final FileOpenResult result;
    try {
      result = await service.pickFilelist(
        dialogTitle: l10n.filePickerFilelistDialogTitle,
      );
    } on Object catch (e) {
      if (!context.mounted) return;
      showCruxErrorSnack(context, l10n.filePickerFailed('$e'));
      return;
    }
    if (result.isCancelled || !context.mounted) return;
    final filelistPath = result.paths.single;
    try {
      final project = await const FilelistReader().readAsProject(filelistPath);
      if (!context.mounted) return;
      await _ref
          .read(appSettingsProvider.notifier)
          .recordRecentProject(
            filelistPath,
          );
      if (!context.mounted) return;
      final displayName = p.basenameWithoutExtension(filelistPath);
      await _ref
          .read(netcruxWorkspaceProvider.notifier)
          .openTab(
            displayName: displayName,
            payload: NetcruxTabPayload(
              sourceFiles: project.sourceFiles,
              topModule: project.topModule,
            ),
          );
      if (!context.mounted) return;
      final container = _ref.activeTabContainerOrNull(context);
      container
          ?.read(currentProjectProvider.notifier)
          .setProject(project, source: NetcruxDesignSource.filelist);
    } on Object catch (e) {
      if (!context.mounted) return;
      showCruxErrorSnack(context, l10n.projectLoadFailed(e.toString()));
    }
  }

  /// The active tab canvas' current on-screen size, read straight from the
  /// per-tab canvas `RepaintBoundary` render object (the same key the PNG
  /// export uses). Always reflects the live viewport, unlike the size cached
  /// in [canvasFitTargetProvider], which the gesture handler only refreshes
  /// when it rebuilds. Null when the canvas isn't mounted / laid out yet, so
  /// the caller can fall back to the cached size.
  Size? _liveCanvasSize(ProviderContainer container) {
    final box = container
        .read(schematicCanvasKeyProvider)
        .currentContext
        ?.findRenderObject();
    if (box is RenderBox && box.hasSize && !box.size.isEmpty) {
      return box.size;
    }
    return null;
  }

  Future<void> _dispatchExport(
    BuildContext context,
    NetcruxExportKind kind,
  ) async {
    final container = _ref.activeTabContainerOrNull(context);
    if (container == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final l10n = L10N.of(context);
    final canvasKey = container.read(schematicCanvasKeyProvider);
    final controller = SchematicExportController(
      container: container,
      messenger: messenger,
      l10n: l10n,
      canvasKey: canvasKey,
    );
    switch (kind) {
      case NetcruxExportKind.png:
        await controller.exportPng();
      case NetcruxExportKind.svg:
        await controller.exportSvg();
      case NetcruxExportKind.json:
        await controller.exportJson();
    }
  }

  void _dispatchTrace(BuildContext context, TraceOverlayMode mode) {
    // The open-core single-step trace, the baseline the Pro cone-of-influence
    // conversion argument is measured against. Recorded on invocation
    // — ahead of both the active-tab lookup and the controller, each of which
    // no-ops on an empty selection or an empty canvas. The user asked for a
    // trace either way, and "asked and got nothing" is a usage signal we would
    // rather see than lose.
    //
    // `mode` is a Dart enum, so it goes through `telemetryEnumToken` — the
    // whole point of which is that a `String` can never take this path.
    _ref
        .read(telemetryServiceProvider)
        .record(
          TelemetryEvent(
            'trace.used',
            properties: <String, Object?>{'kind': telemetryEnumToken(mode)},
          ),
        );
    final container = _ref.activeTabContainerOrNull(context);
    if (container == null) return;
    final controller = TraceOverlayController.fromContainer(container);
    switch (mode) {
      case TraceOverlayMode.fanin:
        controller.showFanin();
      case TraceOverlayMode.fanout:
        controller.showFanout();
    }
  }

  Future<void> _saveSession(BuildContext context) async {
    final container = _ref.activeTabContainerOrNull(context);
    if (container == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final l10n = L10N.of(context);
    final controller = SessionController(
      container: container,
      messenger: messenger,
      l10n: l10n,
    );
    // Read before the await: `ref` is invalid across an async gap.
    final audit = _ref.read(cruxAuditRecorderProvider);
    final saved = await controller.saveAs();
    // Only on a real write. `saveAs` returns null for a cancelled picker AND
    // for a failed write, which are the two cases an audit line must not
    // claim — a line for a save that did not happen is the one an
    // investigation would trust.
    if (saved != null) {
      audit.record(
        NetCruxAuditKinds.sessionSaved,
        payload: <String, Object?>{'path': saved},
      );
    }
  }

  Future<void> _openSession(BuildContext context) async {
    final container = _ref.activeTabContainerOrNull(context);
    if (container == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final l10n = L10N.of(context);
    final controller = SessionController(
      container: container,
      messenger: messenger,
      l10n: l10n,
    );
    await controller.openPicker();
  }

  Future<void> _closeActiveTab() async {
    final ws = _ref.read(netcruxWorkspaceProvider).value;
    final id = ws?.activeTabId;
    if (id == null) return;
    await _ref.read(netcruxWorkspaceProvider.notifier).closeTab(id);
  }

  /// Whether [action] may run; see [allowProAction], which explains itself
  /// to the user when the answer is no.
  bool _proActionAllowed(BuildContext context, NetcruxAction action) =>
      allowProAction(context, _ref, action);

  /// Dispatches the Pro multi-step cone-of-influence trace from the
  /// active tab's selection through the open-core
  /// [coneOfInfluenceServiceProvider] extension point. Open-core resolves
  /// the provider to [NoopConeOfInfluenceService] (silent no-op); the
  /// Pro overlay registers a concrete implementation via
  /// `proOverrides`.
  ///
  /// Reads from the active tab's per-tab container so the cone is
  /// computed against the right scope under split-pane / multi-tab. The
  /// tier gate is applied by the caller via [_proActionAllowed]; this
  /// method runs only once activation is already permitted.
  Future<void> _dispatchConeOfInfluence(
    BuildContext context,
    ConeOfInfluenceMode mode,
  ) async {
    final container = _ref.activeTabContainerOrNull(context);
    if (container == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final l10n = L10N.of(context);
    // Route through the shared controller so this palette / menu-bar path
    // gets the exact same painting, fit-to-cone, and cell-count readout as
    // the schematic context-menu entries.
    final count = await ConeOfInfluenceController.fromContainer(
      container,
    ).run(mode);
    if (!context.mounted || count == null || count == 0) return;
    messenger.hideCurrentSnackBar();
    showCruxInfoSnack(context, l10n.coneOfInfluenceCellCount(count));
  }

  /// Dispatches the Pro X-trace causal-chain walk from the active
  /// tab's selection through the open-core [xTraceServiceProvider]
  /// extension point, then reveals the result panel showing it.
  ///
  /// Open-core resolves the provider to [NoopXTraceService] (silent empty
  /// result); the Pro overlay registers a concrete
  /// `ProXTraceService` via `proOverrides`. Routed through
  /// [XTraceController] so this palette / menu-bar path performs the exact
  /// same publish-and-paint as the Pro schematic context-menu entry, and
  /// reads the active tab's container so the walk runs against the right
  /// scope under split-pane / multi-tab.
  ///
  /// `simulationTime` stays `null`: NetCrux has no time cursor
  /// (`cursorTimeProvider` does not exist), so the Pro service runs
  /// pure-graph reachability over the driver cone and every step's value is
  /// null. That is a v2 gap in the *cursor*, not in waveform support —
  /// `ProWaveformSourceService` parses VCD and `queryNetTransitions` already
  /// returns x/z values for the activity heatmap.
  ///
  /// The panel is revealed only when the walk produced something. A walk
  /// that resolved no start would otherwise pop a panel open on its empty
  /// state, which reads as a failure the user did not cause.
  ///
  /// The tier gate is applied by the caller via [_proActionAllowed]; this
  /// method runs only once activation is already permitted.
  Future<void> _dispatchXTrace(BuildContext context) async {
    final container = _ref.activeTabContainerOrNull(context);
    if (container == null) return;
    // Read the panel notifiers up front: `ref` is invalid after an async gap
    // (`lifecycle_ref_use_test`), and the reveal below runs after the walk.
    final visible = _ref.read(xTracePanelVisibleProvider.notifier);
    final dockTab = _ref.read(rightDockTabProvider.notifier);
    final length = await XTraceController.fromContainer(container).run();
    if (length == null || length == 0) return;
    visible.set(visible: true);
    dockTab.reveal(kRightDockTabXTrace);
  }

  /// Toggles the X-trace result panel, revealing its dock region when it
  /// opens — [`AnalysisDockNotifier.toggle`]'s semantics, so a second
  /// invocation of `Show X-Trace Panel` closes it again.
  ///
  /// Open-core, and deliberately not tier-gated: the panel opens on its empty
  /// state in a build with no walker, which is exactly what
  /// `xTracePanelEmpty` is written to say. Closing this way leaves any result
  /// intact, so reopening restores the chain.
  void _onToggleXTracePanel() {
    final notifier = _ref.read(xTracePanelVisibleProvider.notifier);
    final willShow = !_ref.read(xTracePanelVisibleProvider);
    notifier.toggle();
    if (willShow) {
      _ref.read(rightDockTabProvider.notifier).reveal(kRightDockTabXTrace);
    }
  }
}
