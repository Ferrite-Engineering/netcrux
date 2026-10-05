// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens / focuses the RTL source pane.
///
/// Default is a no-op so [NetcruxAction.showSourcePane] remains
/// discoverable in the command palette / menu bar on open-core
/// builds. The Pro overlay overrides this with a callback that opens
/// the panel as the right dock's Source tab
/// (`AnalysisPanelKind.source`), or brings that tab to the front when
/// it is already open.
typedef ShowSourcePaneOpener = void Function(BuildContext context);

/// Resolves [elementId] through the active [SourcePaneService] and
/// shows the corresponding source location in the pane.
///
/// When [elementId] is null the opener falls back to the active
/// schematic selection (so command-palette dispatch without a
/// pre-supplied target still works). Schematic context-menu
/// dispatch passes the right-clicked element's [ElementId]
/// explicitly.
///
/// Default is a no-op. The Pro overlay overrides with a callback
/// that:
///
///   1. Ensures the source pane is visible (calls the show-opener),
///   2. Reads the active tab's [sourcePaneStateProvider] notifier and
///      invokes `setActiveElement(elementId)`,
///   3. Surfaces a snackbar when the element has no source attribution.
typedef OpenSourceForElementOpener =
    void Function(
      BuildContext context,
      WidgetRef ref, {
      ElementId? elementId,
    });

/// Closes / dismisses the RTL source pane.
///
/// Default is a no-op. The Pro overlay overrides with a callback
/// that closes the right dock's Source tab. The per-tab source-pane
/// state is kept, so reopening the tab shows the same file and line.
typedef CloseSourcePaneOpener = void Function(BuildContext context);

/// Open-core extension point for showing the RTL source pane.
final showSourcePaneOpenerProvider = Provider<ShowSourcePaneOpener>(
  (_) => (_) {
    // Open-core no-op. The Pro overlay overrides this with a callback
    // that mounts the source pane.
  },
  name: 'showSourcePaneOpenerProvider',
);

/// Open-core extension point for opening the source file behind a
/// schematic element.
final openSourceForElementOpenerProvider = Provider<OpenSourceForElementOpener>(
  (_) => (_, _, {elementId}) {
    // Open-core no-op. The Pro overlay overrides this.
  },
  name: 'openSourceForElementOpenerProvider',
);

/// Open-core extension point for closing the RTL source pane.
final closeSourcePaneOpenerProvider = Provider<CloseSourcePaneOpener>(
  (_) => (_) {
    // Open-core no-op. The Pro overlay overrides this.
  },
  name: 'closeSourcePaneOpenerProvider',
);
