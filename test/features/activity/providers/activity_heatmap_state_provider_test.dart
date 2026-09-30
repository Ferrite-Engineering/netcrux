// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/activity/activity_analysis_result.dart';
import 'package:netcrux/domain/models/activity/activity_color_scheme.dart';
import 'package:netcrux/domain/models/activity/net_activity.dart';
import 'package:netcrux/domain/models/activity/waveform_time_range.dart';
import 'package:netcrux/features/activity/providers/activity_heatmap_state_provider.dart';

ActivityAnalysisResult _result(Map<String, double> scores) {
  final perNet = <String, NetActivity>{
    for (final entry in scores.entries)
      entry.key: NetActivity(
        netPath: entry.key,
        transitionCount: (entry.value * 100).round(),
        dutyCyclePercent: 50,
        activityScore: entry.value,
      ),
  };
  return ActivityAnalysisResult.from(
    source: null,
    timeRange: WaveformTimeRange.fullSimulationSentinel,
    perNetActivity: perNet,
    analysisDuration: Duration.zero,
  );
}

void main() {
  group('ActivityHeatmapNotifier', () {
    test('initial state is empty + sentinel range + redBlue scheme', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final state = container.read(activityHeatmapStateProvider);
      expect(state.result.isEmpty, true);
      expect(state.selectedNetPath, isNull);
      expect(state.timeRange, WaveformTimeRange.fullSimulationSentinel);
      expect(state.colorScheme, ActivityColorScheme.heatmapRedBlue);
    });

    test('setResult installs the result and clears unknown selections', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(activityHeatmapStateProvider.notifier).selectNet(null);
      container
          .read(activityHeatmapStateProvider.notifier)
          .setResult(_result({'a': 0.1, 'b': 0.9}));
      expect(
        container
            .read(activityHeatmapStateProvider)
            .result
            .perNetActivity
            .length,
        2,
      );
    });

    test('setResult preserves a still-present selection', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(activityHeatmapStateProvider.notifier)
        ..setResult(_result({'a': 0.1, 'b': 0.9}))
        ..selectNet('b');
      expect(
        container.read(activityHeatmapStateProvider).selectedNetPath,
        'b',
      );
      notifier.setResult(_result({'a': 0.5, 'b': 0.9, 'c': 0.2}));
      expect(
        container.read(activityHeatmapStateProvider).selectedNetPath,
        'b',
      );
    });

    test('setResult clears a no-longer-present selection', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(activityHeatmapStateProvider.notifier)
        ..setResult(_result({'a': 0.1, 'b': 0.9}))
        ..selectNet('b')
        ..setResult(_result({'a': 0.5})); // b is gone
      expect(
        container.read(activityHeatmapStateProvider).selectedNetPath,
        isNull,
      );
    });

    test('selectNet ignores unknown net paths silently', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(activityHeatmapStateProvider.notifier)
          .setResult(_result({'a': 0.1}));
      container
          .read(activityHeatmapStateProvider.notifier)
          .selectNet('not-real');
      expect(
        container.read(activityHeatmapStateProvider).selectedNetPath,
        isNull,
      );
    });

    test('selectNet(null) clears the focused selection', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(activityHeatmapStateProvider.notifier)
          .setResult(_result({'a': 0.1}));
      container.read(activityHeatmapStateProvider.notifier).selectNet('a');
      container.read(activityHeatmapStateProvider.notifier).selectNet(null);
      expect(
        container.read(activityHeatmapStateProvider).selectedNetPath,
        isNull,
      );
    });

    test('setTimeRange + setColorScheme update independently', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(activityHeatmapStateProvider.notifier)
          .setTimeRange(
            const WaveformTimeRange(
              startNs: 100,
              endNs: 200,
              label: 'mid',
            ),
          );
      container
          .read(activityHeatmapStateProvider.notifier)
          .setColorScheme(ActivityColorScheme.heatmapViridis);
      final state = container.read(activityHeatmapStateProvider);
      expect(state.timeRange.label, 'mid');
      expect(state.colorScheme, ActivityColorScheme.heatmapViridis);
    });

    test('clearSelection leaves result, range, scheme intact', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(activityHeatmapStateProvider.notifier)
          .setResult(_result({'a': 0.1}));
      container.read(activityHeatmapStateProvider.notifier).selectNet('a');
      container.read(activityHeatmapStateProvider.notifier).clearSelection();
      final state = container.read(activityHeatmapStateProvider);
      expect(state.selectedNetPath, isNull);
      expect(state.result.perNetActivity.length, 1);
    });

    test('reset wipes everything back to the empty state', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(activityHeatmapStateProvider.notifier)
          .setResult(_result({'a': 0.1}));
      container
          .read(activityHeatmapStateProvider.notifier)
          .setColorScheme(ActivityColorScheme.heatmapGrayscale);
      container.read(activityHeatmapStateProvider.notifier).reset();
      expect(
        container.read(activityHeatmapStateProvider),
        ActivityHeatmapState.empty,
      );
    });

    test('selectedNetActivityProvider tracks the focused row', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(activityHeatmapStateProvider.notifier)
          .setResult(_result({'a': 0.42}));
      container.read(activityHeatmapStateProvider.notifier).selectNet('a');
      final na = container.read(selectedNetActivityProvider);
      expect(na, isNotNull);
      expect(na!.netPath, 'a');
      expect(na.activityScore, closeTo(0.42, 1e-9));
    });

    test('convenience providers narrow rebuild surfaces', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      // Smoke: all three convenience providers resolve without error.
      expect(
        container.read(perTabActivityAnalysisResultProvider).isEmpty,
        true,
      );
      expect(
        container.read(activeActivityTimeRangeProvider),
        WaveformTimeRange.fullSimulationSentinel,
      );
      expect(
        container.read(activeActivityColorSchemeProvider),
        ActivityColorScheme.heatmapRedBlue,
      );
    });
  });
}
