// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:netcrux/domain/models/analysis/analysis_panel_kind.dart';
import 'package:netcrux/domain/models/analysis/crossing_signal_filter.dart';
import 'package:netcrux/domain/models/cdc/cdc_analysis_result.dart';
import 'package:netcrux/domain/models/cdc/cdc_crossing.dart';
import 'package:netcrux/domain/models/cdc/cdc_severity.dart';
import 'package:netcrux/domain/models/cdc/clock_domain.dart';
import 'package:netcrux/features/viewer/providers/analysis_dock_provider.dart';
import 'package:netcrux/services/cdc/clock_domain_analysis_service_provider.dart';

/// Per-tab snapshot of the CDC analysis pane's state.
///
/// Holds:
///   * The most-recent [CdcAnalysisResult] for the tab (or
///     [CdcAnalysisResult.empty] when no analysis has run), and whether
///     it is current for the loaded design ([hasCurrentResult]).
///   * The currently-focused [CdcCrossing] (drives schematic selection
///     sync — when the user clicks a crossing row the matching net
///     highlights on the schematic).
///   * The currently-focused [ClockDomain] (filter state for the
///     panel's grouped list).
///   * The active severity filter (which crossings the panel renders).
///   * The optional [signalFilter] narrowing the list to one signal's
///     crossings, and a pending [revealCrossingId] request the pane
///     answers by scrolling that row into view.
@immutable
class CdcAnalysisState {
  /// Creates a snapshot.
  const CdcAnalysisState({
    this.result = CdcAnalysisResult.empty,
    this.hasCurrentResult = false,
    this.selectedCrossingId,
    this.selectedDomainId,
    this.severityFilter = const <CdcSeverity>{
      CdcSeverity.critical,
      CdcSeverity.warning,
      CdcSeverity.info,
    },
    this.signalFilter,
    this.revealCrossingId,
  });

  /// Canonical empty snapshot.
  static const CdcAnalysisState empty = CdcAnalysisState();

  /// The most-recent analysis result for this tab.
  final CdcAnalysisResult result;

  /// Whether [result] was computed for the design the tab has loaded now.
  ///
  /// True from the moment a result is installed until the analysis
  /// service reports the loaded netlist changed (`analysisInvalidated`),
  /// which also drops [result]. A current result may still be
  /// [CdcAnalysisResult.isEmpty]: a single-clock design analyses to no
  /// domains worth listing, and that answer is as current as any other.
  final bool hasCurrentResult;

  /// `CdcCrossing.id` of the focused crossing, or null when none.
  final String? selectedCrossingId;

  /// `ClockDomain.id` of the focused domain, or null when none.
  final String? selectedDomainId;

  /// Active severity-filter chip set. Empty means "show none"; a full
  /// set means "show all". The panel toggles individual chips into and
  /// out of this set.
  final Set<CdcSeverity> severityFilter;

  /// When set, the pane lists only the crossings this filter admits.
  final CrossingSignalFilter? signalFilter;

  /// A crossing the pane should scroll into view and briefly flash, or
  /// null when no request is pending. The pane clears it through
  /// [CdcAnalysisNotifier.acknowledgeReveal] once it has answered.
  final String? revealCrossingId;

  /// Convenience lookup for the currently-focused [CdcCrossing].
  CdcCrossing? get selectedCrossing {
    final id = selectedCrossingId;
    if (id == null) return null;
    return result.crossingById(id);
  }

  /// Convenience lookup for the currently-focused [ClockDomain].
  ClockDomain? get selectedDomain {
    final id = selectedDomainId;
    if (id == null) return null;
    return result.domainById(id);
  }

  /// The crossings the pane lists: [result]'s, narrowed by the severity
  /// filter and, when set, the [signalFilter]. Detection order.
  List<CdcCrossing> get visibleCrossings => <CdcCrossing>[
    for (final c in result.detectedCrossings)
      if (severityFilter.contains(c.severity) &&
          (signalFilter?.admits(c.id) ?? true))
        c,
  ];

  /// Returns a copy with the given fields replaced.
  CdcAnalysisState copyWith({
    CdcAnalysisResult? result,
    bool? hasCurrentResult,
    String? selectedCrossingId,
    String? selectedDomainId,
    Set<CdcSeverity>? severityFilter,
    CrossingSignalFilter? signalFilter,
    String? revealCrossingId,
    bool clearSelectedCrossingId = false,
    bool clearSelectedDomainId = false,
    bool clearSignalFilter = false,
    bool clearRevealCrossingId = false,
  }) => CdcAnalysisState(
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
    if (other is! CdcAnalysisState) return false;
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

/// Notifier owning the per-tab [CdcAnalysisState].
///
/// Lives in a per-tab `ProviderContainer` (mirrors FSM / diff / source
/// pane scoping) so each open tab keeps its own analysis result and
/// selection. The hosting `CdcAnalysisPanel` widget reads from and
/// writes to this notifier.
class CdcAnalysisNotifier extends Notifier<CdcAnalysisState> {
  @override
  CdcAnalysisState build() {
    // The active tab's analysis service emits on `analysisInvalidated`
    // whenever the tab re-elaborates (the open-core no-op service uses an
    // empty stream, so this is inert on Open Core builds). Drop the stale
    // result on that signal so an open pane stops showing the previous
    // elaboration's crossings instead of silently retaining them until a
    // manual re-run.
    final service = ref.watch(clockDomainAnalysisServiceProvider);
    final sub = service.analysisInvalidated.listen((_) => _onInvalidated());
    ref.onDispose(sub.cancel);
    // Closing the CDC panel, by any route (its dock tab's close button,
    // the View-menu toggle, a clear action), drops the crossing selection
    // and the signal filter, so no crossing stays painted on a schematic
    // whose panel is gone. The dock is root-scoped workspace chrome and
    // shared by every tab, so each tab's notifier clears its own state.
    ref.listen<List<AnalysisPanelKind>>(analysisDockProvider, (prev, next) {
      final wasOpen = prev?.contains(AnalysisPanelKind.cdc) ?? false;
      if (wasOpen && !next.contains(AnalysisPanelKind.cdc)) _onPanelClosed();
    });
    return CdcAnalysisState.empty;
  }

  /// Clears the stale analysis result and any selections or filters
  /// that referenced it, preserving the user's severity-filter choice.
  void _onInvalidated() {
    if (state.result == CdcAnalysisResult.empty &&
        !state.hasCurrentResult &&
        state.selectedCrossingId == null &&
        state.selectedDomainId == null &&
        state.signalFilter == null) {
      return;
    }
    state = state.copyWith(
      result: CdcAnalysisResult.empty,
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

  /// Installs a freshly-computed [CdcAnalysisResult] and marks it current.
  /// Preserves the currently-selected crossing / domain, the signal
  /// filter and a pending reveal only when the new result contains the
  /// ids they name; otherwise clears them.
  void setResult(CdcAnalysisResult result) {
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

  /// "Show CDC Crossings for This Signal": narrows the pane to
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
    final known = <CdcCrossing>[
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
      severityFilter: <CdcSeverity>{
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
  void toggleSeverity(CdcSeverity severity) {
    final next = Set<CdcSeverity>.from(state.severityFilter);
    if (next.contains(severity)) {
      next.remove(severity);
    } else {
      next.add(severity);
    }
    state = state.copyWith(severityFilter: next);
  }

  /// Replaces the entire severity filter with [filter].
  void setSeverityFilter(Set<CdcSeverity> filter) {
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
  /// severity filter — to [CdcAnalysisState.empty]. The pane returns
  /// to its empty state.
  void reset() {
    state = CdcAnalysisState.empty;
  }
}

/// Per-tab provider exposing the [CdcAnalysisNotifier]. Scoped per-tab
/// via the workspace's `TabContainerManager`, same pattern as FSM /
/// diff / source pane / annotations / X-trace.
final cdcAnalysisStateProvider =
    NotifierProvider<CdcAnalysisNotifier, CdcAnalysisState>(
      CdcAnalysisNotifier.new,
      name: 'cdcAnalysisStateProvider',
    );

// The four derived views below are deliberately top-level functions
// referenced both by the provider definitions here and by the per-tab
// overrides in `netcruxTabOverridesFactory`. Derived providers MUST be
// re-scoped per-tab alongside `cdcAnalysisStateProvider` itself —
// otherwise a tab-scoped consumer's read hoists them to the root
// container, where their `watch` resolves the ROOT analysis state
// instead of the tab's — the recurring per-tab scope-leak class.

/// Body of [perTabCdcAnalysisResultProvider]; also its per-tab override.
CdcAnalysisResult perTabCdcAnalysisResult(Ref ref) =>
    ref.watch(cdcAnalysisStateProvider).result;

/// Body of [selectedCdcCrossingProvider]; also its per-tab override.
CdcCrossing? selectedCdcCrossing(Ref ref) =>
    ref.watch(cdcAnalysisStateProvider).selectedCrossing;

/// Body of [selectedClockDomainProvider]; also its per-tab override.
ClockDomain? selectedClockDomain(Ref ref) =>
    ref.watch(cdcAnalysisStateProvider).selectedDomain;

/// Body of [cdcSeverityFilterProvider]; also its per-tab override.
Set<CdcSeverity> cdcSeverityFilter(Ref ref) =>
    ref.watch(cdcAnalysisStateProvider).severityFilter;

/// Convenience provider exposing only the most-recent
/// [CdcAnalysisResult]. Lets widgets that only care about the result
/// itself (e.g. the panel's domain dropdown) rebuild without re-firing
/// on selection changes.
final perTabCdcAnalysisResultProvider = Provider<CdcAnalysisResult>(
  perTabCdcAnalysisResult,
  name: 'perTabCdcAnalysisResultProvider',
);

/// Convenience provider exposing only the currently-focused crossing
/// (or null). Lets the schematic selection-sync layer listen narrowly
/// to crossing focus changes.
final selectedCdcCrossingProvider = Provider<CdcCrossing?>(
  selectedCdcCrossing,
  name: 'selectedCdcCrossingProvider',
);

/// Convenience provider exposing only the currently-focused clock
/// domain (or null). Lets the panel's domain filter rebuild narrowly.
final selectedClockDomainProvider = Provider<ClockDomain?>(
  selectedClockDomain,
  name: 'selectedClockDomainProvider',
);

/// Convenience provider exposing only the active severity filter set.
final cdcSeverityFilterProvider = Provider<Set<CdcSeverity>>(
  cdcSeverityFilter,
  name: 'cdcSeverityFilterProvider',
);
