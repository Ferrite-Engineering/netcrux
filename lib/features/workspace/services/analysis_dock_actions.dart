// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/models/analysis/analysis_panel_kind.dart';
import 'package:netcrux/features/viewer/providers/analysis_dock_provider.dart';
import 'package:netcrux/features/viewer/providers/panel_layout_provider.dart';
import 'package:netcrux/features/viewer/providers/right_dock_provider.dart';
import 'package:netcrux/features/workspace/widgets/netcrux_docks.dart';

/// Opens (or refocuses) the right dock on [kind]. Bound to the tail of the
/// run-analysis flows and the scoped "show crossings for signal" flows —
/// those must always end with the panel visible.
///
/// A first-run nicety: when the right pane is still at (or below) its
/// narrow inspector default, it is widened to [_comfortableDockWidth] so
/// the panel opens readable instead of mostly clipped. A user-dragged wider
/// width is left alone, and any width the user sets afterwards persists as
/// usual.
///
/// `analysisDockProvider` is root-scoped workspace chrome; per-tab
/// containers are parented to the root container, so opening and closing
/// resolve the same instance from any context.
void openAnalysisDock(BuildContext context, AnalysisPanelKind kind) {
  final container = ProviderScope.containerOf(context, listen: false);
  final layout = container.read(panelLayoutProvider);
  if ((layout.inspectorWidth ?? 0) < _comfortableDockWidth) {
    unawaited(
      container
          .read(panelLayoutProvider.notifier)
          .setInspectorWidth(_comfortableDockWidth),
    );
  }
  container.read(analysisDockProvider.notifier).open(kind);
}

/// Right-pane width the dock widens to on open when the pane is
/// narrower. Wide enough for the panels' list rows to read well, while
/// leaving most of a desktop window to the schematic.
const double _comfortableDockWidth = 420;

/// View-menu / palette toggle semantics for the "show pane" actions: a
/// second invocation closes that panel — that panel only, under multi-open.
void toggleAnalysisDock(BuildContext context, AnalysisPanelKind kind) {
  final container = ProviderScope.containerOf(context, listen: false);
  if (container.read(analysisDockProvider).contains(kind)) {
    container.read(analysisDockProvider.notifier).close(kind);
    return;
  }
  openAnalysisDock(context, kind);
}

/// The Annotations "show panel" semantics: opens [kind] when it
/// is closed, brings it to the front when it is open behind another tab,
/// and closes it when it is already the tab on screen. So the View-menu
/// entry works as a toggle without ever closing a panel the user cannot
/// see.
void focusOrToggleAnalysisDock(BuildContext context, AnalysisPanelKind kind) {
  final container = ProviderScope.containerOf(context, listen: false);
  if (_isOnScreen(container, kind)) {
    container.read(analysisDockProvider.notifier).close(kind);
    return;
  }
  final id = analysisDockTabId(kind);
  if (container.read(analysisDockProvider).contains(kind) &&
      container.read(dockPlacementsProvider)[id] == kDockRegionBottom) {
    container.read(bottomDockTabProvider.notifier).reveal(id);
    return;
  }
  openAnalysisDock(context, kind);
}

/// Whether [kind]'s tab is open, frontmost in its dock, and that dock is
/// showing.
bool _isOnScreen(ProviderContainer container, AnalysisPanelKind kind) {
  if (!container.read(analysisDockProvider).contains(kind)) return false;
  final id = analysisDockTabId(kind);
  final layout = container.read(panelLayoutProvider);
  if (container.read(dockPlacementsProvider)[id] == kDockRegionBottom) {
    return layout.diagnosticsVisible &&
        container.read(bottomDockTabProvider) == id;
  }
  return layout.inspectorVisible &&
      container.read(effectiveRightDockTabProvider) == id;
}

/// Closes [kind] only, when open — the clear-selection actions use this so
/// clearing, say, the FSM focus never dismisses a CDC panel the user is
/// looking at. Under multi-open this is precise: it removes exactly that
/// panel's tab, never anything else.
void closeAnalysisDockIfShowing(BuildContext context, AnalysisPanelKind kind) {
  ProviderScope.containerOf(
    context,
    listen: false,
  ).read(analysisDockProvider.notifier).close(kind);
}
