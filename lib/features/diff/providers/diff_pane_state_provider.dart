// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:netcrux/domain/models/diff/element_change.dart';
import 'package:netcrux/domain/models/diff/netlist_diff.dart';
import 'package:netcrux/domain/models/diff/netlist_diff_element_kind.dart';
import 'package:netcrux/domain/models/diff/netlist_diff_request.dart';
import 'package:netcrux/services/diff/netlist_diff_service_provider.dart';

/// State held by [DiffPaneStateNotifier] for a single tab's Diff View.
///
/// Encapsulates: the currently-active comparison request (or null
/// when no comparison is loaded), the result of the most recent
/// [NetlistDiffService.compare] call, the set of [ElementChangeKind]s
/// the user has filtered to (empty set means "all kinds"), the set
/// of [NetlistDiffElementKind]s the user has filtered to, the index
/// of the currently-selected change row (used by next/prev
/// navigation and the schematic overlay highlight), and whether the
/// schematic overlay is currently visible.
@immutable
class DiffPaneState {
  /// Creates a diff-pane state snapshot.
  const DiffPaneState({
    this.activeRequest,
    this.activeDiff,
    this.filteredKinds = const <ElementChangeKind>{},
    this.filteredElementKinds = const <NetlistDiffElementKind>{},
    this.selectedChangeIndex,
    this.overlayVisible = true,
    this.isComputing = false,
    this.errorMessage,
  });

  /// Canonical empty state.
  static const DiffPaneState empty = DiffPaneState();

  /// The most recently submitted comparison request. Null until the
  /// user picks a comparison netlist.
  final NetlistDiffRequest? activeRequest;

  /// The result of computing [activeRequest]. Null until the service
  /// finishes; consumers display the [isComputing] / [errorMessage]
  /// state until then.
  final NetlistDiff? activeDiff;

  /// User-selected change-kind filter. Empty means "show all".
  final Set<ElementChangeKind> filteredKinds;

  /// User-selected element-kind filter. Empty means "show all".
  final Set<NetlistDiffElementKind> filteredElementKinds;

  /// Zero-based index into the post-filter change list of the
  /// currently-selected row. Null when nothing is selected.
  final int? selectedChangeIndex;

  /// Whether the schematic overlay (added=green / removed=red /
  /// modified=amber) is currently visible. Default true; the user
  /// can toggle via the panel header.
  final bool overlayVisible;

  /// True while a [NetlistDiffService.compare] call is in flight.
  final bool isComputing;

  /// Non-null when the most recent compare failed. The panel renders
  /// this in the empty-state region; the snackbar surfaces it once at
  /// dispatch time.
  final String? errorMessage;

  /// True when a comparison has been loaded successfully.
  bool get hasActiveDiff =>
      activeDiff != null && activeRequest != null && errorMessage == null;

  /// Filtered view of [activeDiff]'s [NetlistDiff.elementChanges], in the
  /// order the pane lists them: added, removed, modified, unchanged, each
  /// group in the service's order. Navigation steps through this list, so
  /// next / previous walk down the list as the user sees it rather than
  /// jumping between groups. Empty when no diff is active or every change
  /// is filtered out.
  List<ElementChange> get filteredChanges {
    final diff = activeDiff;
    if (diff == null) return const <ElementChange>[];
    return <ElementChange>[
      for (final kind in displayOrder)
        for (final c in diff.elementChanges)
          if (c.kind == kind && _passesFilters(c)) c,
    ];
  }

  /// The order of the pane's groups.
  static const List<ElementChangeKind> displayOrder = <ElementChangeKind>[
    ElementChangeKind.added,
    ElementChangeKind.removed,
    ElementChangeKind.modified,
    ElementChangeKind.unchanged,
  ];

  bool _passesFilters(ElementChange c) {
    if (filteredKinds.isNotEmpty && !filteredKinds.contains(c.kind)) {
      return false;
    }
    if (filteredElementKinds.isNotEmpty &&
        !filteredElementKinds.contains(c.elementKind)) {
      return false;
    }
    return true;
  }

  /// Returns a copy with the given fields replaced. Pass `clear*`
  /// flags to explicitly reset a field to null.
  DiffPaneState copyWith({
    NetlistDiffRequest? activeRequest,
    NetlistDiff? activeDiff,
    Set<ElementChangeKind>? filteredKinds,
    Set<NetlistDiffElementKind>? filteredElementKinds,
    int? selectedChangeIndex,
    bool? overlayVisible,
    bool? isComputing,
    String? errorMessage,
    bool clearActiveRequest = false,
    bool clearActiveDiff = false,
    bool clearSelectedChangeIndex = false,
    bool clearError = false,
  }) {
    return DiffPaneState(
      activeRequest: clearActiveRequest
          ? null
          : (activeRequest ?? this.activeRequest),
      activeDiff: clearActiveDiff ? null : (activeDiff ?? this.activeDiff),
      filteredKinds: filteredKinds ?? this.filteredKinds,
      filteredElementKinds: filteredElementKinds ?? this.filteredElementKinds,
      selectedChangeIndex: clearSelectedChangeIndex
          ? null
          : (selectedChangeIndex ?? this.selectedChangeIndex),
      overlayVisible: overlayVisible ?? this.overlayVisible,
      isComputing: isComputing ?? this.isComputing,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! DiffPaneState) return false;
    if (other.activeRequest != activeRequest) return false;
    if (other.activeDiff != activeDiff) return false;
    if (other.selectedChangeIndex != selectedChangeIndex) return false;
    if (other.overlayVisible != overlayVisible) return false;
    if (other.isComputing != isComputing) return false;
    if (other.errorMessage != errorMessage) return false;
    if (other.filteredKinds.length != filteredKinds.length) return false;
    for (final k in filteredKinds) {
      if (!other.filteredKinds.contains(k)) return false;
    }
    if (other.filteredElementKinds.length != filteredElementKinds.length) {
      return false;
    }
    for (final k in filteredElementKinds) {
      if (!other.filteredElementKinds.contains(k)) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    activeRequest,
    activeDiff,
    Object.hashAllUnordered(filteredKinds),
    Object.hashAllUnordered(filteredElementKinds),
    selectedChangeIndex,
    overlayVisible,
    isComputing,
    errorMessage,
  );
}

/// Notifier owning the per-tab [DiffPaneState].
///
/// Lives in a per-tab `ProviderContainer` (mirrors how
/// [sourcePaneStateProvider] / [annotationStateProvider] /
/// [xTraceResultProvider] are scoped) so each open tab keeps its
/// own active comparison, filters, and selection. The hosting
/// `DiffPanePanel` widget routes file-picker results and "next /
/// prev" navigation into this notifier.
class DiffPaneStateNotifier extends Notifier<DiffPaneState> {
  @override
  DiffPaneState build() {
    // The diff is computed against the baseline elaboration; when the
    // active tab re-elaborates the service emits `diffsInvalidated`
    // (inert on Open Core: the no-op service uses an empty stream). Drop
    // the now-stale comparison so an open Diff pane does not keep showing
    // a diff against the previous baseline until a manual re-run.
    final service = ref.watch(netlistDiffServiceProvider);
    final sub = service.diffsInvalidated.listen((_) {
      if (state != DiffPaneState.empty) state = DiffPaneState.empty;
    });
    ref.onDispose(sub.cancel);
    return DiffPaneState.empty;
  }

  /// Submits a new comparison [request] and computes the diff
  /// through the active [NetlistDiffService]. Drops any prior
  /// result and selection; surfaces [DiffPaneState.errorMessage] on
  /// failure (preserves the previous diff so the panel keeps showing
  /// the last good comparison).
  Future<void> setRequest(NetlistDiffRequest request) async {
    final service = ref.read(netlistDiffServiceProvider);
    state = state.copyWith(
      activeRequest: request,
      isComputing: true,
      clearError: true,
      clearSelectedChangeIndex: true,
    );
    try {
      final diff = await service.compare(request);
      state = state.copyWith(
        activeDiff: diff,
        isComputing: false,
        clearError: true,
        // Auto-select the first change so navigation has somewhere
        // to start.
        selectedChangeIndex: diff.elementChanges.isEmpty ? null : 0,
        clearSelectedChangeIndex: diff.elementChanges.isEmpty,
      );
    } on Object catch (e) {
      state = state.copyWith(isComputing: false, errorMessage: e.toString());
    }
  }

  /// Clears the active comparison, filters, and selection. Returns
  /// the pane to its empty state.
  void clearRequest() {
    state = DiffPaneState.empty;
  }

  /// Re-runs the most recent [setRequest] through the service.
  /// No-op when there is no active request.
  Future<void> refresh() async {
    final req = state.activeRequest;
    if (req == null) return;
    await setRequest(req);
  }

  /// Toggles whether [kind] is in [DiffPaneState.filteredKinds].
  /// Resets the current selection because the post-filter index may
  /// be invalid.
  void toggleKindFilter(ElementChangeKind kind) {
    final next = <ElementChangeKind>{...state.filteredKinds};
    if (!next.add(kind)) next.remove(kind);
    state = state.copyWith(filteredKinds: next, clearSelectedChangeIndex: true);
  }

  /// Toggles whether [elementKind] is in
  /// [DiffPaneState.filteredElementKinds].
  void toggleElementKindFilter(NetlistDiffElementKind elementKind) {
    final next = <NetlistDiffElementKind>{...state.filteredElementKinds};
    if (!next.add(elementKind)) next.remove(elementKind);
    state = state.copyWith(
      filteredElementKinds: next,
      clearSelectedChangeIndex: true,
    );
  }

  /// Selects a specific change row by zero-based index into
  /// [DiffPaneState.filteredChanges]. Clamps to the valid range
  /// when [index] is out of bounds; passing null clears the selection.
  void selectChange(int? index) {
    if (index == null) {
      state = state.copyWith(clearSelectedChangeIndex: true);
      return;
    }
    final maxIndex = state.filteredChanges.length - 1;
    if (maxIndex < 0) {
      state = state.copyWith(clearSelectedChangeIndex: true);
      return;
    }
    final clamped = index.clamp(0, maxIndex);
    state = state.copyWith(selectedChangeIndex: clamped);
  }

  /// Advances [selectedChangeIndex] to the next change row, wrapping
  /// around. No-op when the filtered list is empty.
  void selectNext() {
    final list = state.filteredChanges;
    if (list.isEmpty) return;
    final current = state.selectedChangeIndex;
    final next = current == null ? 0 : (current + 1) % list.length;
    state = state.copyWith(selectedChangeIndex: next);
  }

  /// Advances [selectedChangeIndex] to the previous change row,
  /// wrapping around. No-op when the filtered list is empty.
  void selectPrevious() {
    final list = state.filteredChanges;
    if (list.isEmpty) return;
    final current = state.selectedChangeIndex;
    final prev = current == null
        ? list.length - 1
        : (current - 1 + list.length) % list.length;
    state = state.copyWith(selectedChangeIndex: prev);
  }

  /// Toggles whether the schematic overlay is rendered.
  void toggleOverlay() {
    state = state.copyWith(overlayVisible: !state.overlayVisible);
  }
}

/// Riverpod provider exposing the per-tab [DiffPaneStateNotifier].
///
/// Scoped per-tab via the workspace's [TabContainerManager], same
/// pattern as source pane / annotations / X-trace.
final diffPaneStateProvider =
    NotifierProvider<DiffPaneStateNotifier, DiffPaneState>(
      DiffPaneStateNotifier.new,
      name: 'diffPaneStateProvider',
    );

/// Convenience provider exposing only the currently-active
/// [NetlistDiff] (or null when no comparison is loaded). The
/// schematic overlay watches this directly so it rebuilds only when
/// the diff content changes — not every time a filter chip toggles.
final activeDiffProvider = Provider<NetlistDiff?>(
  (ref) => ref.watch(diffPaneStateProvider).activeDiff,
  name: 'activeDiffProvider',
);
