// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// Immutable snapshot of the app state that decides whether each
/// [NetcruxAction] is visible and enabled in a given surface.
///
/// This is the single input to [NetcruxActionDescriptor.isVisible] /
/// [NetcruxActionDescriptor.isEnabled]. It is pure Dart (no Flutter imports)
/// so the descriptor table and its predicates are unit-testable without
/// pumping a widget. Each action-discovery surface (toolbar, menu bar,
/// command palette, keyboard dispatch) reads one shared instance from
/// `netcruxActionContextProvider` rather than building its own, which
/// guarantees every surface gates on identical state.
///
/// The per-tab fields (netlist, selection, overlays, analysis results)
/// describe the **active tab**; they are mirrored to the root scope by
/// `activeTabActionFlagsProvider` because the surfaces live outside every
/// per-tab `ProviderScope`. Mirrors the WaveCrux `ActionContext` pattern.
@immutable
class NetcruxActionContext {
  /// Creates a context snapshot. Defaults describe the empty workspace:
  /// no tab, nothing loaded, single pane.
  const NetcruxActionContext({
    this.hasOpenTab = false,
    this.hasNetlist = false,
    this.hasSelection = false,
    this.hasTraceOverlay = false,
    this.hasXTraceResult = false,
    this.comparisonActive = false,
    this.waveformLoaded = false,
    this.cdcAnalysisPresent = false,
    this.resetAnalysisPresent = false,
    this.hasCrossingSelection = false,
    this.fsmFocused = false,
    this.activityColoringActive = false,
    this.paneCount = 1,
    this.tabCountInActivePane = 0,
    this.isBrowser = false,
    this.collaborationAvailable = false,
    this.inCollabSession = false,
  });

  /// Whether the workspace has an active tab. Gates every action that
  /// mutates or reads per-tab state (the dispatcher resolves them through
  /// the active tab's container, which does not exist without a tab).
  final bool hasOpenTab;

  /// Whether the active tab has a non-empty laid-out schematic. Gates
  /// viewport actions (zoom / fit / navigation), exports, session save,
  /// design search, and the full-design analysis runs — all of which
  /// operate on the elaborated design.
  final bool hasNetlist;

  /// Whether the active tab has at least one schematic element selected.
  /// Gates the selection-seeded actions (fanin / fanout, cone of
  /// influence, X-trace, add bookmark / annotation, show source for
  /// element, per-instance symbol editing, per-register FSM detection,
  /// per-signal CDC / reset crossing scoping).
  final bool hasSelection;

  /// Whether the active tab has an active fanin / fanout / cone-of-
  /// influence trace overlay. Gates the overlay clear actions — clearing
  /// is meaningless with nothing to clear.
  final bool hasTraceOverlay;

  /// Whether the active tab holds a non-empty X-trace result. Gates
  /// Clear X-Trace.
  final bool hasXTraceResult;

  /// Whether the active tab has a comparison netlist loaded (Netlist Diff
  /// View). Gates next / previous divergence navigation and Clear
  /// Comparison Netlist.
  final bool comparisonActive;

  /// Whether the active tab has a waveform source (VCD/FST/GHW) loaded.
  /// Gates Close Waveform File and (together with [hasNetlist]) Run
  /// Activity Analysis.
  final bool waveformLoaded;

  /// Whether the active tab holds a non-empty CDC analysis result. Gates
  /// Clear CDC Analysis Selection.
  final bool cdcAnalysisPresent;

  /// Whether the active tab holds a non-empty reset-domain analysis
  /// result. Gates Clear Reset Analysis Selection.
  final bool resetAnalysisPresent;

  /// Whether the active tab has a CDC or reset-domain crossing focused,
  /// which the schematic paints. Escape (`clearOverlay`) clears it, so it
  /// enables that action alongside a selection or a trace.
  final bool hasCrossingSelection;

  /// Whether the active tab has an FSM focused in the bubble-diagram
  /// pane. Gates Clear FSM Selection.
  final bool fsmFocused;

  /// Whether the active tab has an activity color override applied to
  /// the schematic. Gates Clear Activity Coloring.
  final bool activityColoringActive;

  /// Number of workspace panes (1 = single pane; 2 = split). Gates the
  /// pane-management actions.
  final int paneCount;

  /// How many tabs the active pane holds. Gates Next / Previous Tab —
  /// cycling is inert with fewer than two.
  final int tabCountInActivePane;

  /// Whether this is the browser build. Structural, not transient: the
  /// browser has no local file system, no subprocesses and no sockets, so
  /// the actions that need them — opening projects, sources, sessions and
  /// workspaces, saving, exporting, filelist import, cross-probing, update
  /// checks, Quit — are hidden there rather than offered and broken.
  final bool isBrowser;

  /// Whether this build can take part in a collaborative session: a real
  /// collaboration service is bound (the open-source build binds a no-op) and
  /// this is not the browser build.
  ///
  /// Gates Join Session and Leave Session. Join is free in every edition, so
  /// it carries no tier badge, and the browser rule that hides tier-badged
  /// actions does not cover it; without this, a build with no collaboration
  /// protocol would offer a Join action that does nothing.
  final bool collaborationAvailable;

  /// Whether a collaborative session is live (including a join still waiting
  /// for the host's decision). Share and Join grey out while one is; Leave
  /// greys out while none is.
  final bool inCollabSession;

  @override
  bool operator ==(Object other) =>
      other is NetcruxActionContext &&
      other.hasOpenTab == hasOpenTab &&
      other.hasNetlist == hasNetlist &&
      other.hasSelection == hasSelection &&
      other.hasTraceOverlay == hasTraceOverlay &&
      other.hasXTraceResult == hasXTraceResult &&
      other.comparisonActive == comparisonActive &&
      other.waveformLoaded == waveformLoaded &&
      other.cdcAnalysisPresent == cdcAnalysisPresent &&
      other.resetAnalysisPresent == resetAnalysisPresent &&
      other.hasCrossingSelection == hasCrossingSelection &&
      other.fsmFocused == fsmFocused &&
      other.activityColoringActive == activityColoringActive &&
      other.paneCount == paneCount &&
      other.tabCountInActivePane == tabCountInActivePane &&
      other.isBrowser == isBrowser &&
      other.collaborationAvailable == collaborationAvailable &&
      other.inCollabSession == inCollabSession;

  @override
  int get hashCode => Object.hash(
    hasOpenTab,
    hasNetlist,
    hasSelection,
    hasTraceOverlay,
    hasXTraceResult,
    comparisonActive,
    waveformLoaded,
    cdcAnalysisPresent,
    resetAnalysisPresent,
    hasCrossingSelection,
    fsmFocused,
    activityColoringActive,
    paneCount,
    tabCountInActivePane,
    isBrowser,
    collaborationAvailable,
    inCollabSession,
  );
}
