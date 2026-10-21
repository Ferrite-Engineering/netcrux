// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:crux_workspace/crux_workspace.dart' as crux;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/features/diagnostics/providers/diagnostics_providers.dart';
import 'package:netcrux/features/diagnostics/widgets/app_diagnostics_dialog.dart'
    show formatMicros;
import 'package:netcrux/features/statistics/providers/layout_timing_provider.dart';
import 'package:netcrux/features/viewer/providers/pane_render_stats.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_notifier.dart';
import 'package:netcrux/services/workspace/tab_container_manager_holder.dart';

/// Per-pane Pane Render Stats affordance.
///
/// An `i` button that lives in a pane's tab bar (supplied through
/// `PaneHost.paneTrailingActionsBuilder`) and opens a popover with that
/// pane's paint-pipeline readings.
///
/// **Why the tab bar and not the App Diagnostics dialog.** Render stats are
/// per-pane. In a split-pane layout the two canvases have independent paint
/// costs and independent viewport culling, and the question "why is *this*
/// one slow" has to be askable of one pane without ambiguity. A single
/// app-level dialog would have to pick a pane, and it would pick the wrong
/// one exactly when the user was comparing them.
///
/// The button reads `paneRenderStatsProvider` from the surrounding scope.
/// `PaneHost` mounts each pane's `ViewerTabBar` inside that pane's own
/// `UncontrolledProviderScope`, so this resolves the right pane's stream
/// without being told which pane it is.
class PaneRenderStatsButton extends ConsumerStatefulWidget {
  /// Creates the button.
  const PaneRenderStatsButton({super.key});

  @override
  ConsumerState<PaneRenderStatsButton> createState() =>
      _PaneRenderStatsButtonState();
}

class _PaneRenderStatsButtonState extends ConsumerState<PaneRenderStatsButton> {
  @override
  Widget build(BuildContext context) {
    if (!ref.watch(diagnosticsEnabledProvider)) return const SizedBox.shrink();
    final l10n = L10N.of(context);

    return IconButton(
      key: const Key('paneRenderStatsButton'),
      icon: const Icon(Icons.info_outline, size: 16),
      iconSize: 16,
      visualDensity: VisualDensity.compact,
      tooltip: l10n.paneRenderStatsTooltip,
      onPressed: () => _show(context),
    );
  }

  /// The container of the tab showing in this button's pane, or null when the
  /// button is not inside a pane of a workspace (a bare scope, as in a test).
  ProviderContainer? _activeTabContainer() {
    final manager = ref.read(tabContainerManagerHolderProvider).manager;
    final workspace = ref.read(netcruxWorkspaceProvider).value;
    if (manager == null || workspace == null) return null;
    final crux.PaneId pane;
    try {
      pane = ref.read(crux.paneIdProvider);
    } on Object {
      return null;
    }
    final tabs = workspace.tabsForPane(pane);
    if (tabs.isEmpty) return null;
    final active = workspace.panes.where((p) => p.id == pane).firstOrNull;
    final activeId = active?.activeTabId;
    final tab = tabs.where((t) => t.id == activeId).firstOrNull ?? tabs.first;
    return manager.containerFor(tab.id);
  }

  /// Opens the popover anchored to the button's own rect.
  ///
  /// Anchored rather than centred: the reading belongs to the pane whose tab
  /// bar was clicked, and a dialog in the middle of the screen would lose
  /// that association in a split layout.
  void _show(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;

    // The route is pushed onto a Navigator that lives ABOVE the pane's
    // `UncontrolledProviderScope`, so a card that read the providers itself
    // would resolve the empty root-scope instances of the per-pane render
    // stats — a popover reading zeros for a canvas that had painted. A second
    // scope over the pane's container is the one thing that must not be used
    // to fix that (Riverpod flushes a container's rebuilds from every scope
    // that mounts it, mid-build). The card reads no provider: this button,
    // which is inside the pane's scope, listens for as long as the popover is
    // open and hands the readings in.
    final stats = ValueNotifier<PaneRenderStats>(
      ref.read(paneRenderStatsProvider),
    );
    // Layout time is per TAB (the tab's laid-out graph writes it), unlike the
    // paint readings, which are per pane: read it from the pane's active tab's
    // container. Read from the pane's own scope it would resolve the root
    // instance, which nothing writes.
    final tabContainer = _activeTabContainer();
    final layout = ValueNotifier<LayoutTimingStats>(
      tabContainer == null
          ? ref.read(layoutTimingProvider)
          : tabContainer.read(layoutTimingProvider),
    );
    void onLayout(LayoutTimingStats? _, LayoutTimingStats next) =>
        layout.value = next;
    final subscriptions = <ProviderSubscription<Object?>>[
      ref.listenManual<PaneRenderStats>(
        paneRenderStatsProvider,
        (_, next) => stats.value = next,
      ),
      if (tabContainer == null)
        ref.listenManual<LayoutTimingStats>(layoutTimingProvider, onLayout)
      else
        tabContainer.listen<LayoutTimingStats>(layoutTimingProvider, onLayout),
    ];

    final origin = box.localToGlobal(
      box.size.bottomLeft(Offset.zero),
      ancestor: overlay,
    );
    unawaited(
      showCruxDialog<void>(
        context: context,
        // A reading, not a task: no scrim, and a click outside or Escape
        // closes it.
        blocking: false,
        builder: (_) => Stack(
          children: [
            Positioned(
              // Clamped so a pane docked against the right edge does not
              // push the card off-screen.
              left: origin.dx.clamp(
                8.0,
                (overlay.size.width - 308).clamp(8, 8000),
              ),
              top: origin.dy + 4,
              child: _PaneRenderStatsCard(stats: stats, layout: layout),
            ),
          ],
        ),
      ).whenComplete(() {
        for (final subscription in subscriptions) {
          subscription.close();
        }
      }),
    );
  }
}

class _PaneRenderStatsCard extends StatelessWidget {
  const _PaneRenderStatsCard({required this.stats, required this.layout});

  final ValueListenable<PaneRenderStats> stats;
  final ValueListenable<LayoutTimingStats> layout;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge(<Listenable>[stats, layout]),
    builder: (context, _) =>
        _buildCard(context, paint: stats.value, layout: layout.value),
  );

  Widget _buildCard(
    BuildContext context, {
    required PaneRenderStats paint,
    required LayoutTimingStats layout,
  }) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    final painted = paint.frameNumber > 0;

    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 300,
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.paneRenderStatsTitle,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  iconSize: 16,
                  visualDensity: VisualDensity.compact,
                  // A Tooltip works here (unlike the beta-expiry strip): the
                  // card is pushed as a route, so the Navigator's Overlay is
                  // an ancestor. Names the surface rather than saying "Close",
                  // because a screen reader reaches this button without the
                  // visual context that made the bare word sufficient.
                  tooltip: l10n.paneRenderStatsCloseTooltip,
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (!painted)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  l10n.paneRenderStatsEmpty,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else ...[
              _StatRow(
                label: l10n.paneRenderStatsPaint,
                value: formatMicros(paint.paintMicroseconds),
              ),
              _StatRow(
                label: l10n.paneRenderStatsLayout,
                value: layout.hasSample
                    ? formatMicros(layout.lastMicroseconds)
                    : '—',
              ),
              _StatRow(
                label: l10n.paneRenderStatsVisibleCells,
                value: '${paint.visibleCells} / ${paint.totalCells}',
              ),
              _StatRow(
                label: l10n.paneRenderStatsVisibleEdges,
                value: '${paint.visibleEdges} / ${paint.totalEdges}',
              ),
              _StatRow(
                label: l10n.paneRenderStatsFrames,
                value: '${paint.frameNumber}',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 8, top: 3, bottom: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(child: Text(label, style: theme.textTheme.bodySmall)),
          const SizedBox(width: 8),
          Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}
