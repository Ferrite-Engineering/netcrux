// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/models/activity/activity_analysis_result.dart';
import 'package:netcrux/domain/models/activity/activity_color_scheme.dart';
import 'package:netcrux/domain/models/activity/net_activity.dart';
import 'package:netcrux/features/activity/providers/activity_heatmap_state_provider.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/schematic/net_activity_color_override_provider.dart';

/// Open-core Switching Activity Heatmap pane.
///
/// Reads the current analysis result + selected net from
/// [activityHeatmapStateProvider]. When no analysis has run the
/// empty-state explainer renders; when a result is present it surfaces
/// a legend and a grouped list of the hottest and coldest nets. The Pro
/// overlay's `ActivityHeatmapPanel` wraps this widget in panel
/// chrome + the actual time-range / color-scheme controls, and is the
/// only place it is mounted: the open-core build refuses the activity
/// actions with a "requires NetCrux Pro" notice and mounts no pane.
///
/// Each row's bar paints the color the schematic paints that net's wires,
/// through [ActivityColorScheme.colorForNet] with the tab's scheme and the
/// canvas brightness, and the legend above the list draws the same ramp
/// plus the clock color. So the list, the legend and the canvas agree.
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
    final brightness = ref.watch(activityCanvasBrightnessProvider);
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
      scheme: state.colorScheme,
      brightness: brightness,
    );
  }
}

class _FallbackList extends StatelessWidget {
  const _FallbackList({
    required this.l10n,
    required this.result,
    required this.selectedNetPath,
    required this.onSelectNet,
    required this.scheme,
    required this.brightness,
  });

  final L10N l10n;
  final ActivityAnalysisResult result;
  final String? selectedNetPath;
  final void Function(NetActivity)? onSelectNet;
  final ActivityColorScheme scheme;
  final Brightness brightness;

  Widget _row(NetActivity n) => _NetRow(
    l10n: l10n,
    net: n,
    color: scheme.colorForNet(n, brightness),
    isHighlighted: n.netPath == selectedNetPath,
    onTap: onSelectNet == null ? null : () => onSelectNet!(n),
  );

  @override
  Widget build(BuildContext context) {
    final hasClock = result.perNetActivity.values.any((n) => n.isClock);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _Header(l10n: l10n, result: result),
        _Legend(
          l10n: l10n,
          stops: scheme.stops(brightness),
          showClock: hasClock,
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            children: <Widget>[
              _SectionHeader(text: l10n.activityHeatmapPaneHottestSection),
              for (final n in result.hottest) _row(n),
              _SectionHeader(text: l10n.activityHeatmapPaneColdestSection),
              for (final n in result.coldest) _row(n),
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

/// The color key: the scheme's ramp from least to most active, and, when
/// the result holds a clock, the clock color with why it stands apart.
class _Legend extends StatelessWidget {
  const _Legend({
    required this.l10n,
    required this.stops,
    required this.showClock,
  });

  final L10N l10n;
  final List<Color> stops;
  final bool showClock;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      color: theme.colorScheme.surfaceContainer,
      alignment: AlignmentDirectional.centerStart,
      // A wrap, so a narrow dock moves the clock entry to its own line
      // instead of overflowing.
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Flexible(
                child: Text(
                  l10n.activityHeatmapLegendLeast,
                  style: labelStyle,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Semantics(
                label: l10n.activityHeatmapLegendScale,
                child: Container(
                  width: _scaleWidth,
                  height: 8,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    gradient: LinearGradient(colors: stops),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  l10n.activityHeatmapLegendMost,
                  style: labelStyle,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (showClock)
            Tooltip(
              message: l10n.activityHeatmapLegendClockTooltip,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    width: 14,
                    height: 8,
                    decoration: BoxDecoration(
                      color: ActivityColorScheme.clockColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(l10n.activityHeatmapLegendClock, style: labelStyle),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Width of the color strip: enough to read the ramp's stops, small
  /// enough that the strip and its two labels fit the narrowest dock.
  static const double _scaleWidth = 96;
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
    required this.color,
    required this.isHighlighted,
    required this.onTap,
  });

  final L10N l10n;
  final NetActivity net;

  /// The color the schematic paints this net's wires.
  final Color color;
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
            // Activity score bar: fills in proportion to the normalized
            // 0.0..1.0 score, in the color the schematic paints the net,
            // so a row and its wires can be matched at a glance.
            SizedBox(
              width: 36,
              height: 14,
              child: Stack(
                children: <Widget>[
                  Container(color: cs.surfaceContainerHighest),
                  FractionallySizedBox(
                    widthFactor: net.activityScore,
                    child: Container(color: color),
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
            if (net.isClock) ...<Widget>[
              const SizedBox(width: 8),
              Text(
                l10n.activityHeatmapLegendClock,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
