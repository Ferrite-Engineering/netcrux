// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/interfaces/x_trace_service.dart';
import 'package:netcrux/domain/models/activity/waveform_source.dart';
import 'package:netcrux/domain/models/schematic/laid_out_graph.dart';
import 'package:netcrux/domain/models/selection/selection.dart';
import 'package:netcrux/domain/models/trace/trace_overlay.dart';
import 'package:netcrux/features/cdc/providers/cdc_analysis_state_provider.dart';
import 'package:netcrux/features/diff/providers/diff_pane_state_provider.dart';
import 'package:netcrux/features/fsm/providers/selected_fsm_provider.dart';
import 'package:netcrux/features/project/providers/current_laid_out_graph_provider.dart';
import 'package:netcrux/features/reset_domain/providers/reset_domain_analysis_state_provider.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/features/viewer/providers/trace_overlay_notifier.dart';
import 'package:netcrux/features/viewer/providers/x_trace_result_notifier.dart';
import 'package:netcrux/services/schematic/net_activity_color_override_provider.dart';
import 'package:netcrux/services/waveform/waveform_source_service_provider.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_notifier.dart';
import 'package:netcrux/services/workspace/tab_container_manager_holder.dart';

/// Root-scope mirror of the **active tab's** per-tab gating flags consumed
/// by `NetcruxActionContext`. The action-discovery surfaces (menu bar,
/// command palette, toolbar) and the keyboard dispatch path evaluate
/// enablement at the root scope and cannot `ref.watch` a tab container's
/// providers, so this re-emits the active tab's netlist / selection /
/// overlay / analysis state up to the root.
///
/// Bundled into one record rather than one provider per flag to keep the
/// root-scope mirror surface small; reads go through the resolved
/// `container`, not `ref`, so the per-tab scope-leak guard does not flag
/// it. Mirrors WaveCrux's `ActiveTabActionFlags`.
@immutable
class ActiveTabActionFlags {
  /// Creates a flags snapshot. Defaults describe an empty tab.
  const ActiveTabActionFlags({
    this.hasNetlist = false,
    this.hasSelection = false,
    this.hasTraceOverlay = false,
    this.hasXTraceResult = false,
    this.comparisonActive = false,
    this.waveformLoaded = false,
    this.cdcAnalysisPresent = false,
    this.resetAnalysisPresent = false,
    this.fsmFocused = false,
    this.activityColoringActive = false,
  });

  /// Whether the active tab has a non-empty laid-out schematic.
  final bool hasNetlist;

  /// Whether the active tab has at least one selected element.
  final bool hasSelection;

  /// Whether the active tab has an active trace overlay.
  final bool hasTraceOverlay;

  /// Whether the active tab holds a non-empty X-trace result.
  final bool hasXTraceResult;

  /// Whether the active tab has a comparison netlist loaded.
  final bool comparisonActive;

  /// Whether the active tab has a waveform source loaded.
  final bool waveformLoaded;

  /// Whether the active tab holds a non-empty CDC analysis result.
  final bool cdcAnalysisPresent;

  /// Whether the active tab holds a non-empty reset-domain analysis
  /// result.
  final bool resetAnalysisPresent;

  /// Whether the active tab has an FSM focused in the bubble diagram.
  final bool fsmFocused;

  /// Whether the active tab has an activity color override applied.
  final bool activityColoringActive;

  /// Returns a copy with the given fields replaced.
  ActiveTabActionFlags copyWith({
    bool? hasNetlist,
    bool? hasSelection,
    bool? hasTraceOverlay,
    bool? hasXTraceResult,
    bool? comparisonActive,
    bool? waveformLoaded,
    bool? cdcAnalysisPresent,
    bool? resetAnalysisPresent,
    bool? fsmFocused,
    bool? activityColoringActive,
  }) => ActiveTabActionFlags(
    hasNetlist: hasNetlist ?? this.hasNetlist,
    hasSelection: hasSelection ?? this.hasSelection,
    hasTraceOverlay: hasTraceOverlay ?? this.hasTraceOverlay,
    hasXTraceResult: hasXTraceResult ?? this.hasXTraceResult,
    comparisonActive: comparisonActive ?? this.comparisonActive,
    waveformLoaded: waveformLoaded ?? this.waveformLoaded,
    cdcAnalysisPresent: cdcAnalysisPresent ?? this.cdcAnalysisPresent,
    resetAnalysisPresent: resetAnalysisPresent ?? this.resetAnalysisPresent,
    fsmFocused: fsmFocused ?? this.fsmFocused,
    activityColoringActive:
        activityColoringActive ?? this.activityColoringActive,
  );

  @override
  bool operator ==(Object other) =>
      other is ActiveTabActionFlags &&
      other.hasNetlist == hasNetlist &&
      other.hasSelection == hasSelection &&
      other.hasTraceOverlay == hasTraceOverlay &&
      other.hasXTraceResult == hasXTraceResult &&
      other.comparisonActive == comparisonActive &&
      other.waveformLoaded == waveformLoaded &&
      other.cdcAnalysisPresent == cdcAnalysisPresent &&
      other.resetAnalysisPresent == resetAnalysisPresent &&
      other.fsmFocused == fsmFocused &&
      other.activityColoringActive == activityColoringActive;

  @override
  int get hashCode => Object.hash(
    hasNetlist,
    hasSelection,
    hasTraceOverlay,
    hasXTraceResult,
    comparisonActive,
    waveformLoaded,
    cdcAnalysisPresent,
    resetAnalysisPresent,
    fsmFocused,
    activityColoringActive,
  );
}

/// See [ActiveTabActionFlags]. Plain [NotifierProvider] (not codegen) so
/// the state class keeps a clean name and the cross-container
/// subscription pattern stays explicit; matches the WaveCrux reference
/// implementation of the same mirror.
final activeTabActionFlagsProvider =
    NotifierProvider<ActiveTabActionFlagsNotifier, ActiveTabActionFlags>(
      ActiveTabActionFlagsNotifier.new,
      name: 'activeTabActionFlagsProvider',
    );

/// Rebinds to the active tab's container whenever the active tab
/// changes, subscribing to each mirrored per-tab provider and re-emitting
/// its gating projection.
class ActiveTabActionFlagsNotifier extends Notifier<ActiveTabActionFlags> {
  /// True once this notifier is disposed (or is between rebuilds), so a
  /// deferred [_apply] microtask never writes `state` on a dead notifier.
  bool _disposed = false;

  /// Applies [update] to the *current* [state] on a microtask rather than
  /// synchronously.
  ///
  /// The mirrored per-tab providers below are `container.listen`ed, and one of
  /// them can notify while the widget tree is mid-build — e.g. the async
  /// `currentLaidOutGraphProvider` resolving in the same frame `InspectorPanel`
  /// first watches it. Writing `state` during a build throws "Tried to modify a
  /// provider while the widget tree was building", so the write is deferred just
  /// past the build. Applying [update] to the live `state` (not a value captured
  /// at listen time) keeps a batch of listeners firing in one tick from
  /// clobbering one another.
  void _apply(ActiveTabActionFlags Function(ActiveTabActionFlags) update) {
    scheduleMicrotask(() {
      if (_disposed) return;
      final next = update(state);
      if (next != state) state = next;
    });
  }

  @override
  ActiveTabActionFlags build() {
    // build() re-runs on the same instance when its dependencies change; the
    // previous run's onDispose has already flipped this true, so clear it.
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    final activeTabId = ref.watch(
      netcruxWorkspaceProvider.select((ws) => ws.value?.activeTabId),
    );
    final manager = ref.watch(tabContainerManagerHolderProvider).manager;
    if (activeTabId == null || manager == null) {
      return const ActiveTabActionFlags();
    }
    final container = manager.containerFor(activeTabId);

    bool netlistLoaded(AsyncValue<LaidOutGraph?> laidOut) {
      final graph = laidOut.value;
      return graph != null && !graph.isEmpty;
    }

    bool activityColoring(Map<String, Color>? overrides) =>
        overrides != null && overrides.isNotEmpty;

    final subs = <ProviderSubscription<Object?>>[
      container.listen<AsyncValue<LaidOutGraph?>>(
        currentLaidOutGraphProvider,
        (_, next) => _apply((s) => s.copyWith(hasNetlist: netlistLoaded(next))),
      ),
      container.listen<Selection>(
        selectedElementProvider,
        (_, next) => _apply((s) => s.copyWith(hasSelection: next.isNotEmpty)),
      ),
      container.listen<TraceOverlay>(
        traceOverlayProvider,
        (_, next) => _apply((s) => s.copyWith(hasTraceOverlay: !next.isEmpty)),
      ),
      container.listen<XTraceResult>(
        xTraceResultProvider,
        (_, next) => _apply((s) => s.copyWith(hasXTraceResult: !next.isEmpty)),
      ),
      container.listen<DiffPaneState>(
        diffPaneStateProvider,
        (_, next) =>
            _apply((s) => s.copyWith(comparisonActive: next.hasActiveDiff)),
      ),
      container.listen<AsyncValue<WaveformSource?>>(
        currentWaveformSourceProvider,
        (_, next) =>
            _apply((s) => s.copyWith(waveformLoaded: next.value != null)),
      ),
      container.listen<CdcAnalysisState>(
        cdcAnalysisStateProvider,
        (_, next) =>
            _apply((s) => s.copyWith(cdcAnalysisPresent: !next.result.isEmpty)),
      ),
      container.listen<ResetDomainAnalysisState>(
        resetDomainAnalysisStateProvider,
        (_, next) => _apply(
          (s) => s.copyWith(resetAnalysisPresent: !next.result.isEmpty),
        ),
      ),
      container.listen<SelectedFsmState>(
        selectedFsmProvider,
        (_, next) => _apply((s) => s.copyWith(fsmFocused: next.hasFsm)),
      ),
      container.listen<Map<String, Color>?>(
        netActivityColorOverrideProvider,
        (_, next) => _apply(
          (s) => s.copyWith(activityColoringActive: activityColoring(next)),
        ),
      ),
    ];
    for (final sub in subs) {
      ref.onDispose(sub.close);
    }

    return ActiveTabActionFlags(
      hasNetlist: netlistLoaded(container.read(currentLaidOutGraphProvider)),
      hasSelection: container.read(selectedElementProvider).isNotEmpty,
      hasTraceOverlay: !container.read(traceOverlayProvider).isEmpty,
      hasXTraceResult: !container.read(xTraceResultProvider).isEmpty,
      comparisonActive: container.read(diffPaneStateProvider).hasActiveDiff,
      waveformLoaded:
          container.read(currentWaveformSourceProvider).value != null,
      cdcAnalysisPresent: !container
          .read(cdcAnalysisStateProvider)
          .result
          .isEmpty,
      resetAnalysisPresent: !container
          .read(resetDomainAnalysisStateProvider)
          .result
          .isEmpty,
      fsmFocused: container.read(selectedFsmProvider).hasFsm,
      activityColoringActive: activityColoring(
        container.read(netActivityColorOverrideProvider),
      ),
    );
  }
}
