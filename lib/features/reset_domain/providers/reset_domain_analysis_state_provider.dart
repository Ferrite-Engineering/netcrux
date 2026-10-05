// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:netcrux/domain/models/analysis/analysis_panel_kind.dart';
import 'package:netcrux/domain/models/analysis/crossing_signal_filter.dart';
import 'package:netcrux/domain/models/reset_domain/reset_crossing.dart';
import 'package:netcrux/domain/models/reset_domain/reset_domain.dart';
import 'package:netcrux/domain/models/reset_domain/reset_domain_analysis_result.dart';
import 'package:netcrux/domain/models/reset_domain/reset_severity.dart';
import 'package:netcrux/features/viewer/providers/analysis_dock_provider.dart';
import 'package:netcrux/services/reset_domain/reset_domain_analysis_service_provider.dart';

/// Per-tab snapshot of the Reset Domain analysis pane's state.
///
/// Holds:
///   * The most-recent [ResetDomainAnalysisResult] for the tab (or
///     [ResetDomainAnalysisResult.empty] when no analysis has run), and whether
///     it is current for the loaded design ([hasCurrentResult]).
///   * The currently-focused [ResetCrossing] (drives schematic selection
///     sync — when the user clicks a crossing row the matching net
///     highlights on the schematic).
///   * The currently-focused [ResetDomain] (filter state for the
///     panel's grouped list).
///   * The active severity filter (which crossings the panel renders).
///   * The optional [signalFilter] narrowing the list to one signal's
///     crossings, and a pending [revealCrossingId] request the pane
///     answers by scrolling that row into view.
@immutable
class ResetDomainAnalysisState {
  /// Creates a snapshot.
  const ResetDomainAnalysisState({
    this.result = ResetDomainAnalysisResult.empty,
    this.hasCurrentResult = false,
    this.selectedCrossingId,
    this.selectedDomainId,
    this.severityFilter = const <ResetSeverity>{
      ResetSeverity.critical,
      ResetSeverity.warning,
      ResetSeverity.info,
    },
    this.signalFilter,
    this.revealCrossingId,
  });

  /// Canonical empty snapshot.
  static const ResetDomainAnalysisState empty = ResetDomainAnalysisState();

  /// The most-recent analysis result for this tab.
  final ResetDomainAnalysisResult result;

  /// Whether [result] was computed for the design the tab has loaded now.
  ///
  /// True from the moment a result is installed until the analysis
  /// service reports the loaded netlist changed (`analysisInvalidated`),
  /// which also drops [result]. A current result may still be
  /// [ResetDomainAnalysisResult.isEmpty]: a design with one reset analyses to no
  /// domains worth listing, and that answer is as current as any other.
  final bool hasCurrentResult;

  /// `ResetCrossing.id` of the focused crossing, or null when none.
  final String? selectedCrossingId;

  /// `ResetDomain.id` of the focused domain, or null when none.
  final String? selectedDomainId;

  /// Active severity-filter chip set. Empty means "show none"; a full
  /// set means "show all". The panel toggles individual chips into and
  /// out of this set.
  final Set<ResetSeverity> severityFilter;

  /// When set, the pane lists only the crossings this filter admits.
  final CrossingSignalFilter? signalFilter;

  /// A crossing the pane should scroll into view and briefly flash, or
  /// null when no request is pending. The pane clears it through
  /// [ResetDomainAnalysisNotifier.acknowledgeReveal] once it has answered.
  final String? revealCrossingId;

  /// Convenience lookup for the currently-focused [ResetCrossing].
  ResetCrossing? get selectedCrossing {
    final id = selectedCrossingId;
    if (id == null) return null;
    return result.crossingById(id);
  }

  /// Convenience lookup for the currently-focused [ResetDomain].
  ResetDomain? get selectedDomain {
    final id = selectedDomainId;
    if (id == null) return null;
    return result.domainById(id);
  }

  /// The crossings the pane lists: [result]'s, narrowed by the severity
  /// filter and, when set, the [signalFilter]. Detection order.
  List<ResetCrossing> get visibleCrossings => <ResetCrossing>[
    for (final c in result.detectedCrossings)
      if (severityFilter.contains(c.severity) &&
          (signalFilter?.admits(c.id) ?? true))
        c,
  ];

  /// Returns a copy with the given fields replaced.
  ResetDomainAnalysisState copyWith({
    ResetDomainAnalysisResult? result,
    bool? hasCurrentResult,
    String? selectedCrossingId,
    String? selectedDomainId,
    Set<ResetSeverity>? severityFilter,
    CrossingSignalFilter? signalFilter,
    String? revealCrossingId,
    bool clearSelectedCrossingId = false,
    bool clearSelectedDomainId = false,
    bool clearSignalFilter = false,
    bool clearRevealCrossingId = false,
  }) => ResetDomainAnalysisState(
    result: result ?? this.result,
    hasCurrentResult: hasCurrentResult ?? this.hasCurrentResult,
    selectedCrossingId: clearSelectedCrossingId
        ? null
        : (selectedCrossingId ?? this.selectedCrossingId),
    selectedDomainId: clearSelectedDomainId
        ? null
        : (selectedDomainId ?? this.selectedDomainId),
    severityFilter: severityFilter ?? this.severityFilter,
    signalFilter: clearSignalFilter
        ? null
        : (signalFilter ?? this.signalFilter),
    revealCrossingId: clearRevealCrossingId
        ? null
        : (revealCrossingId ?? this.revealCrossingId),
  );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ResetDomainAnalysisState) return false;
    if (result != other.result) return false;
    if (hasCurrentResult != other.hasCurrentResult) return false;
    if (selectedCrossingId != other.selectedCrossingId) return false;
    if (selectedDomainId != other.selectedDomainId) return false;
    if (signalFilter != other.signalFilter) return false;
    if (revealCrossingId != other.revealCrossingId) return false;
    if (severityFilter.length != other.severityFilter.length) return false;
    for (final s in severityFilter) {
      if (!other.severityFilter.contains(s)) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    result,
    hasCurrentResult,
    selectedCrossingId,
    selectedDomainId,
    signalFilter,
    revealCrossingId,
    Object.hashAllUnordered(severityFilter),
  );
}

/// Notifier owning the per-tab [ResetDomainAnalysisState].
///
/// Lives in a per-tab `ProviderContainer` (mirrors CDC / FSM / diff /
/// source pane scoping) so each open tab keeps its own analysis result and
/// selection. The hosting `ResetDomainAnalysisPanel` widget reads from and
/// writes to this notifier.
class ResetDomainAnalysisNotifier extends Notifier<ResetDomainAnalysisState> {
  @override
  ResetDomainAnalysisState build() {
    // The active tab's analysis service emits on `analysisInvalidated`
    // whenever the tab re-elaborates (the open-core no-op service uses an
    // empty stream, so this is inert on Open Core builds). Drop the stale
    // result on that signal so an open pane stops showing the previous
    // elaboration's crossings instead of silently retaining them until a
    // manual re-run.
    final service = ref.watch(resetDomainAnalysisServiceProvider);
    final sub = service.analysisInvalidated.listen((_) => _onInvalidated());
    ref.onDispose(sub.cancel);
    // Closing the Reset Domain panel, by any route (its dock tab's close button,
    // the View-menu toggle, a clear action), drops the crossing selection
    // and the signal filter, so no crossing stays painted on a schematic
    // whose panel is gone. The dock is root-scoped workspace chrome and
    // shared by every tab, so each tab's notifier clears its own state.
    ref.listen<List<AnalysisPanelKind>>(analysisDockProvider, (prev, next) {
      final wasOpen = prev?.contains(AnalysisPanelKind.resetDomain) ?? false;
      if (wasOpen && !next.contains(AnalysisPanelKind.resetDomain)) {
        _onPanelClosed();
      }
    });
    return ResetDomainAnalysisState.empty;
  }

  /// Clears the stale analysis result and any selections or filters
  /// that referenced it, preserving the user's severity-filter choice.
  void _onInvalidated() {
    if (state.result == ResetDomainAnalysisResult.empty &&
        !state.hasCurrentResult &&
        state.selectedCrossingId == null &&
        state.selectedDomainId == null &&
        state.signalFilter == null) {
      return;
    }
    state = state.copyWith(
      result: ResetDomainAnalysisResult.empty,
      hasCurrentResult: false,
      clearSelectedCrossingId: true,
      clearSelectedDomainId: true,
      clearSignalFilter: true,
      clearRevealCrossingId: true,
    );
  }

  void _onPanelClosed() {
    if (state.selectedCrossingId == null &&
        state.selectedDomainId == null &&
        state.signalFilter == null &&
        state.revealCrossingId == null) {
      return;
    }
    state = state.copyWith(
      clearSelectedCrossingId: true,
      clearSelectedDomainId: true,
      clearSignalFilter: true,
      clearRevealCrossingId: true,
    );
  }

  /// Installs a freshly-computed [ResetDomainAnalysisResult] and marks it current.
  /// Preserves the currently-selected crossing / domain, the signal
  /// filter and a pending reveal only when the new result contains the
  /// ids they name; otherwise clears them.
  void setResult(ResetDomainAnalysisResult result) {
    final keepCrossing =
        state.selectedCrossingId != null &&
            result.crossingById(state.selectedCrossingId!) != null
        ? state.selectedCrossingId
        : null;
    final keepDomain =
        state.selectedDomainId != null &&
            result.domainById(state.selectedDomainId!) != null
        ? state.selectedDomainId
        : null;
    final filter = state.signalFilter;
    final keepFilter =
        filter != null &&
        filter.crossingIds.every((id) => result.crossingById(id) != null);
    final reveal = state.revealCrossingId;
    final keepReveal = reveal != null && result.crossingById(reveal) != null;
    state = state.copyWith(
      result: result,
      hasCurrentResult: true,
      selectedCrossingId: keepCrossing,
      selectedDomainId: keepDomain,
      clearSelectedCrossingId: keepCrossing == null,
      clearSelectedDomainId: keepDomain == null,
      clearSignalFilter: !keepFilter,
      clearRevealCrossingId: !keepReveal,
    );
  }

  /// Focuses the crossing with id [crossingId] (or clears the
  /// selection when null). Silently ignored when the id is unknown.
  void selectCrossing(String? crossingId) {
    if (crossingId == null) {
      state = state.copyWith(clearSelectedCrossingId: true);
      return;
    }
    if (state.result.crossingById(crossingId) == null) return;
    state = state.copyWith(selectedCrossingId: crossingId);
  }

  /// Row-click semantics: focuses [crossingId], or clears the focus when
  /// it is already the focused crossing.
  void toggleCrossing(String crossingId) {
    if (state.selectedCrossingId == crossingId) {
      selectCrossing(null);
    } else {
      selectCrossing(crossingId);
    }
  }

  /// "Show Reset Crossings for This Signal": narrows the pane to
  /// [crossingIds] (when there are several), focuses one of them and asks
  /// the pane to scroll it into view.
  ///
  /// The focused crossing stays focused when it is among [crossingIds];
  /// otherwise the first known id is focused. The reveal request is
  /// raised even when the focus does not change, so repeating the command
  /// still produces visible feedback. Severity chips that would hide one
  /// of the crossings are switched on. Unknown ids are ignored; when none
  /// is known the state is left alone.
  void showCrossingsForSignal(
    List<String> crossingIds, {
    required String label,
  }) {
    final known = <ResetCrossing>[
      for (final id in crossingIds) ?state.result.crossingById(id),
    ];
    if (known.isEmpty) return;
    final ids = <String>{for (final c in known) c.id};
    final current = state.selectedCrossingId;
    final focus = current != null && ids.contains(current)
        ? current
        : known.first.id;
    state = state.copyWith(
      selectedCrossingId: focus,
      severityFilter: <ResetSeverity>{
        ...state.severityFilter,
        for (final c in known) c.severity,
      },
      signalFilter: ids.length > 1
          ? CrossingSignalFilter(label: label, crossingIds: ids)
          : null,
      clearSignalFilter: ids.length <= 1,
      revealCrossingId: focus,
    );
  }

  /// Drops the signal filter so the pane lists every crossing again.
  void clearSignalFilter() {
    if (state.signalFilter == null) return;
    state = state.copyWith(clearSignalFilter: true);
  }

  /// Called by the pane once it has answered the reveal request for
  /// [crossingId]. A newer request for a different crossing is kept.
  void acknowledgeReveal(String crossingId) {
    if (state.revealCrossingId != crossingId) return;
    state = state.copyWith(clearRevealCrossingId: true);
  }

  /// Focuses the domain with id [domainId] (or clears the selection
  /// when null). Silently ignored when the id is unknown.
  void selectDomain(String? domainId) {
    if (domainId == null) {
      state = state.copyWith(clearSelectedDomainId: true);
      return;
    }
    if (state.result.domainById(domainId) == null) return;
    state = state.copyWith(selectedDomainId: domainId);
  }

  /// Toggles [severity] in / out of the active filter set.
  void toggleSeverity(ResetSeverity severity) {
    final next = Set<ResetSeverity>.from(state.severityFilter);
    if (next.contains(severity)) {
      next.remove(severity);
    } else {
      next.add(severity);
    }
    state = state.copyWith(severityFilter: next);
  }

  /// Replaces the entire severity filter with [filter].
  void setSeverityFilter(Set<ResetSeverity> filter) {
    state = state.copyWith(severityFilter: filter);
  }

  /// Clears every selection (crossing + domain) and any pending reveal.
  /// Leaves the analysis result, the severity filter and the signal
  /// filter intact.
  void clearSelection() {
    if (state.selectedCrossingId == null &&
        state.selectedDomainId == null &&
        state.revealCrossingId == null) {
      return;
    }
    state = state.copyWith(
      clearSelectedCrossingId: true,
      clearSelectedDomainId: true,
      clearRevealCrossingId: true,
    );
  }

  /// Resets the entire pane state — analysis result, selections,
  /// severity filter — to [ResetDomainAnalysisState.empty]. The pane returns
  /// to its empty state.
  void reset() {
    state = ResetDomainAnalysisState.empty;
  }
}

/// Per-tab provider exposing the [ResetDomainAnalysisNotifier].
/// Scoped per-tab via the workspace's `TabContainerManager`, same
/// pattern as CDC / FSM / diff / source pane / bookmarks / X-trace.
final resetDomainAnalysisStateProvider =
    NotifierProvider<ResetDomainAnalysisNotifier, ResetDomainAnalysisState>(
      ResetDomainAnalysisNotifier.new,
      name: 'resetDomainAnalysisStateProvider',
    );

/// Convenience provider exposing only the most-recent
/// [ResetDomainAnalysisResult]. Lets widgets that only care about the
/// result itself (e.g. the panel's domain dropdown) rebuild without
/// re-firing on selection changes.
final perTabResetDomainAnalysisResultProvider =
    Provider<ResetDomainAnalysisResult>(
      (ref) => ref.watch(resetDomainAnalysisStateProvider).result,
      name: 'perTabResetDomainAnalysisResultProvider',
    );

/// Convenience provider exposing only the currently-focused crossing
/// (or null). Lets the schematic selection-sync layer listen narrowly
/// to crossing focus changes.
final selectedResetCrossingProvider = Provider<ResetCrossing?>(
  (ref) => ref.watch(resetDomainAnalysisStateProvider).selectedCrossing,
  name: 'selectedResetCrossingProvider',
);

/// Convenience provider exposing only the currently-focused reset
/// domain (or null). Lets the panel's domain filter rebuild narrowly.
final selectedResetDomainProvider = Provider<ResetDomain?>(
  (ref) => ref.watch(resetDomainAnalysisStateProvider).selectedDomain,
  name: 'selectedResetDomainProvider',
);

/// Convenience provider exposing only the active severity filter set.
final resetSeverityFilterProvider = Provider<Set<ResetSeverity>>(
  (ref) => ref.watch(resetDomainAnalysisStateProvider).severityFilter,
  name: 'resetSeverityFilterProvider',
);
