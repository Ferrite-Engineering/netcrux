// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/interfaces/reset_domain_analysis_service.dart';
import 'package:netcrux/domain/models/reset_domain/reset_domain_analysis_result.dart';

void main() {
  group('NoopResetDomainAnalysisService', () {
    test('analyze returns the canonical empty result', () async {
      const service = NoopResetDomainAnalysisService();
      final result = await service.analyze();
      expect(result, ResetDomainAnalysisResult.empty);
      expect(result.detectedDomains, isEmpty);
      expect(result.detectedCrossings, isEmpty);
      expect(result.analysisDiagnostics, isEmpty);
    });

    test('crossingsForSignal returns an empty list', () async {
      const service = NoopResetDomainAnalysisService();
      final result = await service.crossingsForSignal('top.q');
      expect(result, isEmpty);
    });

    test('crossingsForDomain returns an empty list', () async {
      const service = NoopResetDomainAnalysisService();
      final result = await service.crossingsForDomain('dom-a');
      expect(result, isEmpty);
    });

    test('analysisInvalidated never emits', () async {
      const service = NoopResetDomainAnalysisService();
      var events = 0;
      final sub = service.analysisInvalidated.listen((_) => events++);
      await Future<void>.delayed(const Duration(milliseconds: 1));
      await sub.cancel();
      expect(events, 0);
    });
  });
}
