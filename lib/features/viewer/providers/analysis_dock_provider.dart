// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/models/analysis/analysis_panel_kind.dart';
import 'package:netcrux/features/viewer/providers/right_dock_provider.dart';

/// The analysis panels currently open in the right dock, in the order they
/// were opened — one dock tab each. Empty when no analysis is docked.
///
/// Root-scoped on purpose — the dock is workspace chrome, exactly like the
/// hierarchy / inspector / diagnostics visibility in `panelLayoutProvider`:
/// every tab shows the same dock choice, while the panel *content* mounted
/// inside the per-tab IDE layout reads that tab's per-tab analysis state.
/// Per-tab containers are parented to the root container, so a watch from
/// inside a tab scope resolves this root instance.
///
/// Session-only (not persisted): an analysis panel with no analysis result
/// is an empty explainer, so re-opening the dock on launch would add chrome
/// without content.
///
/// Multi-open by design: the single-slot model predates the tabbed dock —
/// with a strip to list them, holding CDC and the diff open side by side is
/// exactly what tabs are for.
class AnalysisDockNotifier extends Notifier<List<AnalysisPanelKind>> {
  @override
  List<AnalysisPanelKind> build() => const [];

  /// Whether [kind] is currently open.
  bool isOpen(AnalysisPanelKind kind) => state.contains(kind);

  /// Opens (or refocuses) [kind], revealing its right-dock tab — opening an
  /// analysis both lists it and brings it frontmost, opening the right
  /// region if hidden.
  void open(AnalysisPanelKind kind) {
    if (!state.contains(kind)) state = [...state, kind];
    ref.read(rightDockTabProvider.notifier).reveal(analysisDockTabId(kind));
  }

  /// Closes [kind] (only). Other open analyses keep their tabs; the right
  /// dock falls back per `effectiveRightDockTabProvider` when the closed
  /// tab was frontmost.
  void close(AnalysisPanelKind kind) {
    if (!state.contains(kind)) return;
    state = [
      for (final k in state)
        if (k != kind) k,
    ];
  }

  /// Closes every open analysis (the right dock falls back to the
  /// inspector / cross-probe).
  void closeAll() {
    if (state.isEmpty) return;
    state = const [];
  }

  /// Toggle semantics for the View-menu / palette "show pane" actions: a
  /// second invocation of the action that opened [kind] closes it — that
  /// panel only, under multi-open.
  void toggle(AnalysisPanelKind kind) {
    if (state.contains(kind)) {
      close(kind);
    } else {
      open(kind);
    }
  }
}

/// The analysis dock's open-panel list. See [AnalysisDockNotifier].
final analysisDockProvider =
    NotifierProvider<AnalysisDockNotifier, List<AnalysisPanelKind>>(
      AnalysisDockNotifier.new,
      name: 'analysisDockProvider',
    );

/// Builds the docked panel widget for [kind].
///
/// The widget is mounted inside the active tab's provider scope (the
/// right slot of the per-tab `NetcruxIdeLayout`), so it can read the
/// tab's per-tab analysis state directly — no re-scoping wrapper.
typedef AnalysisPanelBuilder =
    Widget Function(BuildContext context, AnalysisPanelKind kind);

/// Open-core extension point supplying the docked analysis panel
/// widgets. `null` on open-core builds — the dock never opens there
/// because every analysis opener is a no-op, and the dock host falls
/// back to the inspector should the state be set anyway.
final analysisPanelBuilderProvider = Provider<AnalysisPanelBuilder?>(
  (_) => null,
  name: 'analysisPanelBuilderProvider',
);
