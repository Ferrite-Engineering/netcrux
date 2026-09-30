// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';

/// Immutable multi-selection value.
///
/// Holds the unordered [elements] currently selected on the schematic
/// canvas plus a [primary] pointer identifying the element the
/// inspector and the context-menu actions act on. The primary is
/// always either `none` (when [elements] is empty) or one of the
/// elements in [elements].
///
/// Modifier-key semantics mirror Finder / VS Code:
///
/// - Plain click → [Selection.single]
/// - Shift-click → [addElement] (additive)
/// - Cmd/Ctrl-click → [toggleElement]
/// - Esc → [Selection.empty]
///
/// The painter highlights every element in [elements]; the primary
/// element is rendered with the dedicated "primary selection" accent
/// (slightly brighter / thicker), while secondary selections render
/// with the standard accent. This matches WaveCrux's signal-list
/// multi-select model and is how a future right-click context menu
/// can answer "which element did the user mean?" — always [primary].
@immutable
class Selection {
  /// Creates a selection containing [elements] with [primary] as the
  /// inspector / context-menu anchor. Callers should prefer the
  /// [Selection.empty], [Selection.single], or one of the mutation
  /// helpers ([addElement], [toggleElement], [withPrimary]) instead
  /// of using this constructor directly — it does not validate that
  /// [primary] is in [elements].
  const Selection({
    required this.elements,
    required this.primary,
  });

  /// Selection containing only [element] (which is also the primary).
  /// Equivalent to a plain (non-modifier) click.
  factory Selection.single(SelectedElement element) {
    if (element.isNone) return Selection.empty;
    return Selection(
      elements: {element},
      primary: element,
    );
  }

  /// Empty selection — nothing highlighted, primary is the none
  /// sentinel. Const-friendly so widgets can use `Selection.empty`
  /// as a default without allocating.
  static const Selection empty = Selection(
    elements: <SelectedElement>{},
    primary: SelectedElement.none(),
  );

  /// Every selected element. Order is not meaningful; consumers that
  /// need a stable order use the insertion order of [elements] as a
  /// best-effort cue, but no widget depends on it.
  final Set<SelectedElement> elements;

  /// The anchor element for the inspector and context-menu actions.
  /// Always [SelectedElement.none] when [elements] is empty, and
  /// always a member of [elements] otherwise.
  final SelectedElement primary;

  /// True when no elements are selected.
  bool get isEmpty => elements.isEmpty;

  /// True when at least one element is selected.
  bool get isNotEmpty => elements.isNotEmpty;

  /// Number of selected elements.
  int get length => elements.length;

  /// True when [element] is in [elements].
  bool contains(SelectedElement element) => elements.contains(element);

  /// True when [element] equals [primary].
  bool isPrimary(SelectedElement element) => primary == element;

  /// Returns a new selection with [element] added. When [element] is
  /// already in [elements] the existing selection is returned with
  /// [element] promoted to primary (shift-click on an already-selected
  /// element re-anchors the primary; nothing is removed). When
  /// [element] is [SelectedElement.none] the selection is returned
  /// unchanged.
  Selection addElement(SelectedElement element) {
    if (element.isNone) return this;
    if (contains(element)) {
      if (primary == element) return this;
      return Selection(elements: elements, primary: element);
    }
    return Selection(
      elements: <SelectedElement>{...elements, element},
      primary: element,
    );
  }

  /// Returns a new selection with [element] toggled. If it's already
  /// selected it is removed; if not, it is added and promoted to
  /// primary. When the removed element was the primary, the primary
  /// becomes the most recently added remaining element (best-effort —
  /// the set is unordered, so we pick `elements.last`), or none.
  /// [SelectedElement.none] is a no-op.
  Selection toggleElement(SelectedElement element) {
    if (element.isNone) return this;
    if (contains(element)) {
      final remaining = <SelectedElement>{...elements}..remove(element);
      if (remaining.isEmpty) return Selection.empty;
      final newPrimary = primary == element ? remaining.last : primary;
      return Selection(elements: remaining, primary: newPrimary);
    }
    return Selection(
      elements: <SelectedElement>{...elements, element},
      primary: element,
    );
  }

  /// Returns a copy with [primary] changed to [element]. Caller is
  /// responsible for ensuring [element] is in [elements]; passing
  /// [SelectedElement.none] is allowed and produces an empty selection
  /// regardless of the current state.
  Selection withPrimary(SelectedElement element) {
    if (element.isNone) return Selection.empty;
    if (!elements.contains(element)) {
      return Selection(
        elements: <SelectedElement>{...elements, element},
        primary: element,
      );
    }
    if (primary == element) return this;
    return Selection(elements: elements, primary: element);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Selection) return false;
    if (other.primary != primary) return false;
    if (other.elements.length != elements.length) return false;
    for (final element in elements) {
      if (!other.elements.contains(element)) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    primary,
    Object.hashAllUnordered(elements),
  );

  @override
  String toString() =>
      'Selection(primary=$primary, elements=${elements.length})';
}
