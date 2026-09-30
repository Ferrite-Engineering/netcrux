// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/models/panel_layout_state.dart';
import 'package:netcrux/features/viewer/providers/panel_layout_provider.dart';

/// The NetCrux four-region IDE layout.
///
/// A thin adapter over the cross-suite [CruxIdeLayout] (from `crux_ide_layout`):
///
/// ```text
/// ┌────────────┬───────────────────────────────┬──────────────┐
/// │ Hierarchy  │                               │   Inspector  │
/// │   Tree     │   Breadcrumb + Schematic      │   (right)    │
/// │  (left)    │   (center)                    │              │
/// │            ├───────────────────────────────┤              │
/// │            │   Diagnostics drawer (bottom) │              │
/// └────────────┴───────────────────────────────┴──────────────┘
/// ```
///
/// The widget is layout-only: each region is a builder slot the caller fills
/// with the actual panel content (hierarchy tree, schematic canvas, inspector,
/// diagnostics drawer).
///
/// Mounted **inside** each tab's content (`ProjectTabContent`), so it lives in
/// the per-tab `UncontrolledProviderScope` the `crux_workspace` `PaneHost`
/// establishes — the hierarchy / inspector / diagnostics panels therefore read
/// the hosting tab's per-tab providers directly. When the workspace has zero
/// tabs, `PaneHost` renders the empty-canvas state instead and no layout (and
/// so no pane separator) is mounted — matching WaveCrux / LintCrux / SimCrux.
///
/// Visibility and pixel sizes are projected from the shared
/// [panelLayoutProvider] onto the shared widget via [_NetcruxIdePanelLayout] +
/// [_NetcruxIdePanelLayoutSink]; `CruxIdeLayout` owns the `IdeController`, the
/// resizer theme, and the bidirectional visibility/size sync that persists
/// drag-to-resize / drag-to-collapse back through the notifier.
class NetcruxIdeLayout extends ConsumerWidget {
  /// Creates a [NetcruxIdeLayout]. All four region builders are required so
  /// the layout is never empty.
  const NetcruxIdeLayout({
    required this.hierarchyBuilder,
    required this.centerBuilder,
    required this.inspectorBuilder,
    required this.diagnosticsBuilder,
    super.key,
  });

  /// Builder for the left hierarchy-tree pane.
  final IdePaneBuilder hierarchyBuilder;

  /// Builder for the center breadcrumb + schematic-canvas region.
  final IdePaneBuilder centerBuilder;

  /// Builder for the right inspector pane.
  final IdePaneBuilder inspectorBuilder;

  /// Builder for the bottom diagnostics-drawer pane.
  final IdePaneBuilder diagnosticsBuilder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(panelLayoutProvider);
    final notifier = ref.read(panelLayoutProvider.notifier);
    // No analysis-dock special case anymore: the right region is a tabbed
    // dock (NetcruxRightDock), `inspectorVisible` is its one visibility
    // flag, and drag-to-collapse hides the region — a docked analysis stays
    // listed as a tab for when it reopens. The old forced-visible +
    // "drag closes the dock, not the inspector" guesswork dissolved with
    // the priority chain that needed it.
    return CruxIdeLayout(
      layout: _NetcruxIdePanelLayout(state),
      sink: _NetcruxIdePanelLayoutSink(notifier),
      // Floors for every region, matching WaveCrux's and SimCrux's. NetCrux
      // passed none, so any divider could be dragged clear across the window
      // and the region behind it had no way to say no — the diagnostics
      // drawer's in particular could take the whole schematic, leaving
      // nothing to aim the drag back at.
      leftMinSize: PaneSize.pixel(160),
      rightMinSize: PaneSize.pixel(200),
      bottomMinSize: PaneSize.pixel(80),
      // The canvas gives 14 px per axis back to the scrollbar bands, so 160
      // still leaves a schematic worth looking at.
      centerMinSize: PaneSize.pixel(160),
      leftBuilder: hierarchyBuilder,
      centerBuilder: centerBuilder,
      rightBuilder: inspectorBuilder,
      bottomBuilder: diagnosticsBuilder,
    );
  }
}

/// Read-side adapter: NetCrux's [PanelLayoutState] → [IdePanelLayout]
/// (hierarchy→left, inspector→right, diagnostics→bottom; pixel sizes).
class _NetcruxIdePanelLayout implements IdePanelLayout {
  const _NetcruxIdePanelLayout(this._state);

  final PanelLayoutState _state;

  @override
  bool get leftVisible => _state.hierarchyTreeVisible;

  @override
  PaneSize? get leftSize => _state.hierarchyTreeWidth != null
      ? PaneSize.pixel(_state.hierarchyTreeWidth!)
      : null;

  @override
  bool get rightVisible => _state.inspectorVisible;

  @override
  PaneSize? get rightSize => _state.inspectorWidth != null
      ? PaneSize.pixel(_state.inspectorWidth!)
      : null;

  @override
  bool get bottomVisible => _state.diagnosticsVisible;

  @override
  PaneSize? get bottomSize => _state.diagnosticsHeight != null
      ? PaneSize.pixel(_state.diagnosticsHeight!)
      : null;
}

/// Write-side adapter: drag-to-collapse / drag-to-resize → the NetCrux
/// [PanelLayoutNotifier], which persists via the settings codec.
class _NetcruxIdePanelLayoutSink implements IdePanelLayoutSink {
  const _NetcruxIdePanelLayoutSink(this._notifier);

  final PanelLayoutNotifier _notifier;

  @override
  void setLeftVisible({required bool visible}) =>
      unawaited(_notifier.setHierarchyTreeVisible(visible: visible));

  @override
  void setRightVisible({required bool visible}) =>
      unawaited(_notifier.setInspectorVisible(visible: visible));

  @override
  void setBottomVisible({required bool visible}) =>
      unawaited(_notifier.setDiagnosticsVisible(visible: visible));

  @override
  void setLeftSize(double pixels) =>
      unawaited(_notifier.setHierarchyTreeWidth(pixels));

  @override
  void setRightSize(double pixels) =>
      unawaited(_notifier.setInspectorWidth(pixels));

  @override
  void setBottomSize(double pixels) =>
      unawaited(_notifier.setDiagnosticsHeight(pixels));
}
