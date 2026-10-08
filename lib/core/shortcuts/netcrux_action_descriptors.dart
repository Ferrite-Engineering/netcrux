// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:netcrux/core/shortcuts/action_category.dart';
import 'package:netcrux/core/shortcuts/netcrux_action.dart';
import 'package:netcrux/core/shortcuts/netcrux_action_context.dart';
import 'package:netcrux/core/shortcuts/netcrux_action_descriptor.dart';

/// The single source of truth for where every [NetcruxAction] appears and
/// when it is visible / enabled. Every action-discovery surface (toolbar,
/// menu bar, command palette) and the keyboard dispatch path read from
/// this one function instead of maintaining per-surface visibility sets
/// and enablement logic — see [NetcruxActionDescriptor] for the
/// per-surface presentation policy.
///
/// ## IMPORTANT — adding a new action
///
/// This is an **exhaustive `switch`** (like `NetcruxAction.category` and
/// `.label`). Adding a value to [NetcruxAction] therefore fails to
/// compile until a case is added here, which is the guardrail that keeps
/// every new action wired into the single source of truth. Never
/// re-introduce a per-surface "hidden actions" set or a per-surface
/// enablement copy — declare the behavior here instead.
NetcruxActionDescriptor descriptorFor(NetcruxAction action) => switch (action) {
  // ── Toolbar + menu + palette, always enabled ────────────────────────
  // The file-open flows create their own tab, so they are meaningful on
  // the empty canvas. Projects and HDL sources need a local file system and
  // Yosys, so the browser build does not offer them.
  NetcruxAction.openProject ||
  NetcruxAction.openSourceFiles => const NetcruxActionDescriptor(
    surfaces: _everywhere,
    isVisible: _desktopOnly,
  ),

  // A pre-built netlist renders without elaboration, so it opens everywhere —
  // and in the browser it is the only way in.
  NetcruxAction.openNetlistJson => const NetcruxActionDescriptor(
    surfaces: _everywhere,
  ),

  // ── Toolbar + menu + palette, requires a laid-out design ────────────
  // Design search and the scope-navigation / viewport actions operate on
  // the elaborated schematic; they grey out until one is on canvas.
  // Zoom In / Out are toolbar buttons as well as menu and palette entries.
  NetcruxAction.openSearch ||
  NetcruxAction.jumpToTop ||
  NetcruxAction.popOutScope ||
  NetcruxAction.zoomIn ||
  NetcruxAction.zoomOut ||
  NetcruxAction.zoomFitAll => const NetcruxActionDescriptor(
    surfaces: _everywhere,
    isEnabled: _requiresNetlist,
  ),

  // ── Browsable (menu + palette), always enabled ──────────────────────
  // Import Filelist opens a new tab; the symbol-library actions manage
  // the per-user symbol store, independent of any open design; the
  // cross-probe panel is the peer-discovery status surface, so it stays
  // openable at zero peers (hiding it would hide the only place that
  // explains why no peers are connected).
  // Check for Updates and Submit Issue are workspace-independent app-level
  // actions — the update check compares build versions and the reporter
  // renders whatever session it finds, including none.
  NetcruxAction.openAbout ||
  NetcruxAction.submitIssue ||
  NetcruxAction.openAppDiagnostics ||
  NetcruxAction.openDocumentation ||
  NetcruxAction.openSymbolManager ||
  NetcruxAction.importSymbolFromSvg => const NetcruxActionDescriptor(
    surfaces: _menuPalette,
  ),

  // The same, but meaningless in a browser tab: a filelist names local
  // paths, the update check compares a desktop install against its release
  // manifest, and a page is closed, not quit.
  NetcruxAction.checkForUpdates ||
  NetcruxAction.importFilelist ||
  NetcruxAction.quit => const NetcruxActionDescriptor(
    surfaces: _menuPalette,
    isVisible: _desktopOnly,
  ),

  // ── Workspace lifecycle — browsable, always enabled ──────────────────
  // New / Open / Save As operate on the workspace *document*, which exists
  // whether or not a tab is open: "New Workspace" on an empty canvas is a
  // no-op the user can still reasonably ask for, and Save As on an empty
  // workspace writes a valid empty document. Reset is the exception below —
  // there is nothing to reset without a tab.
  NetcruxAction.newWorkspace => const NetcruxActionDescriptor(
    surfaces: _menuPalette,
  ),
  // A named workspace is a file on disk; the browser has none to read or
  // write.
  NetcruxAction.openWorkspace ||
  NetcruxAction.saveWorkspaceAs => const NetcruxActionDescriptor(
    surfaces: _menuPalette,
    isVisible: _desktopOnly,
  ),

  // ── Theme — browsable, always enabled ────────────────────────────────
  // Flipping light/dark is workspace-independent.
  NetcruxAction.toggleTheme => const NetcruxActionDescriptor(
    surfaces: _menuPalette,
  ),

  // ── Destructive / tab-scoped workspace commands ──────────────────────
  // Reset discards every tab, so it needs one to discard.
  NetcruxAction.resetWorkspace => const NetcruxActionDescriptor(
    surfaces: _menuPalette,
    isEnabled: _requiresTab,
  ),

  // ── Collaborative sessions — browsable, gated on session state ───────
  // Hosting (Share Session) is the only tier-gated step and the only one that
  // carries a badge; it is hidden in the browser by the tier rule above every
  // descriptor. Joining is free in every edition, so Join and Leave carry no
  // badge, and are offered only where a real collaboration service is bound
  // on a desktop build: the protocol is compiled out of the open-source build,
  // and the browser has no sockets to run it on.
  NetcruxAction.shareSession => const NetcruxActionDescriptor(
    surfaces: _menuPalette,
    isVisible: _desktopOnly,
    isEnabled: _notInCollabSession,
  ),
  NetcruxAction.joinSession => const NetcruxActionDescriptor(
    surfaces: _menuPalette,
    isVisible: _collaborationAvailable,
    isEnabled: _notInCollabSession,
  ),
  NetcruxAction.leaveSession => const NetcruxActionDescriptor(
    surfaces: _menuPalette,
    isVisible: _collaborationAvailable,
    isEnabled: _inCollabSession,
  ),

  // ── Close Tab — browsable, needs a tab to close ──────────────────────
  // Cmd/Ctrl+W's action (suite keyboard-parity pass). Menu + palette
  // only: the canonical common toolbar block's close slot stays with
  // closeProject below, mirroring WaveCrux where closeTab is likewise
  // not a toolbar action.
  NetcruxAction.closeTab => const NetcruxActionDescriptor(
    surfaces: _menuPalette,
    isEnabled: _requiresTab,
  ),

  // ── Tab navigation — needs somewhere to navigate to ──────────────────
  // Greyed with fewer than two tabs in the active pane: cycling a single
  // tab is inert, and a live-looking menu item that does nothing is worse
  // than a greyed one that explains itself.
  NetcruxAction.nextTab ||
  NetcruxAction.previousTab => const NetcruxActionDescriptor(
    surfaces: _menuPalette,
    isEnabled: _requiresMultipleTabs,
  ),

  // ── Settings — toolbar + menu + palette, always enabled ─────────────
  // A Settings (gear) button on the toolbar mirrors WaveCrux (a gear
  // affordance on every suite toolbar). Opening
  // Settings is workspace-independent, so it stays enabled on the empty
  // canvas.
  NetcruxAction.openSettings => const NetcruxActionDescriptor(
    surfaces: _everywhere,
  ),

  // ── Cross-Probe panel — toolbar + menu + palette, always enabled ────
  // On the toolbar, as on all four suite toolbars. Stays openable at
  // zero peers — the panel is the peer-discovery status surface, and
  // hiding it would hide the only place that explains why no peers are
  // connected.
  // Cross-probing is a local socket server plus an on-disk discovery
  // directory, neither of which exists in a browser.
  NetcruxAction.showCrossProbePanel => const NetcruxActionDescriptor(
    surfaces: _everywhere,
    isVisible: _desktopOnly,
  ),

  // ── Command palette opener — menu only ──────────────────────────────
  // Self-referential in the palette itself (you can't open the palette
  // from the palette), so it is excluded from the palette surface — but
  // it MUST stay reachable from the menu bar, otherwise unbinding its
  // keyboard shortcut (or losing it to a conflict) would make the
  // command palette permanently inaccessible with no recovery path.
  NetcruxAction.openCommandPalette => const NetcruxActionDescriptor(
    surfaces: _menuOnly,
  ),

  // ── Browsable, requires an open tab ─────────────────────────────────
  // These mutate or read per-tab state resolved through the active
  // tab's container; with no tab the dispatch has nothing to target.
  // The panel-show actions (annotations / source / diff /
  // FSM / CDC / reset / activity) open onto their panel's empty-state
  // explainer once a tab exists, so a loaded design is deliberately NOT
  // required for them.
  NetcruxAction.toggleHierarchyTree ||
  NetcruxAction.toggleInspector ||
  NetcruxAction.toggleDiagnosticsPanel ||
  // Tab Diagnostics (WaveCrux's chord) reveals the bottom dock's
  // Diagnostics tab — per-tab state, so it needs a tab like the toggle.
  NetcruxAction.openTabDiagnostics ||
  NetcruxAction.showAnnotationsPanel ||
  NetcruxAction.showSourcePane ||
  NetcruxAction.closeSourcePane ||
  NetcruxAction.showDiffPane ||
  NetcruxAction.showFsmBubbleDiagram ||
  NetcruxAction.showCdcAnalysisPane ||
  NetcruxAction.showResetDomainAnalysisPane ||
  NetcruxAction.showActivityHeatmap ||
  NetcruxAction.configureActivityScheme => const NetcruxActionDescriptor(
    surfaces: _menuPalette,
    isEnabled: _requiresTab,
  ),

  // ── Open Session — browsable, needs a tab ───────────────────────────
  // Loads into the active tab. A session is a file on disk, so the browser
  // build does not offer it.
  NetcruxAction.openSession => const NetcruxActionDescriptor(
    surfaces: _menuPalette,
    isVisible: _desktopOnly,
    isEnabled: _requiresTab,
  ),

  // ── Close Project — toolbar + menu + palette, needs a tab ───────────
  // Part of the canonical common toolbar block (Open · Save · Close), so
  // it gains the toolbar surface alongside saveSession below.
  NetcruxAction.closeProject => const NetcruxActionDescriptor(
    surfaces: _everywhere,
    isEnabled: _requiresTab,
  ),

  // ── Save Session — toolbar + menu + palette, needs a design ─────────
  // The second slot of the canonical common toolbar block.
  NetcruxAction.saveSession => const NetcruxActionDescriptor(
    surfaces: _everywhere,
    isVisible: _desktopOnly,
    isEnabled: _requiresNetlist,
  ),

  // ── Trace overlays — toolbar (as one split button) + menu + palette ──
  // Fan-in / fan-out / clear share a single grouped toolbar slot rather
  // than three near-identical buttons; see NetcruxToolbar.
  NetcruxAction.showFanin ||
  NetcruxAction.showFanout => const NetcruxActionDescriptor(
    surfaces: _everywhere,
    isEnabled: _requiresSelection,
  ),

  // ── Zoom to Selection — toolbar + menu + palette, needs a selection ──
  // Frames the selection, plus whatever a trace overlay seeded from it
  // highlights. With nothing selected there is nothing to frame.
  NetcruxAction.zoomToSelection => const NetcruxActionDescriptor(
    surfaces: _everywhere,
    isEnabled: _requiresSelection,
  ),

  // ── Browsable, requires a laid-out design ───────────────────────────
  // Exports operate on the schematic and write a file, which the browser
  // build cannot.
  NetcruxAction.exportPng ||
  NetcruxAction.exportSvg ||
  NetcruxAction.exportJson => const NetcruxActionDescriptor(
    surfaces: _menuPalette,
    isVisible: _desktopOnly,
    isEnabled: _requiresNetlist,
  ),

  // The full-design analysis runs and the comparison / waveform loaders
  // need an elaborated base design to analyze against.
  NetcruxAction.runCdcAnalysis ||
  NetcruxAction.runResetDomainAnalysis ||
  NetcruxAction.runFsmDetectionAcrossDesign ||
  NetcruxAction.loadComparisonNetlist ||
  NetcruxAction.openWaveformFile => const NetcruxActionDescriptor(
    surfaces: _menuPalette,
    isEnabled: _requiresNetlist,
  ),

  // ── Browsable, requires a non-empty selection ───────────────────────
  // All selection-seeded: the dispatch reads the active tab's primary
  // selection and silently returned before this gate existed.
  NetcruxAction.showConeOfInfluenceFanin ||
  NetcruxAction.showConeOfInfluenceFanout ||
  NetcruxAction.addAnnotation ||
  NetcruxAction.openSourceForElement ||
  NetcruxAction.editSymbolForCurrentInstance ||
  NetcruxAction.removeSymbolForCurrentInstance ||
  NetcruxAction.detectFsmForCurrentRegister ||
  NetcruxAction.showCdcCrossingForSelectedSignal ||
  NetcruxAction.showResetCrossingForSelectedSignal =>
    const NetcruxActionDescriptor(
      surfaces: _menuPalette,
      isEnabled: _requiresSelection,
    ),

  // ── Clear / dismiss actions — enabled only with something to clear ──
  // Clearing is never *tier*-gated (the openers stay unconditional in
  // the dispatcher), but a clear action with nothing to clear is inert,
  // so each one greys out until its target state exists.
  NetcruxAction.clearOverlay => const NetcruxActionDescriptor(
    surfaces: _everywhere,
    isEnabled: _requiresOverlayOrSelection,
  ),
  NetcruxAction.clearConeOfInfluence => const NetcruxActionDescriptor(
    surfaces: _menuPalette,
    isEnabled: _requiresTraceOverlay,
  ),
  NetcruxAction.clearXTrace => const NetcruxActionDescriptor(
    surfaces: _menuPalette,
    isEnabled: _requiresXTraceResult,
  ),
  NetcruxAction.clearFsmSelection => const NetcruxActionDescriptor(
    surfaces: _menuPalette,
    isEnabled: _requiresFsmFocused,
  ),
  NetcruxAction.clearCdcAnalysisSelection => const NetcruxActionDescriptor(
    surfaces: _menuPalette,
    isEnabled: _requiresCdcAnalysis,
  ),
  NetcruxAction.clearResetAnalysisSelection => const NetcruxActionDescriptor(
    surfaces: _menuPalette,
    isEnabled: _requiresResetAnalysis,
  ),
  NetcruxAction.clearActivityColoring => const NetcruxActionDescriptor(
    surfaces: _menuPalette,
    isEnabled: _requiresActivityColoring,
  ),

  // ── Comparison navigation — requires an active diff ─────────────────
  NetcruxAction.navigateNextDiff ||
  NetcruxAction.navigatePrevDiff ||
  NetcruxAction.clearComparisonNetlist => const NetcruxActionDescriptor(
    surfaces: _menuPalette,
    isEnabled: _requiresComparison,
  ),

  // ── Waveform source — requires a loaded waveform ────────────────────
  NetcruxAction.closeWaveformFile => const NetcruxActionDescriptor(
    surfaces: _menuPalette,
    isEnabled: _requiresWaveform,
  ),
  NetcruxAction.runActivityAnalysis => const NetcruxActionDescriptor(
    surfaces: _menuPalette,
    isEnabled: _requiresNetlistAndWaveform,
  ),

  // ── Pane management ─────────────────────────────────────────────────
  NetcruxAction.splitPaneRight => const NetcruxActionDescriptor(
    surfaces: _menuPalette,
    isEnabled: _requiresTabSinglePane,
  ),
  NetcruxAction.closePane ||
  NetcruxAction.focusOtherPane => const NetcruxActionDescriptor(
    surfaces: _menuPalette,
    isEnabled: _requiresMultiPane,
  ),
  NetcruxAction.moveTabToOtherPane => const NetcruxActionDescriptor(
    surfaces: _menuPalette,
    isEnabled: _requiresTabMultiPane,
  ),

  // ── X-trace ─────────────────────────────────────────────────────────
  // Menu bar + palette, not `_everywhere`: the toolbar is for tier-1
  // actions, and cone-of-influence — the closest analogue, and the group
  // X-trace sits beside in the Navigate menu — is `_menuPalette` too. The
  // discoverable surface that matters is the Pro schematic context menu
  // ("right-click the wire showing X" is the gesture the feature is named
  // for), which is not a descriptor surface. `clearXTrace` is declared
  // above with the other clear actions.
  NetcruxAction.showXTrace => const NetcruxActionDescriptor(
    surfaces: _menuPalette,
    isEnabled: _requiresSelection,
  ),
  NetcruxAction.showXTracePanel => const NetcruxActionDescriptor(
    surfaces: _menuPalette,
    isEnabled: _requiresTab,
  ),
};

// ── derived selectors (the API every surface consumes) ───────────────────────

/// Whether [action] should structurally appear in [surface] under
/// [context] (its descriptor lists the surface and its visibility
/// predicate passes). Independent of enablement — a visible action may
/// still be greyed out.
bool isActionVisibleIn(
  NetcruxAction action,
  NetcruxActionSurface surface,
  NetcruxActionContext context,
) =>
    descriptorFor(action).surfaces.contains(surface) &&
    isActionVisible(action, context);

/// Whether [action] exists at all under [context], on any surface.
///
/// The descriptor's own predicate, plus one rule stated here rather than on
/// every Pro descriptor: the browser build is Open Core only (client-side
/// gating is bypassable, so no paid tier ships there), and a Pro action it
/// cannot ever run is not offered.
bool isActionVisible(NetcruxAction action, NetcruxActionContext context) {
  if (context.isBrowser && action.requiredTier != LicenseTier.openCore) {
    return false;
  }
  return descriptorFor(action).isVisible(context);
}

/// Whether invoking [action] under [context] should do anything: it is
/// visible and enabled. The keyboard surface gates on this, so a chord bound
/// to a hidden action is as inert as one bound to a disabled action.
bool isActionInvocable(NetcruxAction action, NetcruxActionContext context) =>
    isActionVisible(action, context) && isActionEnabled(action, context);

/// Whether [action] is currently enabled under [context].
bool isActionEnabled(NetcruxAction action, NetcruxActionContext context) =>
    descriptorFor(action).isEnabled(context);

/// Actions to render in the menu bar under [context], grouped by
/// [ActionCategory] in enum declaration order. Every category key is
/// present. Disabled actions are *included* — the menu greys them out;
/// only structurally-hidden actions are omitted.
Map<ActionCategory, List<NetcruxAction>> groupedActionsFor(
  NetcruxActionSurface surface,
  NetcruxActionContext context,
) {
  final result = <ActionCategory, List<NetcruxAction>>{
    for (final category in ActionCategory.values) category: <NetcruxAction>[],
  };
  for (final action in NetcruxAction.values) {
    if (isActionVisibleIn(action, surface, context)) {
      result[action.category]!.add(action);
    }
  }
  return result;
}

/// Actions to list in the command palette under [context] — visible
/// **and** enabled, in enum declaration order. The palette has no greyed
/// state, so a disabled action is omitted rather than shown inert.
List<NetcruxAction> paletteActionsFor(NetcruxActionContext context) =>
    NetcruxAction.values
        .where(
          (a) =>
              isActionVisibleIn(a, NetcruxActionSurface.palette, context) &&
              isActionEnabled(a, context),
        )
        .toList();

// ── surface sets ─────────────────────────────────────────────────────────────

const Set<NetcruxActionSurface> _everywhere = {
  NetcruxActionSurface.toolbar,
  NetcruxActionSurface.menu,
  NetcruxActionSurface.palette,
};

const Set<NetcruxActionSurface> _menuPalette = {
  NetcruxActionSurface.menu,
  NetcruxActionSurface.palette,
};

const Set<NetcruxActionSurface> _menuOnly = {NetcruxActionSurface.menu};

// ── enablement predicates (top-level for const tear-off) ─────────────────────

bool _desktopOnly(NetcruxActionContext c) => !c.isBrowser;
bool _collaborationAvailable(NetcruxActionContext c) =>
    c.collaborationAvailable && !c.isBrowser;
bool _inCollabSession(NetcruxActionContext c) => c.inCollabSession;
bool _notInCollabSession(NetcruxActionContext c) => !c.inCollabSession;
bool _requiresTab(NetcruxActionContext c) => c.hasOpenTab;
bool _requiresMultipleTabs(NetcruxActionContext c) =>
    c.tabCountInActivePane > 1;
bool _requiresNetlist(NetcruxActionContext c) => c.hasNetlist;
bool _requiresSelection(NetcruxActionContext c) => c.hasSelection;
bool _requiresOverlayOrSelection(NetcruxActionContext c) =>
    c.hasTraceOverlay || c.hasSelection || c.hasCrossingSelection;
bool _requiresTraceOverlay(NetcruxActionContext c) => c.hasTraceOverlay;
bool _requiresXTraceResult(NetcruxActionContext c) => c.hasXTraceResult;
bool _requiresFsmFocused(NetcruxActionContext c) => c.fsmFocused;
bool _requiresCdcAnalysis(NetcruxActionContext c) => c.cdcAnalysisPresent;
bool _requiresResetAnalysis(NetcruxActionContext c) => c.resetAnalysisPresent;
bool _requiresActivityColoring(NetcruxActionContext c) =>
    c.activityColoringActive;
bool _requiresComparison(NetcruxActionContext c) => c.comparisonActive;
bool _requiresWaveform(NetcruxActionContext c) => c.waveformLoaded;
bool _requiresNetlistAndWaveform(NetcruxActionContext c) =>
    c.hasNetlist && c.waveformLoaded;
bool _requiresTabSinglePane(NetcruxActionContext c) =>
    c.hasOpenTab && c.paneCount == 1;
bool _requiresMultiPane(NetcruxActionContext c) => c.paneCount >= 2;
bool _requiresTabMultiPane(NetcruxActionContext c) =>
    c.hasOpenTab && c.paneCount >= 2;
