// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_menu_bar/crux_menu_bar.dart';
import 'package:netcrux/core/shortcuts/action_category.dart';
import 'package:netcrux/core/shortcuts/netcrux_action.dart';

/// Declarative ordering and grouping of NetCrux's menu-bar actions, in the
/// suite-wide canonical group order (see the shared `crux_menu_bar` README).
///
/// `netcrux_action_descriptors.dart` is the single source of truth for *which*
/// actions appear in the menu surface and *when* they are visible/enabled.
/// This table is the single source of truth for the *order* they appear in and
/// *where the separators fall*.
///
/// Before this table NetCrux rendered every category as one undifferentiated
/// run of items in enum-declaration order — View was 23 consecutive rows with
/// no separator, and the order tracked nothing but the sequence in which
/// features happened to be built.
///
/// ## Canonical group order
///
/// - **File** — New | Open/Import | Save | Export | Close | Reset |
///   Collaborative session
/// - **View** — Command Palette | Zoom | Panels | Panes | Tabs | Appearance
/// - **Navigate** — Scope | Trace overlays + Zoom to Selection | Cone of
///   influence | X-trace | Diff
/// - **Search** — Find
/// - **Tools** — Bookmarks/annotations | Symbols | FSM | CDC | Reset domain |
///   Activity | Diagnostics (last)
/// - **Help** — Documentation | Report Issue | Check for Updates | About
///
/// ## Not in this table on purpose
///
/// `openSettings` and `quit` are placed by `CruxDesktopMenuBar` from
/// [kAppMenuActions] because their placement is platform-specific. `openAbout`
/// and `checkForUpdates` *are* here, under Help — their Windows/Linux home —
/// and the macOS renderer hoists them into the application menu.
///
/// `ActionCategory.edit` has no entry: NetCrux has no editing actions, so no
/// Edit menu renders.
///
/// ## Drift guard
///
/// `menu_layout_test.dart` asserts that `cruxMenuLayoutActions(this)` unioned
/// with `kAppMenuActions.desktopFolded` equals exactly the set of actions whose
/// descriptor lists `NetcruxActionSurface.menu`, so a newly menu-visible action
/// fails the test until it is given a home here.
const CruxMenuLayout<NetcruxAction> kMenuLayout = {
  // ── File ──────────────────────────────────────────────────────────────────
  ActionCategory.file: [
    [
      NetcruxAction.newWorkspace,
    ],
    [
      NetcruxAction.openProject,
      NetcruxAction.openSourceFiles,
      NetcruxAction.openNetlistJson,
      NetcruxAction.openWorkspace,
      NetcruxAction.openSession,
      NetcruxAction.importFilelist,
    ],
    // Auxiliary inputs loaded alongside the design: a comparison netlist for
    // the diff view and a waveform for activity analysis. Each loader sits
    // next to the command that unloads it.
    [
      NetcruxAction.loadComparisonNetlist,
      NetcruxAction.clearComparisonNetlist,
      NetcruxAction.openWaveformFile,
      NetcruxAction.closeWaveformFile,
    ],
    [
      NetcruxAction.saveSession,
      NetcruxAction.saveWorkspaceAs,
    ],
    [
      NetcruxAction.exportPng,
      NetcruxAction.exportSvg,
      NetcruxAction.exportJson,
    ],
    // Close Tab (Cmd/Ctrl+W) leads the close group, mirroring WaveCrux's
    // File menu (suite keyboard-parity pass). NetCrux tabs *are* projects,
    // so Close Project closes the same active tab under its
    // project-flavored label at Cmd/Ctrl+Shift+W.
    [
      NetcruxAction.closeTab,
      NetcruxAction.closeProject,
    ],
    [
      NetcruxAction.resetWorkspace,
    ],
    // The collaborative session, last in File as in WaveCrux. Leave Session
    // greys out until a session is live.
    [
      NetcruxAction.shareSession,
      NetcruxAction.joinSession,
      NetcruxAction.leaveSession,
    ],
  ],

  // ── View ──────────────────────────────────────────────────────────────────
  ActionCategory.view: [
    [
      NetcruxAction.openCommandPalette,
    ],
    [
      NetcruxAction.zoomIn,
      NetcruxAction.zoomOut,
      NetcruxAction.zoomFitAll,
    ],
    [
      NetcruxAction.toggleHierarchyTree,
      NetcruxAction.toggleInspector,
      NetcruxAction.showCrossProbePanel,
      NetcruxAction.showBookmarksPanel,
      NetcruxAction.showAnnotationsPanel,
      NetcruxAction.showSourcePane,
      NetcruxAction.closeSourcePane,
      NetcruxAction.showDiffPane,
      NetcruxAction.showFsmBubbleDiagram,
      NetcruxAction.clearFsmSelection,
      NetcruxAction.showCdcAnalysisPane,
      NetcruxAction.clearCdcAnalysisSelection,
      NetcruxAction.showResetDomainAnalysisPane,
      NetcruxAction.clearResetAnalysisSelection,
      NetcruxAction.showActivityHeatmap,
      NetcruxAction.clearActivityColoring,
    ],
    [
      NetcruxAction.splitPaneRight,
      NetcruxAction.closePane,
      NetcruxAction.focusOtherPane,
      NetcruxAction.moveTabToOtherPane,
    ],
    [
      NetcruxAction.nextTab,
      NetcruxAction.previousTab,
    ],
    [
      NetcruxAction.toggleTheme,
    ],
  ],

  // ── Navigate ──────────────────────────────────────────────────────────────
  ActionCategory.navigate: [
    [
      NetcruxAction.jumpToTop,
      NetcruxAction.popOutScope,
    ],
    [
      NetcruxAction.showFanin,
      NetcruxAction.showFanout,
      NetcruxAction.zoomToSelection,
    ],
    [
      NetcruxAction.showConeOfInfluenceFanin,
      NetcruxAction.showConeOfInfluenceFanout,
      NetcruxAction.clearConeOfInfluence,
    ],
    [
      NetcruxAction.showXTrace,
      NetcruxAction.showXTracePanel,
      NetcruxAction.clearXTrace,
    ],
    [
      NetcruxAction.openSourceForElement,
    ],
    [
      NetcruxAction.navigatePrevDiff,
      NetcruxAction.navigateNextDiff,
    ],
    [
      NetcruxAction.clearOverlay,
    ],
  ],

  // ── Search ────────────────────────────────────────────────────────────────
  ActionCategory.search: [
    [
      NetcruxAction.openSearch,
    ],
  ],

  // ── Tools ─────────────────────────────────────────────────────────────────
  ActionCategory.tools: [
    [
      NetcruxAction.addBookmark,
      NetcruxAction.addAnnotation,
    ],
    [
      NetcruxAction.openSymbolManager,
      NetcruxAction.importSymbolFromSvg,
      NetcruxAction.editSymbolForCurrentInstance,
      NetcruxAction.removeSymbolForCurrentInstance,
    ],
    [
      NetcruxAction.detectFsmForCurrentRegister,
      NetcruxAction.runFsmDetectionAcrossDesign,
    ],
    [
      NetcruxAction.runCdcAnalysis,
      NetcruxAction.showCdcCrossingForSelectedSignal,
    ],
    [
      NetcruxAction.runResetDomainAnalysis,
      NetcruxAction.showResetCrossingForSelectedSignal,
    ],
    [
      NetcruxAction.runActivityAnalysis,
      NetcruxAction.configureActivityScheme,
    ],
    // Tools ends with the diagnostics group in every product: the per-tab
    // surface (reveal + toggle), then the process-wide dialog — Tab
    // Diagnostics leads, matching WaveCrux's menu placement.
    [
      NetcruxAction.openTabDiagnostics,
      NetcruxAction.toggleDiagnosticsPanel,
      NetcruxAction.openAppDiagnostics,
    ],
  ],

  // ── Help ──────────────────────────────────────────────────────────────────
  // About and Check for Updates are hoisted into the macOS application menu.
  ActionCategory.help: [
    [
      NetcruxAction.openDocumentation,
    ],
    [
      NetcruxAction.submitIssue,
    ],
    [
      NetcruxAction.checkForUpdates,
    ],
    [
      NetcruxAction.openAbout,
    ],
  ],
};

/// The four actions whose menu placement the host platform decides.
const CruxAppMenuActions<NetcruxAction> kAppMenuActions = CruxAppMenuActions(
  about: NetcruxAction.openAbout,
  checkForUpdates: NetcruxAction.checkForUpdates,
  settings: NetcruxAction.openSettings,
  quit: NetcruxAction.quit,
);
