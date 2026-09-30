// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/domain/models/selection/selection.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'selected_element_notifier.g.dart';

/// Per-canvas multi-selection state.
///
/// Holds the current [Selection] (zero, one, or many elements with a
/// [Selection.primary] anchor). Modifier-key click semantics from the
/// gesture handler:
///
/// - Plain click → [select] (replaces with a single element)
/// - Shift-click → [addToSelection] (adds + anchors primary)
/// - Cmd/Ctrl-click → [toggleInSelection] (adds or removes)
/// - Esc → [clear]
///
/// Declared at root and re-bound per tab by `netcrux_tab_overrides.dart`,
/// so every tab keeps its own selection (mirrors WaveCrux).
@Riverpod(keepAlive: true)
class SelectedElementNotifier extends _$SelectedElementNotifier {
  @override
  Selection build() => Selection.empty;

  /// Replaces the current selection with a single-element selection
  /// containing [element]. Plain (no-modifier) click. Selecting the
  /// none sentinel clears the selection.
  void select(SelectedElement element) {
    final next = Selection.single(element);
    if (state == next) return;
    state = next;
  }

  /// Replaces the current selection with [selection] verbatim. Used
  /// by the session restore path to install a previously-persisted
  /// selection without re-running the gesture-handler dispatch.
  void replace(Selection selection) {
    if (state == selection) return;
    state = selection;
  }

  /// Toggles [element] in the selection — adds it if absent, removes
  /// it if present. Cmd/Ctrl-click semantics. Promotes [element] to
  /// primary when added.
  void toggleInSelection(SelectedElement element) {
    final next = state.toggleElement(element);
    if (state == next) return;
    state = next;
  }

  /// Adds [element] to the selection without removing existing
  /// elements. Shift-click semantics. Promotes [element] to primary
  /// even when already present (so the inspector follows the click).
  void addToSelection(SelectedElement element) {
    final next = state.addElement(element);
    if (state == next) return;
    state = next;
  }

  /// Drops the selection back to empty. Wired to Esc and to scope
  /// changes (the breadcrumb push/pop clears the previous scope's
  /// selection because the cell ids no longer resolve).
  void clear() {
    if (state.isEmpty) return;
    state = Selection.empty;
  }
}
