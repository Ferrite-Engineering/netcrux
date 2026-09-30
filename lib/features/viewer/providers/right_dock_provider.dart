// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/models/analysis/analysis_panel_kind.dart';
import 'package:netcrux/features/remote/providers/cross_probe_visible_provider.dart';
import 'package:netcrux/features/viewer/providers/analysis_dock_provider.dart';
import 'package:netcrux/features/viewer/providers/panel_layout_provider.dart';
import 'package:netcrux/features/viewer/providers/x_trace_panel_visible_provider.dart';

/// The pinned inspector tab.
const String kRightDockTabInspector = 'inspector';

/// The docked cross-probe panel tab (on-demand).
const String kRightDockTabCrossProbe = 'crossProbe';

/// The docked X-trace result panel tab (on-demand).
///
/// Native region is the right dock — the trace is read *against* the
/// schematic, beside the Inspector, where NetCrux's other element-oriented
/// surfaces live. Movable, so the bottom dock (where WaveCrux keeps its
/// identically-named panel) is one drag away.
const String kRightDockTabXTrace = 'xTrace';

/// Prefix for the dynamic analysis tabs (`'analysis:cdc'` …).
const String kRightDockAnalysisPrefix = 'analysis:';

/// The bottom dock's region id (drag-between-docks).
const String kDockRegionBottom = 'bottom';

/// The right dock's region id (drag-between-docks).
const String kDockRegionRight = 'right';

/// Drag-between-docks placement overrides (tab id → region). Session-only,
/// like every other right-dock feature state. Movable tabs: the open
/// analyses and Cross-Probe (native region: right).
class DockPlacementsNotifier extends Notifier<Map<String, String>> {
  @override
  Map<String, String> build() => const {};

  /// Re-homes [id] into [region].
  void move(String id, String region) => state = {...state, id: region};

  /// The region [id] currently lives in.
  String regionOf(String id, String nativeRegion) => state[id] ?? nativeRegion;
}

/// See [DockPlacementsNotifier].
final dockPlacementsProvider =
    NotifierProvider<DockPlacementsNotifier, Map<String, String>>(
      DockPlacementsNotifier.new,
      name: 'dockPlacementsProvider',
    );

/// The right-dock tab id for [kind].
String analysisDockTabId(AnalysisPanelKind kind) =>
    '$kRightDockAnalysisPrefix${kind.name}';

/// Holds the right dock's active tab id. See [rightDockTabProvider].
class RightDockTabNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  /// Records [id] as the active tab without touching region visibility.
  // Not a setter: this is an intent method on a Notifier, symmetric with
  // [reveal], and the analyzer's setter suggestion would read as plain
  // assignment at call sites.
  // ignore: use_setters_to_change_properties
  void select(String id) => state = id;

  /// Reveals [id]: records the choice AND opens the right region — the
  /// shared reveal path for the analysis-dock openers, the CXP toggle, and
  /// the dock widget's auto-reveal.
  void reveal(String id) {
    state = id;
    // Fire-and-forget: the settings mirror behind the layout notifier is
    // async, but the in-memory visibility updates synchronously.
    unawaited(
      ref.read(panelLayoutProvider.notifier).setInspectorVisible(visible: true),
    );
  }
}

/// The right dock's active tab id.
///
/// Root-scoped, session-only — exactly like [analysisDockProvider] and
/// [crossProbeVisibleProvider], the feature states whose tabs it selects
/// between. The persisted layout (`AppSettings.panelLayout`) carries only
/// region visibility and sizes; an analysis or CXP tab with no live state
/// behind it would restore as an empty explainer.
final rightDockTabProvider = NotifierProvider<RightDockTabNotifier, String?>(
  RightDockTabNotifier.new,
  name: 'rightDockTabProvider',
);

/// The right-dock tab that is (or would be) active, validated against the
/// presence providers. Mirrors the retired priority chain (Cross-Probe >
/// analysis dock > Inspector) when no explicit choice exists or the choice
/// went stale.
final Provider<String> effectiveRightDockTabProvider = Provider<String>((ref) {
  final tab = ref.watch(rightDockTabProvider);
  final openKinds = ref.watch(analysisDockProvider);
  final crossProbe = ref.watch(crossProbeVisibleProvider);
  final xTrace = ref.watch(xTracePanelVisibleProvider);
  if (tab != null) {
    if (tab.startsWith(kRightDockAnalysisPrefix)) {
      if (openKinds.any((k) => analysisDockTabId(k) == tab)) return tab;
    } else if (tab == kRightDockTabCrossProbe) {
      if (crossProbe) return tab;
    } else if (tab == kRightDockTabXTrace) {
      if (xTrace) return tab;
    } else {
      return tab;
    }
  }
  // Stale or unset: fall back to the most recently opened analysis, then
  // cross-probe, then X-trace, then the pinned inspector.
  if (openKinds.isNotEmpty) return analysisDockTabId(openKinds.last);
  if (crossProbe) return kRightDockTabCrossProbe;
  if (xTrace) return kRightDockTabXTrace;
  return kRightDockTabInspector;
}, name: 'effectiveRightDockTabProvider');

/// Whether the cross-probe panel is the tab on screen — the toolbar's CXP
/// glyph. Dock-aware: the feature being on *behind* the inspector tab does
/// not light the glyph.
final Provider<bool> crossProbeShowingProvider = Provider<bool>((ref) {
  if (!ref.watch(crossProbeVisibleProvider)) return false;
  final placements = ref.watch(dockPlacementsProvider);
  final layout = ref.watch(panelLayoutProvider);
  if ((placements[kRightDockTabCrossProbe] ?? kDockRegionRight) ==
      kDockRegionBottom) {
    // Moved to the bottom dock: on screen whenever that region is open (the
    // bottom dock has no competing selection state to hide it behind — its
    // other occupant is the pinned Diagnostics tab, tracked by the dock's
    // own active id, which falls back to the moved-in tab on reveal).
    return layout.diagnosticsVisible;
  }
  return layout.inspectorVisible &&
      ref.watch(effectiveRightDockTabProvider) == kRightDockTabCrossProbe;
}, name: 'crossProbeShowingProvider');
