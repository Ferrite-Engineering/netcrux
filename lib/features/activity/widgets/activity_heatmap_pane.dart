// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/models/activity/activity_analysis_result.dart';
import 'package:netcrux/domain/models/activity/net_activity.dart';
import 'package:netcrux/features/activity/providers/activity_heatmap_state_provider.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

/// Open-core Switching Activity Heatmap pane.
///
/// Reads the current analysis result + selected net from
/// [activityHeatmapStateProvider]. When no analysis has run the
/// empty-state explainer renders; when a result is present it surfaces
/// a simple grouped list of the hottest and coldest nets. The Pro
/// overlay's `ActivityHeatmapPanel` wraps this widget in panel
/// chrome + the actual time-range / color-scheme controls, and is the
/// only place it is mounted: the open-core build refuses the activity
/// actions with a "requires NetCrux Pro" notice and mounts no pane.
///
/// Selection-sync: tapping a net row invokes [onSelectNet] when
/// supplied. The Pro overlay routes this into the schematic
/// selection provider; open-core ships [onSelectNet] = null which
/// renders the rows non-interactive.
class ActivityHeatmapPane extends ConsumerWidget {
  /// Creates the activity heatmap pane.
  const ActivityHeatmapPane({this.onSelectNet, super.key});

  /// Invoked when the user taps a net row. The hosting Pro panel
  /// typically routes the call into the per-tab schematic selection
  /// provider so the corresponding net highlights. Null disables
  /// the callback (renders rows but doesn't fire — open-core
  /// default).
  final void Function(NetActivity)? onSelectNet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final state = ref.watch(activityHeatmapStateProvider);
    final result = state.result;
    if (result.isEmpty) {
      return CruxPanelEmptyState(
        icon: Icons.local_fire_department_outlined,
        message:
            '${l10n.activityHeatmapPaneEmptyTitle}\n'
            '${l10n.activityHeatmapPaneEmptyHint}',
      );
    }
    return _FallbackList(
      l10n: l10n,
      result: result,
      selectedNetPath: state.selectedNetPath,
      onSelectNet: onSelectNet,
    );
  }
}

class _FallbackList extends StatelessWidget {
  const _FallbackList({
    required this.l10n,
    required this.result,
    required this.selectedNetPath,
    required this.onSelectNet,
  });

  final L10N l10n;
  final ActivityAnalysisResult result;
  final String? selectedNetPath;
  final void Function(NetActivity)? onSelectNet;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _Header(l10n: l10n, result: result),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            children: <Widget>[
              _SectionHeader(text: l10n.activityHeatmapPaneHottestSection),
              for (final n in result.hottest)
                _NetRow(
                  l10n: l10n,
                  net: n,
                  isHighlighted: n.netPath == selectedNetPath,
                  onTap: onSelectNet == null ? null : () => onSelectNet!(n),
                ),
              _SectionHeader(text: l10n.activityHeatmapPaneColdestSection),
              for (final n in result.coldest)
                _NetRow(
                  l10n: l10n,
                  net: n,
                  isHighlighted: n.netPath == selectedNetPath,
                  onTap: onSelectNet == null ? null : () => onSelectNet!(n),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.l10n, required this.result});

  final L10N l10n;
  final ActivityAnalysisResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: theme.colorScheme.surfaceContainer,
      child: Text(
        l10n.activityHeatmapPaneHeader(
          result.perNetActivity.length,
          result.totalTransitions,
        ),
        style: theme.textTheme.labelMedium,
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: theme.colorScheme.surfaceContainerHighest,
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _NetRow extends StatelessWidget {
  const _NetRow({
    required this.l10n,
    required this.net,
    required this.isHighlighted,
    required this.onTap,
  });

  final L10N l10n;
  final NetActivity net;
  final bool isHighlighted;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      child: Container(
        color: isHighlighted ? cs.primary.withValues(alpha: 0.10) : null,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          children: <Widget>[
            // Activity score visual bar — fills proportional to the
            // normalized 0.0..1.0 activity score so even the
            // open-core fallback list communicates relative magnitude
            // without color coding (which is the Pro overlay's
            // responsibility via the painter override).
            SizedBox(
              width: 36,
              height: 14,
              child: Stack(
                children: <Widget>[
                  Container(color: cs.surfaceContainerHighest),
                  FractionallySizedBox(
                    widthFactor: net.activityScore,
                    child: Container(color: cs.primary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l10n.activityHeatmapPaneNetLine(
                  net.netPath,
                  net.transitionCount,
                  net.dutyCyclePercent.toStringAsFixed(1),
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
