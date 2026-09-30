// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:netcrux/features/viewer/providers/pane_render_stats.dart';

/// Per-pane override list applied on top of [`paneIdProvider`] when
/// [`PaneContainerManager`] creates a fresh `ProviderContainer` for a new
/// pane.
///
/// Render-stats are pane-scoped because each pane has its own schematic
/// canvas with its own paint pipeline. App-level metrics (memory, FPS)
/// live at the root scope.
///
/// The [paneId] parameter is part of the [`PaneOverridesFactory`]
/// signature; future per-pane providers that need the pane id can read it.
List<Override> netcruxPaneOverridesFactory(PaneId paneId) {
  return <Override>[
    paneRenderStatsProvider.overrideWith(PaneRenderStatsNotifier.new),
  ];
}
