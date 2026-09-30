// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:crux_shortcut_action/crux_shortcut_action.dart';
import 'package:flutter/widgets.dart';
import 'package:netcrux/core/license/netcrux_gated_feature.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

/// Every user-facing action in netcrux. Single source of truth for the
/// command palette, the desktop menu bar, the toolbar, and the keyboard
/// shortcut system.
///
/// Implements [CruxAction] so the cross-suite command palette
/// (`CommandPalette<NetcruxAction>`) and any future shared infrastructure
/// can reason about the action without depending on netcrux's specific
/// enum shape. Mirrors the WaveCrux `ShortcutAction` pattern.
enum NetcruxAction implements CruxAction {
  /// Open a `.netcrux` project file via file picker.
  openProject,

  /// Open one or more Verilog/VHDL source files into a new project.
  openSourceFiles,

  /// Open a pre-built Yosys JSON netlist, which renders without elaboration.
  /// The one open action the browser build offers.
  openNetlistJson,

  /// Close the currently open project.
  closeProject,

  /// Zoom the schematic canvas in.
  zoomIn,

  /// Zoom the schematic canvas out.
  zoomOut,

  /// Fit the entire schematic in the viewport.
  zoomFitAll,

  /// Toggle the left hierarchy tree panel.
  toggleHierarchyTree,

  /// Toggle the right inspector panel.
  toggleInspector,

  /// Toggle the bottom diagnostics panel.
  toggleDiagnosticsPanel,

  /// Open the design search dialog.
  openSearch,

  /// Open the command palette overlay.
  openCommandPalette,

  /// Open the settings screen.
  openSettings,

  /// Open the about box.
  openAbout,

  /// Jump to the top of the design hierarchy.
  jumpToTop,

  /// Pop out of the current scope (navigate to the parent scope).
  popOutScope,

  /// Show the fanin overlay for the current selection (drivers).
  showFanin,

  /// Show the fanout overlay for the current selection (loads).
  showFanout,

  /// Clear any active fanin/fanout overlay or selection.
  clearOverlay,

  /// Export the current schematic as PNG.
  exportPng,

  /// Export the current schematic as SVG.
  exportSvg,

  /// Export the current scope's Yosys JSON subset.
  exportJson,

  /// Save the current session as a `.netcrux` file.
  saveSession,

  /// Open a `.netcrux` session file.
  openSession,

  /// Import a Vivado-style `.f` filelist and open it as a new
  /// project.
  importFilelist,

  /// Split the active pane to the right (creates a second pane and
  /// moves the active tab into it).
  splitPaneRight,

  /// Close the active pane, merging its tabs into the surviving pane.
  closePane,

  /// Toggle focus between the two panes when split.
  focusOtherPane,

  /// Move the active tab to the non-active pane (command-palette
  /// equivalent of the drag-tab-to-other-pane gesture).
  moveTabToOtherPane,

  /// Show the CXP cross-probe panel (peers + event log).
  showCrossProbePanel,

  /// Show the multi-step cone-of-influence fanin overlay for the
  /// current selection. Pro feature — requires [LicenseTier.pro]
  /// (see [NetcruxActionRequiredTier.requiredTier]).
  showConeOfInfluenceFanin,

  /// Show the multi-step cone-of-influence fanout overlay for the
  /// current selection. Pro feature — see [showConeOfInfluenceFanin].
  showConeOfInfluenceFanout,

  /// Clear any active cone-of-influence overlay. Always available
  /// (clearing is never gated).
  clearConeOfInfluence,

  /// Compute the X-trace causal chain backward from the currently
  /// selected net at the current simulation time. Pro feature —
  /// requires [LicenseTier.pro] (see
  /// [NetcruxActionRequiredTier.requiredTier]).
  showXTrace,

  /// Add a bookmark on the currently selected schematic element.
  /// Pro feature — requires [LicenseTier.pro].
  addBookmark,

  /// Show / focus the Bookmarks panel. The panel exists only in the Pro
  /// overlay, so this carries the Pro tier; an open-core build refuses it
  /// with a "requires NetCrux Pro" notice.
  showBookmarksPanel,

  /// Add an annotation on the currently selected schematic element.
  /// Pro feature.
  addAnnotation,

  /// Show / focus the Annotations panel. The panel exists only in the Pro
  /// overlay, so this carries the Pro tier; an open-core build refuses it
  /// with a "requires NetCrux Pro" notice.
  showAnnotationsPanel,

  /// Show / focus the RTL source pane (Pro). Always discoverable; an
  /// open-core build refuses it with a "requires NetCrux Pro" notice,
  /// because only the Pro overlay mounts the pane.
  /// Pro feature — requires [LicenseTier.pro].
  showSourcePane,

  /// Open the source file defining the currently selected schematic
  /// element in the RTL source pane (Pro). The dispatch reads the
  /// active selection from the active tab and resolves it through
  /// [SourcePaneService]. Pro feature.
  openSourceForElement,

  /// Close the RTL source pane. Always available (clearing /
  /// dismissing is never gated).
  closeSourcePane,

  /// Show / focus the X-trace result panel. Always available so
  /// users can dismiss a stale panel without an active license; the
  /// panel itself is empty under the open-core no-op service.
  showXTracePanel,

  /// Clear any active X-trace result. Open-core (clearing is never
  /// gated).
  clearXTrace,

  /// Show / focus the Netlist Diff View pane (Pro). Always
  /// discoverable; an open-core build refuses it with a "requires
  /// NetCrux Pro" notice, because only the Pro overlay mounts the pane.
  /// Pro feature — requires [LicenseTier.pro].
  showDiffPane,

  /// Load a comparison-side netlist via the platform file picker.
  /// Pro feature.
  loadComparisonNetlist,

  /// Clear any active comparison netlist and dismiss the diff
  /// overlay. Open-core tier, like every other clear / dismiss action:
  /// the dispatcher never tier-gates a clear, and open-core resolves the
  /// opener to a no-op, so gating it would badge an action that cannot
  /// do anything a Pro licence unlocks.
  clearComparisonNetlist,

  /// Jump the diff pane selection to the next [ElementChange] in
  /// the active comparison. Pro feature.
  navigateNextDiff,

  /// Jump the diff pane selection to the previous [ElementChange]
  /// in the active comparison. Pro feature.
  navigatePrevDiff,

  /// Open the Custom Cell Symbol manager screen, where users can
  /// browse, create, edit, import, and export per-module-type
  /// symbol overrides. Pro feature — requires [LicenseTier.pro]
  /// (see [NetcruxActionRequiredTier.requiredTier]).
  openSymbolManager,

  /// Open the Symbol Editor pre-loaded with the contents of an SVG
  /// file chosen via the platform file picker. Pro feature.
  importSymbolFromSvg,

  /// Context-aware: open the Symbol Editor for the right-clicked
  /// cell's `moduleType`. Creates a new symbol if none exists yet,
  /// otherwise edits the existing binding. Pro feature.
  editSymbolForCurrentInstance,

  /// Remove the custom symbol bound to the right-clicked cell's
  /// `moduleType` so the schematic falls back to the built-in
  /// rectangular rendering. Pro feature.
  removeSymbolForCurrentInstance,

  /// Show / focus the FSM Bubble Diagram pane (Pro). Always
  /// discoverable; an open-core build refuses it with a "requires
  /// NetCrux Pro" notice, because only the Pro overlay mounts the pane.
  /// Pro feature — requires [LicenseTier.pro].
  showFsmBubbleDiagram,

  /// Force structural FSM detection on the currently selected (or
  /// context-menu-targeted) register, skipping the detector's
  /// structural-signature filter. Pro feature.
  detectFsmForCurrentRegister,

  /// Run full-design FSM detection and open the detection-results
  /// dialog. Pro feature.
  runFsmDetectionAcrossDesign,

  /// Dismiss the FSM bubble diagram pane (clears the focused FSM).
  /// Always available — clearing is never gated.
  clearFsmSelection,

  /// Show / focus the CDC analysis pane (Pro). Always discoverable; an
  /// open-core build refuses it with a "requires NetCrux Pro" notice,
  /// because only the Pro overlay mounts the pane.
  /// Pro feature — requires [LicenseTier.pro].
  showCdcAnalysisPane,

  /// Run full-design CDC analysis and open the panel with the result.
  /// Pro feature.
  runCdcAnalysis,

  /// Scope the CDC panel to crossings involving the right-clicked (or
  /// command-palette dispatched) signal. Pro feature.
  showCdcCrossingForSelectedSignal,

  /// Clear the CDC pane's focused crossing + domain. Always available
  /// — clearing is never gated.
  clearCdcAnalysisSelection,

  /// Show / focus the Reset Domain analysis pane (Pro). Always
  /// discoverable; an open-core build refuses it with a "requires
  /// NetCrux Pro" notice, because only the Pro overlay mounts the pane.
  /// Pro feature — requires [LicenseTier.pro].
  showResetDomainAnalysisPane,

  /// Run full-design reset domain analysis and open the panel with
  /// the result. Pro feature.
  runResetDomainAnalysis,

  /// Scope the Reset Domain panel to crossings involving the
  /// right-clicked (or command-palette dispatched) signal. Pro
  /// feature.
  showResetCrossingForSelectedSignal,

  /// Clear the Reset Domain pane's focused crossing + domain. Always
  /// available — clearing is never gated.
  clearResetAnalysisSelection,

  /// Open the platform file picker and load a VCD/FST/GHW waveform
  /// into the active [WaveformSourceService]. Pro feature — requires
  /// [LicenseTier.pro].
  openWaveformFile,

  /// Unload the currently-loaded waveform source. Pro feature.
  closeWaveformFile,

  /// Show / focus the Switching Activity Heatmap pane (Pro). Always
  /// discoverable; an open-core build refuses it with a "requires
  /// NetCrux Pro" notice, because only the Pro overlay mounts the pane.
  /// Pro feature.
  showActivityHeatmap,

  /// Run full-design switching activity analysis using the active
  /// per-tab time range + color scheme, route the result into the
  /// per-tab state notifier, and open the panel. Pro feature.
  runActivityAnalysis,

  /// Clear the per-edge activity color override map (the schematic
  /// painter falls back to default wire color). Does not clear the
  /// underlying analysis result. Always available — clearing is
  /// never gated.
  clearActivityColoring,

  /// Open the activity color-scheme picker (Pro). Pro feature.
  configureActivityScheme,

  /// Run a manual check against the public version manifest and report the
  /// outcome. Always runs, regardless of the Settings → General
  /// "Automatically check for updates" toggle. Open Core — every user is
  /// entitled to know a newer build exists.
  checkForUpdates,

  /// Open the beta issue reporter: collect diagnostics, let the user review
  /// and opt out of each category, then open a pre-filled GitHub new-issue
  /// page. Open Core, and deliberately never tier-gated — a user who cannot
  /// report a bug is a user whose bug never gets fixed.
  submitIssue,

  /// Reveal the per-tab Tab Diagnostics surface (the bottom dock's
  /// Diagnostics tab), opening the bottom region if it is hidden.
  ///
  /// WaveCrux's Cmd/Ctrl+Shift+I "Tab Diagnostics" opener, mirrored. Unlike [toggleDiagnosticsPanel] this
  /// always *reveals* (never hides), so the shortcut is idempotent — the
  /// same open-only semantics as WaveCrux's drawer opener.
  openTabDiagnostics,

  /// Open the process-wide App Diagnostics dialog.
  ///
  /// NetCrux had only the per-tab diagnostics drawer, so nothing answered
  /// "what is the state of the app?" — the question a bug report starts with.
  /// The dialog renders the same privacy-scrubbed session snapshot the issue
  /// reporter sends, so the two can never disagree. Open Core: a support
  /// report is free in every build.
  openAppDiagnostics,

  /// Open the online NetCrux documentation (docs.netcrux.app) in the user's
  /// browser. Open Core and never tier-gated — every suite Help menu leads
  /// with it.
  openDocumentation,

  // ── workspace lifecycle ───────────────────────────────────────────────────
  // NetCrux already had the full multi-tab / multi-pane workspace document;
  // what it lacked was any menu path to manage it. These five mirror the
  // WaveCrux and LintCrux File menus one-for-one.
  /// Discard the current workspace and start an empty one.
  newWorkspace,

  /// Open a previously saved `.netcrux-workspace` document.
  openWorkspace,

  /// Save the whole workspace (every tab and pane) to a chosen path.
  saveWorkspaceAs,

  /// Close every open tab and return to the empty-canvas state. Destructive,
  /// so it confirms first.
  resetWorkspace,

  /// Activate the next tab in the active pane, wrapping at the end.
  nextTab,

  /// Activate the previous tab in the active pane, wrapping at the start.
  previousTab,

  /// Close the active workspace tab. Cmd/Ctrl+W — the universal "close"
  /// convention, matching WaveCrux and LintCrux (suite keyboard-parity
  /// pass). NetCrux tabs *are* projects, so this closes the active
  /// project's tab; [closeProject] keeps its explicit label and moves to
  /// Cmd/Ctrl+Shift+W.
  closeTab,

  /// Flip the app between the light and dark themes.
  toggleTheme,

  /// Quit the application.
  quit;

  @override
  String get id => 'netcrux.$name';

  @override
  ActionCategory get category {
    switch (this) {
      case NetcruxAction.newWorkspace:
      case NetcruxAction.openProject:
      case NetcruxAction.openSourceFiles:
      case NetcruxAction.openNetlistJson:
      case NetcruxAction.openWorkspace:
      case NetcruxAction.openSession:
      case NetcruxAction.importFilelist:
      // Loading and unloading a waveform / comparison netlist is opening and
      // closing a file, so both halves of each pair live in File rather than
      // split between Tools and View.
      case NetcruxAction.openWaveformFile:
      case NetcruxAction.closeWaveformFile:
      case NetcruxAction.loadComparisonNetlist:
      case NetcruxAction.clearComparisonNetlist:
      case NetcruxAction.saveSession:
      case NetcruxAction.saveWorkspaceAs:
      case NetcruxAction.exportPng:
      case NetcruxAction.exportSvg:
      case NetcruxAction.exportJson:
      case NetcruxAction.closeTab:
      case NetcruxAction.closeProject:
      case NetcruxAction.resetWorkspace:
        return ActionCategory.file;
      // Settings and Quit live in the "App" category: on macOS the shared
      // menu bar renders them in the system application menu, and on
      // Windows / Linux it folds them into the bottom of the File menu.
      // Settings used to sit in Tools, which is where Windows and Linux
      // users actually saw it — not where any other suite product puts it.
      case NetcruxAction.openSettings:
      case NetcruxAction.quit:
        return ActionCategory.app;
      case NetcruxAction.zoomIn:
      case NetcruxAction.zoomOut:
      case NetcruxAction.zoomFitAll:
      case NetcruxAction.openCommandPalette:
      case NetcruxAction.toggleHierarchyTree:
      case NetcruxAction.toggleInspector:
      // Showing a panel is a View concern; *creating* the thing the panel
      // lists (Add Bookmark / Add Annotation) stays in Tools.
      case NetcruxAction.showBookmarksPanel:
      case NetcruxAction.showAnnotationsPanel:
      case NetcruxAction.splitPaneRight:
      case NetcruxAction.closePane:
      case NetcruxAction.focusOtherPane:
      case NetcruxAction.moveTabToOtherPane:
      case NetcruxAction.nextTab:
      case NetcruxAction.previousTab:
      case NetcruxAction.showCrossProbePanel:
      case NetcruxAction.showSourcePane:
      case NetcruxAction.closeSourcePane:
      case NetcruxAction.showDiffPane:
      case NetcruxAction.showFsmBubbleDiagram:
      case NetcruxAction.clearFsmSelection:
      case NetcruxAction.showCdcAnalysisPane:
      case NetcruxAction.clearCdcAnalysisSelection:
      case NetcruxAction.showResetDomainAnalysisPane:
      case NetcruxAction.clearResetAnalysisSelection:
      case NetcruxAction.showActivityHeatmap:
      case NetcruxAction.clearActivityColoring:
      case NetcruxAction.toggleTheme:
        return ActionCategory.view;
      case NetcruxAction.jumpToTop:
      case NetcruxAction.popOutScope:
      case NetcruxAction.showFanin:
      case NetcruxAction.showFanout:
      case NetcruxAction.clearOverlay:
      case NetcruxAction.showConeOfInfluenceFanin:
      case NetcruxAction.showConeOfInfluenceFanout:
      case NetcruxAction.clearConeOfInfluence:
      case NetcruxAction.showXTrace:
      case NetcruxAction.showXTracePanel:
      case NetcruxAction.clearXTrace:
      case NetcruxAction.openSourceForElement:
      case NetcruxAction.navigateNextDiff:
      case NetcruxAction.navigatePrevDiff:
        return ActionCategory.navigate;
      case NetcruxAction.addBookmark:
      case NetcruxAction.addAnnotation:
      case NetcruxAction.openSymbolManager:
      case NetcruxAction.importSymbolFromSvg:
      case NetcruxAction.editSymbolForCurrentInstance:
      case NetcruxAction.removeSymbolForCurrentInstance:
      case NetcruxAction.detectFsmForCurrentRegister:
      case NetcruxAction.runFsmDetectionAcrossDesign:
      case NetcruxAction.runCdcAnalysis:
      case NetcruxAction.showCdcCrossingForSelectedSignal:
      case NetcruxAction.runResetDomainAnalysis:
      case NetcruxAction.showResetCrossingForSelectedSignal:
      case NetcruxAction.runActivityAnalysis:
      case NetcruxAction.configureActivityScheme:
      // The diagnostics drawer is NetCrux's per-tab diagnostics surface, so
      // it belongs in Tools next to the analyses — the same place WaveCrux
      // and LintCrux put theirs — not in View with the layout toggles.
      case NetcruxAction.toggleDiagnosticsPanel:
      // …and the app-wide dialog closes Tools, matching WaveCrux, LintCrux
      // and SimCrux.
      case NetcruxAction.openTabDiagnostics:
      case NetcruxAction.openAppDiagnostics:
        return ActionCategory.tools;
      case NetcruxAction.openSearch:
        return ActionCategory.search;
      case NetcruxAction.openDocumentation:
      case NetcruxAction.openAbout:
      case NetcruxAction.checkForUpdates:
      case NetcruxAction.submitIssue:
        return ActionCategory.help;
    }
  }
}

/// Localized label extension on [NetcruxAction]. Lives alongside the enum
/// because labels are L10N-coupled — the cross-suite `CruxAction` interface
/// stays Flutter- and L10N-free.
extension NetcruxActionLabel on NetcruxAction {
  /// The localized display label for this action (menu, command palette,
  /// toolbar tooltip).
  String label(L10N l10n) {
    switch (this) {
      case NetcruxAction.openProject:
        return l10n.actionOpenProject;
      case NetcruxAction.openSourceFiles:
        return l10n.actionOpenSourceFiles;
      case NetcruxAction.openNetlistJson:
        return l10n.actionOpenNetlistJson;
      case NetcruxAction.closeProject:
        return l10n.actionCloseProject;
      case NetcruxAction.closeTab:
        return l10n.actionCloseTab;
      case NetcruxAction.zoomIn:
        return l10n.actionZoomIn;
      case NetcruxAction.zoomOut:
        return l10n.actionZoomOut;
      case NetcruxAction.zoomFitAll:
        return l10n.actionZoomFitAll;
      case NetcruxAction.toggleHierarchyTree:
        return l10n.actionToggleHierarchyTree;
      case NetcruxAction.toggleInspector:
        return l10n.actionToggleInspector;
      case NetcruxAction.toggleDiagnosticsPanel:
        return l10n.actionToggleDiagnosticsPanel;
      case NetcruxAction.openSearch:
        return l10n.actionOpenSearch;
      case NetcruxAction.openCommandPalette:
        return l10n.actionOpenCommandPalette;
      case NetcruxAction.openSettings:
        return l10n.actionOpenSettings;
      case NetcruxAction.openAbout:
        return l10n.actionOpenAbout;
      case NetcruxAction.jumpToTop:
        return l10n.actionJumpToTop;
      case NetcruxAction.popOutScope:
        return l10n.actionPopOutScope;
      case NetcruxAction.showFanin:
        return l10n.actionShowFanin;
      case NetcruxAction.showFanout:
        return l10n.actionShowFanout;
      case NetcruxAction.clearOverlay:
        return l10n.actionClearOverlay;
      case NetcruxAction.exportPng:
        return l10n.actionExportPng;
      case NetcruxAction.exportSvg:
        return l10n.actionExportSvg;
      case NetcruxAction.exportJson:
        return l10n.actionExportJson;
      case NetcruxAction.saveSession:
        return l10n.actionSaveSession;
      case NetcruxAction.openSession:
        return l10n.actionOpenSession;
      case NetcruxAction.importFilelist:
        return l10n.actionImportFilelist;
      case NetcruxAction.splitPaneRight:
        return l10n.actionSplitPaneRight;
      case NetcruxAction.closePane:
        return l10n.actionClosePane;
      case NetcruxAction.focusOtherPane:
        return l10n.actionFocusOtherPane;
      case NetcruxAction.moveTabToOtherPane:
        return l10n.actionMoveTabToOtherPane;
      case NetcruxAction.showCrossProbePanel:
        return l10n.actionShowCrossProbePanel;
      case NetcruxAction.showConeOfInfluenceFanin:
        return l10n.actionShowConeOfInfluenceFanin;
      case NetcruxAction.showConeOfInfluenceFanout:
        return l10n.actionShowConeOfInfluenceFanout;
      case NetcruxAction.clearConeOfInfluence:
        return l10n.actionClearConeOfInfluence;
      case NetcruxAction.showXTrace:
        return l10n.actionShowXTrace;
      case NetcruxAction.showXTracePanel:
        return l10n.actionShowXTracePanel;
      case NetcruxAction.clearXTrace:
        return l10n.actionClearXTrace;
      case NetcruxAction.addBookmark:
        return l10n.actionAddBookmark;
      case NetcruxAction.showBookmarksPanel:
        return l10n.actionShowBookmarksPanel;
      case NetcruxAction.addAnnotation:
        return l10n.actionAddAnnotation;
      case NetcruxAction.showAnnotationsPanel:
        return l10n.actionShowAnnotationsPanel;
      case NetcruxAction.showSourcePane:
        return l10n.actionShowSourcePane;
      case NetcruxAction.openSourceForElement:
        return l10n.actionOpenSourceForElement;
      case NetcruxAction.closeSourcePane:
        return l10n.actionCloseSourcePane;
      case NetcruxAction.showDiffPane:
        return l10n.actionShowDiffPane;
      case NetcruxAction.loadComparisonNetlist:
        return l10n.actionLoadComparisonNetlist;
      case NetcruxAction.clearComparisonNetlist:
        return l10n.actionClearComparisonNetlist;
      case NetcruxAction.navigateNextDiff:
        return l10n.actionNavigateNextDiff;
      case NetcruxAction.navigatePrevDiff:
        return l10n.actionNavigatePrevDiff;
      case NetcruxAction.openSymbolManager:
        return l10n.actionOpenSymbolManager;
      case NetcruxAction.importSymbolFromSvg:
        return l10n.actionImportSymbolFromSvg;
      case NetcruxAction.editSymbolForCurrentInstance:
        return l10n.actionEditSymbolForCurrentInstance;
      case NetcruxAction.removeSymbolForCurrentInstance:
        return l10n.actionRemoveSymbolForCurrentInstance;
      case NetcruxAction.showFsmBubbleDiagram:
        return l10n.actionShowFsmBubbleDiagram;
      case NetcruxAction.detectFsmForCurrentRegister:
        return l10n.actionDetectFsmForCurrentRegister;
      case NetcruxAction.runFsmDetectionAcrossDesign:
        return l10n.actionRunFsmDetectionAcrossDesign;
      case NetcruxAction.clearFsmSelection:
        return l10n.actionClearFsmSelection;
      case NetcruxAction.showCdcAnalysisPane:
        return l10n.actionShowCdcAnalysisPane;
      case NetcruxAction.runCdcAnalysis:
        return l10n.actionRunCdcAnalysis;
      case NetcruxAction.showCdcCrossingForSelectedSignal:
        return l10n.actionShowCdcCrossingForSelectedSignal;
      case NetcruxAction.clearCdcAnalysisSelection:
        return l10n.actionClearCdcAnalysisSelection;
      case NetcruxAction.showResetDomainAnalysisPane:
        return l10n.actionShowResetDomainAnalysisPane;
      case NetcruxAction.runResetDomainAnalysis:
        return l10n.actionRunResetDomainAnalysis;
      case NetcruxAction.showResetCrossingForSelectedSignal:
        return l10n.actionShowResetCrossingForSelectedSignal;
      case NetcruxAction.clearResetAnalysisSelection:
        return l10n.actionClearResetAnalysisSelection;
      case NetcruxAction.openWaveformFile:
        return l10n.actionOpenWaveformFile;
      case NetcruxAction.closeWaveformFile:
        return l10n.actionCloseWaveformFile;
      case NetcruxAction.showActivityHeatmap:
        return l10n.actionShowActivityHeatmap;
      case NetcruxAction.runActivityAnalysis:
        return l10n.actionRunActivityAnalysis;
      case NetcruxAction.clearActivityColoring:
        return l10n.actionClearActivityColoring;
      case NetcruxAction.configureActivityScheme:
        return l10n.actionConfigureActivityScheme;
      case NetcruxAction.checkForUpdates:
        return l10n.actionCheckForUpdates;
      case NetcruxAction.submitIssue:
        return l10n.actionSubmitIssue;
      case NetcruxAction.openTabDiagnostics:
        return l10n.actionOpenTabDiagnostics;
      case NetcruxAction.openAppDiagnostics:
        return l10n.actionOpenAppDiagnostics;
      case NetcruxAction.openDocumentation:
        return l10n.actionOpenDocumentation;
      case NetcruxAction.newWorkspace:
        return l10n.actionNewWorkspace;
      case NetcruxAction.openWorkspace:
        return l10n.actionOpenWorkspace;
      case NetcruxAction.saveWorkspaceAs:
        return l10n.actionSaveWorkspaceAs;
      case NetcruxAction.resetWorkspace:
        return l10n.actionResetWorkspace;
      case NetcruxAction.nextTab:
        return l10n.actionNextTab;
      case NetcruxAction.previousTab:
        return l10n.actionPreviousTab;
      case NetcruxAction.toggleTheme:
        return l10n.actionToggleTheme;
      case NetcruxAction.quit:
        return l10n.actionQuit;
    }
  }
}

/// Maps a [NetcruxAction] to the minimum [LicenseTier] required to
/// activate it. Lives alongside the enum because tier is a Pro/Enterprise
/// concept and the cross-suite `CruxAction` interface deliberately stays
/// tier-agnostic.
///
/// Actions default to [LicenseTier.openCore] (no badge). Only the small
/// set of Pro/Enterprise actions returns a higher tier — the command
/// palette / menu bar renders a [FeatureTierBadge] beside the label when the
/// required tier is `pro` or `enterprise`.
///
/// Convention: when adding a new Pro/Enterprise action, *also* add the
/// `requiredTier` mapping below in the same commit so the badge renders
/// from day one.
extension NetcruxActionRequiredTier on NetcruxAction {
  /// Minimum [LicenseTier] needed to activate this action.
  LicenseTier get requiredTier {
    switch (this) {
      case NetcruxAction.showConeOfInfluenceFanin:
      case NetcruxAction.showConeOfInfluenceFanout:
      case NetcruxAction.showXTrace:
      case NetcruxAction.addBookmark:
      // The panels exist only in the Pro overlay; open core has nothing to
      // show, so they carry the tier and its badge like the actions that fill
      // them.
      case NetcruxAction.showBookmarksPanel:
      case NetcruxAction.showAnnotationsPanel:
      case NetcruxAction.addAnnotation:
      case NetcruxAction.showSourcePane:
      case NetcruxAction.openSourceForElement:
      case NetcruxAction.showDiffPane:
      case NetcruxAction.loadComparisonNetlist:
      case NetcruxAction.navigateNextDiff:
      case NetcruxAction.navigatePrevDiff:
      case NetcruxAction.openSymbolManager:
      case NetcruxAction.importSymbolFromSvg:
      case NetcruxAction.editSymbolForCurrentInstance:
      case NetcruxAction.removeSymbolForCurrentInstance:
      case NetcruxAction.showFsmBubbleDiagram:
      case NetcruxAction.detectFsmForCurrentRegister:
      case NetcruxAction.runFsmDetectionAcrossDesign:
      case NetcruxAction.showCdcAnalysisPane:
      case NetcruxAction.runCdcAnalysis:
      case NetcruxAction.showCdcCrossingForSelectedSignal:
      case NetcruxAction.showResetDomainAnalysisPane:
      case NetcruxAction.runResetDomainAnalysis:
      case NetcruxAction.showResetCrossingForSelectedSignal:
      case NetcruxAction.openWaveformFile:
      case NetcruxAction.closeWaveformFile:
      case NetcruxAction.showActivityHeatmap:
      case NetcruxAction.runActivityAnalysis:
      case NetcruxAction.configureActivityScheme:
        return LicenseTier.pro;
      case NetcruxAction.openProject:
      case NetcruxAction.openSourceFiles:
      case NetcruxAction.openNetlistJson:
      case NetcruxAction.closeProject:
      case NetcruxAction.closeTab:
      // Workspace lifecycle, tab navigation, theme, and the docs link are
      // all Open Core: they operate on the workspace document and the
      // shell, neither of which is a paid capability.
      case NetcruxAction.newWorkspace:
      case NetcruxAction.openWorkspace:
      case NetcruxAction.saveWorkspaceAs:
      case NetcruxAction.resetWorkspace:
      case NetcruxAction.nextTab:
      case NetcruxAction.previousTab:
      case NetcruxAction.toggleTheme:
      case NetcruxAction.openDocumentation:
      case NetcruxAction.zoomIn:
      case NetcruxAction.zoomOut:
      case NetcruxAction.zoomFitAll:
      case NetcruxAction.toggleHierarchyTree:
      case NetcruxAction.toggleInspector:
      case NetcruxAction.toggleDiagnosticsPanel:
      case NetcruxAction.openSearch:
      case NetcruxAction.openCommandPalette:
      case NetcruxAction.openSettings:
      case NetcruxAction.openAbout:
      case NetcruxAction.jumpToTop:
      case NetcruxAction.popOutScope:
      case NetcruxAction.showFanin:
      case NetcruxAction.showFanout:
      case NetcruxAction.clearOverlay:
      case NetcruxAction.exportPng:
      case NetcruxAction.exportSvg:
      case NetcruxAction.exportJson:
      case NetcruxAction.saveSession:
      case NetcruxAction.openSession:
      case NetcruxAction.importFilelist:
      case NetcruxAction.splitPaneRight:
      case NetcruxAction.closePane:
      case NetcruxAction.focusOtherPane:
      case NetcruxAction.moveTabToOtherPane:
      case NetcruxAction.showCrossProbePanel:
      case NetcruxAction.clearConeOfInfluence:
      case NetcruxAction.showXTracePanel:
      case NetcruxAction.clearXTrace:
      case NetcruxAction.closeSourcePane:
      case NetcruxAction.clearComparisonNetlist:
      case NetcruxAction.clearFsmSelection:
      case NetcruxAction.clearCdcAnalysisSelection:
      case NetcruxAction.clearResetAnalysisSelection:
      case NetcruxAction.clearActivityColoring:
      case NetcruxAction.checkForUpdates:
      case NetcruxAction.submitIssue:
      case NetcruxAction.openTabDiagnostics:
      case NetcruxAction.openAppDiagnostics:
      case NetcruxAction.quit:
        return LicenseTier.openCore;
    }
  }
}

/// Maps a [NetcruxAction] to the [NetcruxGatedFeature] a gate denial reports
/// as `tier.gate_hit {feature}`, or `null` for actions no
/// gate can deny.
///
/// Lives beside [NetcruxActionRequiredTier] on purpose: the two switches are
/// one decision seen twice — an action that needs a tier is exactly an action
/// whose denial has something to report — and a test asserts they agree, so a
/// new Pro action that gets a `requiredTier` and no feature id (or the reverse)
/// fails the build rather than emitting a gate hit nobody can attribute.
///
/// The mapping is many-to-one by design: fanin and fanout are one purchase
/// decision, and so are the three CDC entry points. See [NetcruxGatedFeature]
/// for why the granularity is the priced feature rather than the menu item.
extension NetcruxActionGatedFeature on NetcruxAction {
  /// The closed-vocabulary feature id reported when this action is denied,
  /// or `null` when [NetcruxActionRequiredTier.requiredTier] is
  /// [LicenseTier.openCore] and no denial is possible.
  NetcruxGatedFeature? get gatedFeature {
    switch (this) {
      case NetcruxAction.showConeOfInfluenceFanin:
      case NetcruxAction.showConeOfInfluenceFanout:
        return NetcruxGatedFeature.coi;
      case NetcruxAction.showXTrace:
        return NetcruxGatedFeature.xTrace;
      case NetcruxAction.addBookmark:
      case NetcruxAction.showBookmarksPanel:
        return NetcruxGatedFeature.bookmark;
      case NetcruxAction.addAnnotation:
      case NetcruxAction.showAnnotationsPanel:
        return NetcruxGatedFeature.annotation;
      case NetcruxAction.showSourcePane:
      case NetcruxAction.openSourceForElement:
        return NetcruxGatedFeature.sourcePane;
      case NetcruxAction.showDiffPane:
      case NetcruxAction.loadComparisonNetlist:
      case NetcruxAction.navigateNextDiff:
      case NetcruxAction.navigatePrevDiff:
        return NetcruxGatedFeature.diff;
      case NetcruxAction.openSymbolManager:
      case NetcruxAction.importSymbolFromSvg:
      case NetcruxAction.editSymbolForCurrentInstance:
      case NetcruxAction.removeSymbolForCurrentInstance:
        return NetcruxGatedFeature.symbol;
      case NetcruxAction.showFsmBubbleDiagram:
      case NetcruxAction.detectFsmForCurrentRegister:
      case NetcruxAction.runFsmDetectionAcrossDesign:
        return NetcruxGatedFeature.fsm;
      case NetcruxAction.showCdcAnalysisPane:
      case NetcruxAction.runCdcAnalysis:
      case NetcruxAction.showCdcCrossingForSelectedSignal:
        return NetcruxGatedFeature.cdc;
      case NetcruxAction.showResetDomainAnalysisPane:
      case NetcruxAction.runResetDomainAnalysis:
      case NetcruxAction.showResetCrossingForSelectedSignal:
        return NetcruxGatedFeature.reset;
      case NetcruxAction.openWaveformFile:
      case NetcruxAction.closeWaveformFile:
        return NetcruxGatedFeature.waveform;
      case NetcruxAction.showActivityHeatmap:
      case NetcruxAction.runActivityAnalysis:
      case NetcruxAction.configureActivityScheme:
        return NetcruxGatedFeature.activity;
      // Open-core actions. Their gate admits every tier, so no denial — and no
      // feature id — can ever be produced for them.
      case NetcruxAction.openProject:
      case NetcruxAction.openSourceFiles:
      case NetcruxAction.openNetlistJson:
      case NetcruxAction.closeProject:
      case NetcruxAction.closeTab:
      case NetcruxAction.newWorkspace:
      case NetcruxAction.openWorkspace:
      case NetcruxAction.saveWorkspaceAs:
      case NetcruxAction.resetWorkspace:
      case NetcruxAction.nextTab:
      case NetcruxAction.previousTab:
      case NetcruxAction.toggleTheme:
      case NetcruxAction.openDocumentation:
      case NetcruxAction.zoomIn:
      case NetcruxAction.zoomOut:
      case NetcruxAction.zoomFitAll:
      case NetcruxAction.toggleHierarchyTree:
      case NetcruxAction.toggleInspector:
      case NetcruxAction.toggleDiagnosticsPanel:
      case NetcruxAction.openSearch:
      case NetcruxAction.openCommandPalette:
      case NetcruxAction.openSettings:
      case NetcruxAction.openAbout:
      case NetcruxAction.jumpToTop:
      case NetcruxAction.popOutScope:
      case NetcruxAction.showFanin:
      case NetcruxAction.showFanout:
      case NetcruxAction.clearOverlay:
      case NetcruxAction.exportPng:
      case NetcruxAction.exportSvg:
      case NetcruxAction.exportJson:
      case NetcruxAction.saveSession:
      case NetcruxAction.openSession:
      case NetcruxAction.importFilelist:
      case NetcruxAction.splitPaneRight:
      case NetcruxAction.closePane:
      case NetcruxAction.focusOtherPane:
      case NetcruxAction.moveTabToOtherPane:
      case NetcruxAction.showCrossProbePanel:
      case NetcruxAction.clearConeOfInfluence:
      case NetcruxAction.showXTracePanel:
      case NetcruxAction.clearXTrace:
      case NetcruxAction.closeSourcePane:
      case NetcruxAction.clearComparisonNetlist:
      case NetcruxAction.clearFsmSelection:
      case NetcruxAction.clearCdcAnalysisSelection:
      case NetcruxAction.clearResetAnalysisSelection:
      case NetcruxAction.clearActivityColoring:
      case NetcruxAction.checkForUpdates:
      case NetcruxAction.submitIssue:
      case NetcruxAction.openTabDiagnostics:
      case NetcruxAction.openAppDiagnostics:
      case NetcruxAction.quit:
        return null;
    }
  }
}

/// Flutter [Intent] subclass used to dispatch a [NetcruxAction] through
/// Flutter's `Shortcuts` / `Actions` machinery. Each product has its own
/// Intent subtype so `Actions.maybeInvoke<NetcruxActionIntent>` keeps
/// dispatch type-safe.
class NetcruxActionIntent extends Intent {
  /// Wraps [action] for dispatch through `Actions.invoke`.
  const NetcruxActionIntent(this.action);

  /// The user-facing action to fire.
  final NetcruxAction action;
}
