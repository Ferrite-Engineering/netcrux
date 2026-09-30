// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/interfaces/clock_domain_analysis_service.dart';
import 'package:netcrux/domain/models/cdc/cdc_analysis_result.dart';

void main() {
  group('NoopClockDomainAnalysisService', () {
    test('analyze returns the canonical empty result', () async {
      const service = NoopClockDomainAnalysisService();
      final result = await service.analyze();
      expect(result, CdcAnalysisResult.empty);
    });

    test('crossingsForSignal returns an empty list', () async {
      const service = NoopClockDomainAnalysisService();
      expect(await service.crossingsForSignal('top.x'), isEmpty);
    });

    test('crossingsForDomain returns an empty list', () async {
      const service = NoopClockDomainAnalysisService();
      expect(await service.crossingsForDomain('dom-A'), isEmpty);
    });

    test('analysisInvalidated is an empty stream', () async {
      const service = NoopClockDomainAnalysisService();
      var emissions = 0;
      final sub = service.analysisInvalidated.listen((_) => emissions++);
      // Wait for the empty stream to complete naturally.
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(emissions, 0);
    });
  });
}
