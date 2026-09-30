// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:netcrux/domain/models/panel_layout_state.dart';
import 'package:netcrux/features/settings/providers/app_settings_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'panel_layout_provider.g.dart';

/// Active panel-layout state for the workspace IDE layout.
///
/// Shared across every tab (root-scoped — never overridden per tab), so the
/// hierarchy / inspector / diagnostics panels behave the same in whichever
/// tab is focused. This mirrors the single-`IdeController` model NetCrux had
/// before the per-tab `IdeLayout` move, and matches the LintCrux / SimCrux
/// shared-panel-layout convention.
///
/// External callers (View-menu items, keyboard shortcuts, the command
/// palette) drive the layout through the toggle / set methods; each per-tab
/// [`NetcruxIdeLayout`] bidirectionally syncs its underlying
/// `panes.IdeController`:
///
/// - drag-to-resize fires `setHierarchyTreeWidth` / `setInspectorWidth` /
///   `setDiagnosticsHeight` via `IdeLayout.onSizeChanged`.
/// - drag-to-collapse fires the `set*Visible` mutators via
///   `IdeLayout.onPaneStateChanged`.
/// - programmatic toggles are re-applied onto every mounted `IdeController`
///   via `ref.listen`.
///
/// Initial state is seeded from the persisted [`AppSettings.panelLayout`] the
/// moment settings finish loading; until then callers see the model defaults
/// so the first frame is stable. Every mutation is mirrored back to disk via
/// [`AppSettingsNotifier.updatePanelLayout`].
@Riverpod(keepAlive: true)
class PanelLayoutNotifier extends _$PanelLayoutNotifier {
  @override
  PanelLayoutState build() {
    final settings = ref.watch(appSettingsProvider);
    return settings.maybeWhen(
      data: (loaded) => loaded.panelLayout,
      orElse: () => const PanelLayoutState(),
    );
  }

  /// Toggles the visibility of the left hierarchy-tree pane.
  Future<void> toggleHierarchyTree() async {
    await _update(
      state.copyWith(hierarchyTreeVisible: !state.hierarchyTreeVisible),
    );
  }

  /// Toggles the visibility of the right inspector pane.
  Future<void> toggleInspector() async {
    await _update(
      state.copyWith(inspectorVisible: !state.inspectorVisible),
    );
  }

  /// Toggles the visibility of the bottom diagnostics-drawer pane.
  Future<void> toggleDiagnostics() async {
    await _update(
      state.copyWith(diagnosticsVisible: !state.diagnosticsVisible),
    );
  }

  /// Sets the hierarchy-tree visibility explicitly. Used by the
  /// `IdeController`→state sync to mirror user drag-to-collapse actions.
  Future<void> setHierarchyTreeVisible({required bool visible}) async {
    await _update(state.copyWith(hierarchyTreeVisible: visible));
  }

  /// Sets the inspector visibility explicitly.
  Future<void> setInspectorVisible({required bool visible}) async {
    await _update(state.copyWith(inspectorVisible: visible));
  }

  /// Sets the diagnostics-drawer visibility explicitly.
  Future<void> setDiagnosticsVisible({required bool visible}) async {
    await _update(state.copyWith(diagnosticsVisible: visible));
  }

  /// Sets the hierarchy-tree pane width (logical pixels). Driven by the
  /// `IdeController`'s drag-resize callback so user drag persists across
  /// launches via the settings codec.
  Future<void> setHierarchyTreeWidth(double width) async {
    await _update(state.copyWith(hierarchyTreeWidth: width));
  }

  /// Sets the inspector pane width (logical pixels).
  Future<void> setInspectorWidth(double width) async {
    await _update(state.copyWith(inspectorWidth: width));
  }

  /// Sets the diagnostics pane height (logical pixels).
  Future<void> setDiagnosticsHeight(double height) async {
    await _update(state.copyWith(diagnosticsHeight: height));
  }

  /// Applies [next], persisting the change to disk via the settings
  /// notifier. The in-memory state is the source of truth; persistence is a
  /// side effect, not a guard. A no-op identity check short-circuits a
  /// redundant rebuild + write when nothing changed.
  Future<void> _update(PanelLayoutState next) async {
    if (next == state) return;
    state = next;
    await ref.read(appSettingsProvider.notifier).updatePanelLayout(next);
  }
}
