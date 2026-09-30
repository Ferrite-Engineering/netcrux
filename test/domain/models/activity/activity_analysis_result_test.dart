// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/activity/activity_analysis_result.dart';
import 'package:netcrux/domain/models/activity/net_activity.dart';
import 'package:netcrux/domain/models/activity/waveform_format.dart';
import 'package:netcrux/domain/models/activity/waveform_source.dart';
import 'package:netcrux/domain/models/activity/waveform_time_range.dart';

void main() {
  group('ActivityAnalysisResult', () {
    NetActivity make(String path, double score, int count) => NetActivity(
      netPath: path,
      transitionCount: count,
      dutyCyclePercent: 50,
      activityScore: score,
    );

    test('empty is canonical and isEmpty true', () {
      expect(ActivityAnalysisResult.empty.isEmpty, true);
      expect(ActivityAnalysisResult.empty.perNetActivity, isEmpty);
      expect(ActivityAnalysisResult.empty.hottest, isEmpty);
      expect(ActivityAnalysisResult.empty.coldest, isEmpty);
      expect(ActivityAnalysisResult.empty.totalTransitions, 0);
    });

    test('from sorts hottest descending and coldest ascending', () {
      final source = WaveformSource(
        filePath: '/tmp/a.vcd',
        format: WaveformFormat.vcd,
        loadedAt: DateTime.utc(2026, 5, 25),
        fingerprint: 'x',
      );
      final perNet = <String, NetActivity>{
        'a': make('a', 0.10, 10),
        'b': make('b', 0.90, 90),
        'c': make('c', 0.50, 50),
        'd': make('d', 0.25, 25),
      };
      final result = ActivityAnalysisResult.from(
        source: source,
        timeRange: const WaveformTimeRange(
          startNs: 0,
          endNs: 1000,
          label: 'x',
        ),
        perNetActivity: perNet,
        analysisDuration: const Duration(milliseconds: 12),
        topN: 2,
      );
      expect(result.hottest.length, 2);
      expect(result.hottest[0].netPath, 'b');
      expect(result.hottest[1].netPath, 'c');
      expect(result.coldest.length, 2);
      expect(result.coldest[0].netPath, 'a');
      expect(result.coldest[1].netPath, 'd');
      expect(result.totalTransitions, 175);
    });

    test('from with topN larger than per-net count returns full list', () {
      final perNet = <String, NetActivity>{
        'a': make('a', 0.10, 5),
        'b': make('b', 0.90, 10),
      };
      final result = ActivityAnalysisResult.from(
        source: null,
        timeRange: WaveformTimeRange.fullSimulationSentinel,
        perNetActivity: perNet,
        analysisDuration: Duration.zero,
      );
      expect(result.hottest.length, 2);
      expect(result.coldest.length, 2);
      expect(result.totalTransitions, 15);
    });

    test('activityForNet returns null for unknown paths', () {
      final perNet = <String, NetActivity>{'a': make('a', 0.1, 1)};
      final result = ActivityAnalysisResult.from(
        source: null,
        timeRange: WaveformTimeRange.fullSimulationSentinel,
        perNetActivity: perNet,
        analysisDuration: Duration.zero,
      );
      expect(result.activityForNet('a')?.netPath, 'a');
      expect(result.activityForNet('z'), isNull);
    });

    test('JSON round-trip preserves source, range, per-net, top-N', () {
      final source = WaveformSource(
        filePath: '/tmp/a.vcd',
        format: WaveformFormat.fst,
        loadedAt: DateTime.utc(2026, 5, 25),
        fingerprint: 'x',
        fileSizeBytes: 200,
      );
      final perNet = <String, NetActivity>{
        'a': make('a', 0.1, 1),
        'b': make('b', 0.9, 9),
      };
      final original = ActivityAnalysisResult.from(
        source: source,
        timeRange: const WaveformTimeRange(
          startNs: 100,
          endNs: 200,
          label: 'mid',
        ),
        perNetActivity: perNet,
        analysisDuration: const Duration(microseconds: 500),
      );
      final restored = ActivityAnalysisResult.fromJson(original.toJson());
      expect(restored.source, source);
      expect(restored.timeRange, original.timeRange);
      expect(restored.perNetActivity.length, 2);
      expect(restored.totalTransitions, 10);
      expect(restored.hottest.length, 2);
      expect(restored.hottest.first.netPath, 'b');
      expect(restored.analysisDuration, const Duration(microseconds: 500));
    });

    test('fromJson handles missing source / range / per-net safely', () {
      final restored = ActivityAnalysisResult.fromJson(
        const <String, Object?>{},
      );
      expect(restored.source, isNull);
      expect(restored.timeRange, WaveformTimeRange.fullSimulationSentinel);
      expect(restored.perNetActivity, isEmpty);
      expect(restored.hottest, isEmpty);
      expect(restored.coldest, isEmpty);
      expect(restored.totalTransitions, 0);
      expect(restored.analysisDuration, Duration.zero);
    });
  });
}
