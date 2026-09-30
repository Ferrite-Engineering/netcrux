// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:netcrux/domain/models/reset_domain/reset_crossing.dart';
import 'package:netcrux/domain/models/reset_domain/reset_domain.dart';
import 'package:netcrux/domain/models/reset_domain/reset_domain_analysis_result.dart';
import 'package:netcrux/domain/models/reset_domain/reset_severity.dart';
import 'package:netcrux/services/reset_domain/reset_domain_analysis_service_provider.dart';

/// Per-tab snapshot of the Reset Domain analysis pane's state.
///
/// Holds:
///   * The most-recent [ResetDomainAnalysisResult] for the tab (or
///     [ResetDomainAnalysisResult.empty] when no analysis has run).
///   * The currently-focused [ResetCrossing] (drives schematic
///     selection sync — when the user clicks a crossing row the
///     matching net highlights on the schematic).
///   * The currently-focused [ResetDomain] (filter state for the
///     panel's grouped list).
///   * The active severity filter (which crossings the panel
///     renders).
@immutable
class ResetDomainAnalysisState {
  /// Creates a snapshot.
  const ResetDomainAnalysisState({
    this.result = ResetDomainAnalysisResult.empty,
    this.selectedCrossingId,
    this.selectedDomainId,
    this.severityFilter = const <ResetSeverity>{
      ResetSeverity.critical,
      ResetSeverity.warning,
      ResetSeverity.info,
    },
  });

  /// Canonical empty snapshot.
  static const ResetDomainAnalysisState empty = ResetDomainAnalysisState();

  /// The most-recent analysis result for this tab.
  final ResetDomainAnalysisResult result;

  /// `ResetCrossing.id` of the focused crossing, or null when none.
  final String? selectedCrossingId;

  /// `ResetDomain.id` of the focused domain, or null when none.
  final String? selectedDomainId;

  /// Active severity-filter chip set. Empty means "show none"; a full
  /// set means "show all". The panel toggles individual chips into
  /// and out of this set.
  final Set<ResetSeverity> severityFilter;

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

  /// Returns a copy with the given fields replaced.
  ResetDomainAnalysisState copyWith({
    ResetDomainAnalysisResult? result,
    String? selectedCrossingId,
    String? selectedDomainId,
    Set<ResetSeverity>? severityFilter,
    bool clearSelectedCrossingId = false,
    bool clearSelectedDomainId = false,
  }) => ResetDomainAnalysisState(
    result: result ?? this.result,
    selectedCrossingId: clearSelectedCrossingId
        ? null
        : (selectedCrossingId ?? this.selectedCrossingId),
    selectedDomainId: clearSelectedDomainId
        ? null
        : (selectedDomainId ?? this.selectedDomainId),
    severityFilter: severityFilter ?? this.severityFilter,
  );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ResetDomainAnalysisState) return false;
    if (result != other.result) return false;
    if (selectedCrossingId != other.selectedCrossingId) return false;
    if (selectedDomainId != other.selectedDomainId) return false;
    if (severityFilter.length != other.severityFilter.length) return false;
    for (final s in severityFilter) {
      if (!other.severityFilter.contains(s)) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    result,
    selectedCrossingId,
    selectedDomainId,
    Object.hashAllUnordered(severityFilter),
  );
}

/// Notifier owning the per-tab [ResetDomainAnalysisState].
///
/// Lives in a per-tab `ProviderContainer` (mirrors CDC / FSM / diff /
/// source pane scoping) so each open tab keeps its own analysis
/// result and selection. The hosting `ResetDomainAnalysisPanel` widget
/// reads from and writes to this notifier.
class ResetDomainAnalysisNotifier extends Notifier<ResetDomainAnalysisState> {
  @override
  ResetDomainAnalysisState build() {
    // Drop the stale result when the active tab re-elaborates (inert on
    // Open Core: the no-op service uses an empty invalidation stream) so
    // an open pane does not keep showing the previous elaboration's
    // crossings until a manual re-run.
    final service = ref.watch(resetDomainAnalysisServiceProvider);
    final sub = service.analysisInvalidated.listen((_) => _onInvalidated());
    ref.onDispose(sub.cancel);
    return ResetDomainAnalysisState.empty;
  }

  /// Clears the stale analysis result and any selections that referenced
  /// it, preserving the user's severity-filter choice.
  void _onInvalidated() {
    if (state.result == ResetDomainAnalysisResult.empty &&
        state.selectedCrossingId == null &&
        state.selectedDomainId == null) {
      return;
    }
    state = state.copyWith(
      result: ResetDomainAnalysisResult.empty,
      clearSelectedCrossingId: true,
      clearSelectedDomainId: true,
    );
  }

  /// Installs a freshly-computed [ResetDomainAnalysisResult].
  /// Preserves the currently-selected crossing / domain only when the
  /// new result contains the corresponding ids; otherwise clears
  /// them.
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
    state = state.copyWith(
      result: result,
      selectedCrossingId: keepCrossing,
      selectedDomainId: keepDomain,
      clearSelectedCrossingId: keepCrossing == null,
      clearSelectedDomainId: keepDomain == null,
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

  /// Clears every selection (crossing + domain). Leaves the analysis
  /// result and severity filter intact.
  void clearSelection() {
    state = state.copyWith(
      clearSelectedCrossingId: true,
      clearSelectedDomainId: true,
    );
  }

  /// Resets the entire pane state — analysis result, selections,
  /// severity filter — to [ResetDomainAnalysisState.empty]. The pane
  /// returns to its empty state.
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
