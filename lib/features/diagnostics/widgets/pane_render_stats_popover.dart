// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/features/diagnostics/providers/diagnostics_providers.dart';
import 'package:netcrux/features/diagnostics/widgets/app_diagnostics_dialog.dart'
    show formatMicros;
import 'package:netcrux/features/statistics/providers/layout_timing_provider.dart';
import 'package:netcrux/features/viewer/providers/pane_render_stats.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

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
class PaneRenderStatsButton extends ConsumerWidget {
  /// Creates the button.
  const PaneRenderStatsButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
    // `UncontrolledProviderScope`, so the card would otherwise resolve the
    // empty root-scope instances of the per-pane render stats and the
    // per-tab layout timing — a popover reading zeros for a canvas that had
    // painted. Capture this pane's container here, where we are still
    // inside it, and re-scope the card onto it.
    final container = ProviderScope.containerOf(context, listen: false);

    final origin = box.localToGlobal(
      box.size.bottomLeft(Offset.zero),
      ancestor: overlay,
    );
    unawaited(
      showDialog<void>(
        context: context,
        barrierColor: Colors.transparent,
        builder: (_) => UncontrolledProviderScope(
          container: container,
          child: Stack(
            children: [
              Positioned(
                // Clamped so a pane docked against the right edge does not
                // push the card off-screen.
                left: origin.dx.clamp(
                  8.0,
                  (overlay.size.width - 308).clamp(8, 8000),
                ),
                top: origin.dy + 4,
                child: const _PaneRenderStatsCard(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PaneRenderStatsCard extends ConsumerWidget {
  const _PaneRenderStatsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    final paint = ref.watch(paneRenderStatsProvider);
    final layout = ref.watch(layoutTimingProvider);
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
