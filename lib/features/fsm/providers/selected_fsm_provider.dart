// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/models/fsm/fsm.dart';
import 'package:netcrux/domain/models/fsm/fsm_state.dart';
import 'package:netcrux/services/fsm/fsm_detection_service_provider.dart';

/// Per-tab snapshot of the FSM Bubble Diagram pane's selection state.
///
/// Holds:
///   * The currently-focused [Fsm] (or null when no FSM is open).
///   * The currently-highlighted [FsmState] within that FSM (or null
///     when nothing is highlighted — the diagram still renders, the
///     reset state shows its default highlight only).
///   * User-arranged bubble positions keyed by `FsmState.id`. The
///     bubble diagram persists these so re-opening the same FSM
///     remembers the user's layout; per-tab scoping keeps each tab's
///     arrangement independent.
@immutable
class SelectedFsmState {
  /// Creates a snapshot.
  const SelectedFsmState({
    this.fsm,
    this.selectedStateId,
    this.bubblePositions = const <String, Offset>{},
  });

  /// Canonical empty snapshot.
  static const SelectedFsmState empty = SelectedFsmState();

  /// The currently-focused FSM, or null when none is open.
  final Fsm? fsm;

  /// `FsmState.id` of the highlighted state within [fsm], or null
  /// when nothing is highlighted. Distinct from "no FSM open" — the
  /// diagram can render with no highlight (the reset state's outline
  /// is sufficient guidance).
  final String? selectedStateId;

  /// User-arranged bubble positions for the currently-focused FSM.
  /// Keys are `FsmState.id`; values are local-to-canvas offsets in
  /// logical pixels. Missing entries fall back to the layout
  /// algorithm's computed position.
  final Map<String, Offset> bubblePositions;

  /// True when an FSM is currently focused. The bubble diagram
  /// renders empty when this is false.
  bool get hasFsm => fsm != null;

  /// Convenience lookup for the currently-highlighted [FsmState].
  /// Returns null when there is no current FSM, no current selection,
  /// or the selection points at a state that no longer exists in the
  /// FSM (e.g. after a re-detect).
  FsmState? get selectedState {
    final f = fsm;
    final id = selectedStateId;
    if (f == null || id == null) return null;
    return f.stateById(id);
  }

  /// Returns a copy with the given fields replaced. Pass `clear*`
  /// flags to reset a field to null / empty explicitly.
  SelectedFsmState copyWith({
    Fsm? fsm,
    String? selectedStateId,
    Map<String, Offset>? bubblePositions,
    bool clearFsm = false,
    bool clearSelectedStateId = false,
    bool clearBubblePositions = false,
  }) => SelectedFsmState(
    fsm: clearFsm ? null : (fsm ?? this.fsm),
    selectedStateId: clearSelectedStateId
        ? null
        : (selectedStateId ?? this.selectedStateId),
    bubblePositions: clearBubblePositions
        ? const <String, Offset>{}
        : (bubblePositions ?? this.bubblePositions),
  );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! SelectedFsmState) return false;
    if (fsm != other.fsm) return false;
    if (selectedStateId != other.selectedStateId) return false;
    if (bubblePositions.length != other.bubblePositions.length) return false;
    for (final entry in bubblePositions.entries) {
      if (other.bubblePositions[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode {
    var hash = Object.hash(fsm, selectedStateId);
    for (final entry in bubblePositions.entries) {
      hash ^= Object.hash(entry.key, entry.value);
    }
    return hash;
  }
}

/// Notifier owning the per-tab [SelectedFsmState].
///
/// Lives in a per-tab `ProviderContainer` (mirrors source pane / diff
/// pane / bookmarks scoping) so each open tab keeps its own focused
/// FSM, highlighted state, and bubble-position layout. The hosting
/// `FsmBubbleDiagramPanel` widget reads from and writes to this
/// notifier.
class SelectedFsmNotifier extends Notifier<SelectedFsmState> {
  @override
  SelectedFsmState build() {
    // Drop the focused FSM when the active tab re-elaborates (inert on
    // Open Core: the no-op service uses an empty invalidation stream) —
    // the FSM belongs to the previous elaboration and its state ids may
    // no longer exist, so an open bubble diagram must not keep rendering
    // it until a manual re-detect.
    final service = ref.watch(fsmDetectionServiceProvider);
    final sub = service.detectionInvalidated.listen((_) {
      if (state != SelectedFsmState.empty) state = SelectedFsmState.empty;
    });
    ref.onDispose(sub.cancel);
    return SelectedFsmState.empty;
  }

  /// Focuses [fsm] in the bubble diagram. Clears any prior highlight
  /// and any bubble-position layout — the new FSM gets a fresh layout
  /// the diagram's force-directed algorithm will compute on first
  /// paint.
  void focusFsm(Fsm fsm) {
    state = SelectedFsmState(fsm: fsm);
  }

  /// Updates the focused FSM's structure (e.g. after a re-detect)
  /// while preserving the existing highlight and bubble positions
  /// where the state ids still exist. State ids absent from the new
  /// FSM have their positions dropped; the highlight is dropped if
  /// the highlighted state is no longer present.
  void updateFsm(Fsm fsm) {
    final newIds = <String>{for (final s in fsm.states) s.id};
    final keepPositions = <String, Offset>{
      for (final entry in state.bubblePositions.entries)
        if (newIds.contains(entry.key)) entry.key: entry.value,
    };
    final keepSelected =
        state.selectedStateId != null && newIds.contains(state.selectedStateId)
        ? state.selectedStateId
        : null;
    state = SelectedFsmState(
      fsm: fsm,
      selectedStateId: keepSelected,
      bubblePositions: keepPositions,
    );
  }

  /// Highlights the state with id [stateId] (which must be a
  /// `FsmState.id` in the currently-focused FSM). Pass null to clear
  /// the highlight.
  void highlightState(String? stateId) {
    if (stateId == null) {
      state = state.copyWith(clearSelectedStateId: true);
      return;
    }
    if (state.fsm == null) return;
    if (state.fsm!.stateById(stateId) == null) return;
    state = state.copyWith(selectedStateId: stateId);
  }

  /// Records a user-arranged bubble position for [stateId]. Stored
  /// per-tab in this notifier so the layout survives panel close /
  /// reopen within the tab's lifetime.
  void setBubblePosition(String stateId, Offset offset) {
    if (state.fsm == null) return;
    if (state.fsm!.stateById(stateId) == null) return;
    final next = <String, Offset>{...state.bubblePositions, stateId: offset};
    state = state.copyWith(bubblePositions: next);
  }

  /// Clears the focused FSM, the highlight, and the bubble-position
  /// layout. The bubble diagram returns to its empty state.
  void clear() {
    state = SelectedFsmState.empty;
  }
}

/// Per-tab provider exposing the [SelectedFsmNotifier].
///
/// Scoped per-tab via the workspace's [TabContainerManager], same
/// pattern as diff pane / source pane / bookmarks / X-trace.
final selectedFsmProvider =
    NotifierProvider<SelectedFsmNotifier, SelectedFsmState>(
      SelectedFsmNotifier.new,
      name: 'selectedFsmProvider',
    );

/// Convenience provider exposing only the currently-focused [Fsm]
/// (or null when none is open). Lets widgets that only care about
/// the FSM structure rebuild without re-firing on highlight changes.
final activeFsmProvider = Provider<Fsm?>(
  (ref) => ref.watch(selectedFsmProvider).fsm,
  name: 'activeFsmProvider',
);

/// Convenience provider exposing only the currently-highlighted
/// [FsmState] (or null). Lets the schematic selection-sync layer
/// listen narrowly to the highlight without re-firing on bubble
/// position changes.
final selectedFsmStateProvider = Provider<FsmState?>(
  (ref) => ref.watch(selectedFsmProvider).selectedState,
  name: 'selectedFsmStateProvider',
);
