// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_stats_strip/crux_stats_strip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/features/project/providers/current_laid_out_graph_provider.dart';
import 'package:netcrux/features/project/providers/loaded_netlist_provider.dart';
import 'package:netcrux/features/statistics/providers/elaboration_progress_provider.dart';
import 'package:netcrux/features/statistics/providers/layout_timing_provider.dart';
import 'package:netcrux/features/viewer/providers/pane_render_stats.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

/// NetCrux's live statistics strip.
///
/// Assembles the shared app-level segments with NetCrux's own:
///
/// * **Layout time** — the slowest non-elaboration step in the pipeline.
///   Called out in the plan as NetCrux's product-specific addition because
///   on a large scope "is it hung or is it working?" is a real question.
/// * **Elaboration indicator** — a spinner with elapsed time while a Yosys
///   subprocess is running. Deliberately distinct from the Tab Diagnostics
///   drawer: the strip answers "is something running right now?", the
///   drawer answers "what happened on the last run?".
/// * **Paint time and viewport counts** — from the active pane's
///   `paneRenderStatsProvider`, which is per-pane so switching panes swaps
///   the reading without losing either pane's history.
class NetcruxStatsStrip extends ConsumerWidget {
  /// Creates the strip.
  const NetcruxStatsStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final frame = ref.watch(cruxFrameStatsProvider);
    final memory = ref.watch(cruxMemoryStatsProvider);
    final layout = ref.watch(layoutTimingProvider);
    final paint = ref.watch(paneRenderStatsProvider);
    final netlist = ref.watch(loadedNetlistProvider);
    // "Layout is running" is the graph provider's own loading state —
    // the provider IS the layout pass, so a mirrored flag elsewhere could
    // only ever disagree with it.
    final layoutRunning = ref.watch(currentLaidOutGraphProvider).isLoading;

    final elaborating = netlist.isLoading;
    // The pass Yosys is executing right now, parsed from its stderr as it
    // streams. Null between passes or when the banner has not arrived yet.
    final pass = ref.watch(elaborationProgressProvider);

    return CruxStatsStrip(
      label: l10n.statsStripLabel,
      // The disclosure control's one spoken name: the visible caption is a
      // terse "Stats", which a screen reader would otherwise read as a word.
      semanticLabel: l10n.statisticsStripTitle,
      expandTooltip: l10n.statsStripExpandTooltip,
      collapseTooltip: l10n.statsStripCollapseTooltip,
      segments: <CruxStatSegment>[
        CruxStatSegment(
          label: l10n.statsSegmentMemory,
          value: memory.hasSample ? cruxFormatBytes(memory.residentBytes) : '—',
          sparkline: memory.recentResidentBytes,
          tooltip: l10n.statsSegmentMemoryTooltip,
        ),
        CruxStatSegment(
          label: l10n.statsSegmentFps,
          value: frame.sampledFrames == 0
              ? '—'
              : frame.framesPerSecond.toStringAsFixed(1),
          sparkline: frame.recentFrameMillis,
          tooltip: l10n.statsSegmentFpsTooltip,
        ),
        CruxStatSegment(
          label: l10n.statsSegmentJank,
          value: '${frame.budgetOverruns}',
          emphasis: frame.overrunRatio > 0.05
              ? CruxStatEmphasis.warning
              : CruxStatEmphasis.normal,
          tooltip: l10n.statsSegmentJankTooltip,
        ),
        CruxStatSegment(
          label: l10n.statsSegmentLayout,
          value: layoutRunning
              ? '…'
              : layout.hasSample
              ? _formatMicros(layout.lastMicroseconds)
              : '—',
          sparkline: layout.recentMillis,
          emphasis: layoutRunning
              ? CruxStatEmphasis.dimmed
              : CruxStatEmphasis.normal,
          tooltip: l10n.statsSegmentLayoutTooltip,
        ),
        CruxStatSegment(
          label: l10n.statsSegmentPaint,
          value: paint.frameNumber == 0
              ? '—'
              : _formatMicros(paint.paintMicroseconds),
          tooltip: l10n.statsSegmentPaintTooltip,
        ),
        CruxStatSegment(
          label: l10n.statsSegmentViewport,
          value: paint.frameNumber == 0
              ? '—'
              : '${paint.visibleCells}/${paint.visibleEdges}',
          tooltip: l10n.statsSegmentViewportTooltip,
        ),
        CruxStatSegment(
          label: l10n.statsSegmentElaboration,
          // Name the pass when Yosys has announced one; a long
          // elaboration otherwise reads as an undifferentiated "running"
          // with no sense of whether it is progressing.
          value: elaborating
              ? (pass ?? l10n.statsElaborationRunning)
              : l10n.statsElaborationIdle,
          emphasis: elaborating
              ? CruxStatEmphasis.normal
              : CruxStatEmphasis.dimmed,
          leading: elaborating
              ? const SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(strokeWidth: 1.5),
                )
              : null,
          tooltip: l10n.statsSegmentElaborationTooltip,
        ),
      ],
    );
  }
}

/// Renders a microsecond duration at the precision the strip's narrow
/// value column can show — sub-millisecond in µs, everything else in ms.
String _formatMicros(int micros) {
  if (micros < 1000) return '$micros µs';
  return '${(micros / 1000).toStringAsFixed(1)} ms';
}
