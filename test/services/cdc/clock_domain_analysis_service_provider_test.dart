// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/interfaces/clock_domain_analysis_service.dart';
import 'package:netcrux/domain/models/cdc/cdc_analysis_options.dart';
import 'package:netcrux/domain/models/cdc/cdc_analysis_result.dart';
import 'package:netcrux/domain/models/cdc/cdc_crossing.dart';
import 'package:netcrux/domain/models/cdc/clock_domain.dart';
import 'package:netcrux/services/cdc/clock_domain_analysis_service_provider.dart';

class _FakeAnalysisService implements ClockDomainAnalysisService {
  @override
  Future<CdcAnalysisResult> analyze({CdcAnalysisOptions? options}) async {
    return const CdcAnalysisResult(
      detectedDomains: <ClockDomain>[],
      detectedCrossings: <CdcCrossing>[],
      analysisDiagnostics: <String>['ran by fake'],
      analysisDuration: Duration.zero,
    );
  }

  @override
  Future<List<CdcCrossing>> crossingsForSignal(String signalPath) async {
    return const <CdcCrossing>[];
  }

  @override
  Future<List<CdcCrossing>> crossingsForDomain(String domainId) async {
    return const <CdcCrossing>[];
  }

  @override
  Stream<void> get analysisInvalidated => const Stream<void>.empty();
}

void main() {
  group('clockDomainAnalysisServiceProvider', () {
    test('default resolves to a NoopClockDomainAnalysisService', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(
        container.read(clockDomainAnalysisServiceProvider),
        isA<NoopClockDomainAnalysisService>(),
      );
    });

    test('Pro overlay can override with .overrideWith', () async {
      final container = ProviderContainer(
        overrides: [
          clockDomainAnalysisServiceProvider.overrideWithValue(
            _FakeAnalysisService(),
          ),
        ],
      );
      addTearDown(container.dispose);
      final svc = container.read(clockDomainAnalysisServiceProvider);
      expect(svc, isA<_FakeAnalysisService>());
      final result = await svc.analyze();
      expect(result.analysisDiagnostics, contains('ran by fake'));
    });
  });
}
