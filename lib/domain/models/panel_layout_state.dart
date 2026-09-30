// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// Visibility and size state for the three NetCrux viewer side panels.
///
/// The viewer is a four-region IDE-style layout (hierarchy tree left,
/// schematic canvas center, inspector right, diagnostics drawer bottom).
/// This model is the source of truth for which side panels are visible and
/// at what size; the `IdeLayout` widget and the `IdeController` it owns are
/// driven from this state via the bidirectional sync in `NetcruxIdeLayout`.
///
/// Sizes are stored as logical pixels because `panes.PaneSize` is not a
/// pure-Dart type and would pull a Flutter import into the domain layer.
/// `null` for any size field means "use the panes default", which is what
/// `IdeController` configures via its constructor defaults.
///
/// Mirrors the LintCrux / SimCrux / WaveCrux `PanelLayoutState` design (same
/// field shape, same `copyWith` / `==` / `hashCode` contract) so the four
/// products share one workspace-shell model. The defaults preserve NetCrux's
/// historical launch experience: the hierarchy tree is docked, the inspector
/// and diagnostics drawer start collapsed and are opened on demand from the
/// View menu / command palette.
@immutable
class PanelLayoutState {
  /// Creates a [PanelLayoutState]. The defaults match NetCrux's
  /// open-on-launch experience: hierarchy tree visible, inspector and
  /// diagnostics drawer collapsed.
  const PanelLayoutState({
    this.hierarchyTreeVisible = true,
    this.inspectorVisible = false,
    this.diagnosticsVisible = false,
    this.hierarchyTreeWidth,
    this.inspectorWidth,
    this.diagnosticsHeight,
  });

  /// Whether the left hierarchy-tree pane is visible.
  final bool hierarchyTreeVisible;

  /// Whether the right inspector pane is visible.
  final bool inspectorVisible;

  /// Whether the bottom diagnostics-drawer pane is visible.
  final bool diagnosticsVisible;

  /// Logical-pixel width of the hierarchy-tree pane. `null` ⇒ panes default.
  final double? hierarchyTreeWidth;

  /// Logical-pixel width of the inspector pane. `null` ⇒ panes default.
  final double? inspectorWidth;

  /// Logical-pixel height of the diagnostics pane. `null` ⇒ panes default.
  final double? diagnosticsHeight;

  /// Returns a copy with overridden fields. To explicitly clear a `?`-typed
  /// size field, pass the corresponding `clear*` flag — the standard
  /// `field: null` convention means "don't touch" in `copyWith`.
  PanelLayoutState copyWith({
    bool? hierarchyTreeVisible,
    bool? inspectorVisible,
    bool? diagnosticsVisible,
    double? hierarchyTreeWidth,
    double? inspectorWidth,
    double? diagnosticsHeight,
    bool clearHierarchyTreeWidth = false,
    bool clearInspectorWidth = false,
    bool clearDiagnosticsHeight = false,
  }) {
    return PanelLayoutState(
      hierarchyTreeVisible: hierarchyTreeVisible ?? this.hierarchyTreeVisible,
      inspectorVisible: inspectorVisible ?? this.inspectorVisible,
      diagnosticsVisible: diagnosticsVisible ?? this.diagnosticsVisible,
      hierarchyTreeWidth: clearHierarchyTreeWidth
          ? null
          : (hierarchyTreeWidth ?? this.hierarchyTreeWidth),
      inspectorWidth: clearInspectorWidth
          ? null
          : (inspectorWidth ?? this.inspectorWidth),
      diagnosticsHeight: clearDiagnosticsHeight
          ? null
          : (diagnosticsHeight ?? this.diagnosticsHeight),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PanelLayoutState &&
        other.hierarchyTreeVisible == hierarchyTreeVisible &&
        other.inspectorVisible == inspectorVisible &&
        other.diagnosticsVisible == diagnosticsVisible &&
        other.hierarchyTreeWidth == hierarchyTreeWidth &&
        other.inspectorWidth == inspectorWidth &&
        other.diagnosticsHeight == diagnosticsHeight;
  }

  @override
  int get hashCode => Object.hash(
    hierarchyTreeVisible,
    inspectorVisible,
    diagnosticsVisible,
    hierarchyTreeWidth,
    inspectorWidth,
    diagnosticsHeight,
  );

  @override
  String toString() =>
      'PanelLayoutState('
      'hierarchyTreeVisible: $hierarchyTreeVisible, '
      'inspectorVisible: $inspectorVisible, '
      'diagnosticsVisible: $diagnosticsVisible, '
      'hierarchyTreeWidth: $hierarchyTreeWidth, '
      'inspectorWidth: $inspectorWidth, '
      'diagnosticsHeight: $diagnosticsHeight)';
}
