// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/interfaces/activity_analysis_service.dart';
import 'package:netcrux/domain/models/activity/activity_analysis_result.dart';
import 'package:netcrux/domain/models/activity/waveform_time_range.dart';

void main() {
  group('NoopActivityAnalysisService', () {
    test('analyze returns the canonical empty result', () async {
      const service = NoopActivityAnalysisService();
      final result = await service.analyze();
      expect(result, ActivityAnalysisResult.empty);
      expect(result.isEmpty, true);
    });

    test('activityForNet returns null for any path', () async {
      const service = NoopActivityAnalysisService();
      final na = await service.activityForNet(
        'top.q',
        WaveformTimeRange.fullSimulationSentinel,
      );
      expect(na, isNull);
    });

    test('analysisInvalidated never emits', () async {
      const service = NoopActivityAnalysisService();
      var events = 0;
      final sub = service.analysisInvalidated.listen((_) => events++);
      await Future<void>.delayed(const Duration(milliseconds: 1));
      await sub.cancel();
      expect(events, 0);
    });
  });
}
