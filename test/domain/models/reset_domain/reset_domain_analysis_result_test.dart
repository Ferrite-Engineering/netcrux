// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/reset_domain/reset_crossing.dart';
import 'package:netcrux/domain/models/reset_domain/reset_crossing_kind.dart';
import 'package:netcrux/domain/models/reset_domain/reset_domain.dart';
import 'package:netcrux/domain/models/reset_domain/reset_domain_analysis_result.dart';
import 'package:netcrux/domain/models/reset_domain/reset_polarity.dart';
import 'package:netcrux/domain/models/reset_domain/reset_severity.dart';
import 'package:netcrux/domain/models/reset_domain/reset_source_kind.dart';
import 'package:netcrux/domain/models/reset_domain/reset_synchronicity.dart';
import 'package:netcrux/domain/models/reset_domain/reset_synchronizer_status.dart';

void main() {
  group('ResetDomainAnalysisResult', () {
    const sigId = ElementId(kind: ElementKind.signal, path: 'top.q');

    ResetDomain dom(String id, String name) => ResetDomain(
      id: id,
      resetSignalId: ElementId(kind: ElementKind.signal, path: 'top.$name'),
      resetSignalName: name,
      polarity: ResetPolarity.activeLow,
      synchronicity: ResetSynchronicity.asyncAssertSyncDeassert,
      sourceKind: ResetSourceKind.primaryInput,
      memberRegisters: const <ElementId>[],
      memberNets: const <ElementId>[],
    );

    ResetCrossing crs(
      String id,
      ResetSeverity sev, {
      String source = 'dom-a',
      String dest = 'dom-b',
    }) => ResetCrossing(
      id: id,
      sourceDomainId: source,
      destinationDomainId: dest,
      signalId: sigId,
      signalName: 'top.q',
      crossingKind: ResetCrossingKind.resetDeassertCrossing,
      synchronizerStatus: ResetSynchronizerStatus.properAsyncAssertSyncDeassert,
      severity: sev,
      confidence: ResetConfidence.high,
      sourcePolarity: ResetPolarity.activeLow,
    );

    test('empty constant is empty', () {
      expect(ResetDomainAnalysisResult.empty.detectedDomains, isEmpty);
      expect(ResetDomainAnalysisResult.empty.detectedCrossings, isEmpty);
      expect(ResetDomainAnalysisResult.empty.isEmpty, isTrue);
      expect(
        ResetDomainAnalysisResult.empty.analysisDuration,
        Duration.zero,
      );
    });

    test('severity counts reflect detected crossings', () {
      final result = ResetDomainAnalysisResult(
        detectedDomains: <ResetDomain>[dom('dom-a', 'rst_a')],
        detectedCrossings: <ResetCrossing>[
          crs('c1', ResetSeverity.critical),
          crs('c2', ResetSeverity.critical),
          crs('c3', ResetSeverity.warning),
          crs('c4', ResetSeverity.info),
        ],
        analysisDiagnostics: const <String>[],
        analysisDuration: const Duration(milliseconds: 12),
      );
      expect(result.criticalCount, 2);
      expect(result.warningCount, 1);
      expect(result.infoCount, 1);
    });

    test('domainById / crossingById return matches and null for misses', () {
      final result = ResetDomainAnalysisResult(
        detectedDomains: <ResetDomain>[dom('dom-a', 'rst_a')],
        detectedCrossings: <ResetCrossing>[
          crs('c1', ResetSeverity.warning),
        ],
        analysisDiagnostics: const <String>[],
        analysisDuration: Duration.zero,
      );
      expect(result.domainById('dom-a'), isNotNull);
      expect(result.domainById('dom-z'), isNull);
      expect(result.crossingById('c1'), isNotNull);
      expect(result.crossingById('cz'), isNull);
    });

    test('JSON round-trip preserves all fields', () {
      final original = ResetDomainAnalysisResult(
        detectedDomains: <ResetDomain>[dom('dom-a', 'rst_a')],
        detectedCrossings: <ResetCrossing>[
          crs('c1', ResetSeverity.warning),
        ],
        analysisDiagnostics: const <String>['hello', 'world'],
        analysisDuration: const Duration(milliseconds: 25),
      );
      final json = original.toJson();
      final roundTripped = ResetDomainAnalysisResult.fromJson(json);
      expect(roundTripped, equals(original));
      expect(roundTripped.toJson(), equals(json));
    });

    test('isEmpty true only when both lists are empty', () {
      expect(
        ResetDomainAnalysisResult.empty.isEmpty,
        isTrue,
      );
      final withDomains = ResetDomainAnalysisResult(
        detectedDomains: <ResetDomain>[dom('dom-a', 'rst_a')],
        detectedCrossings: const <ResetCrossing>[],
        analysisDiagnostics: const <String>[],
        analysisDuration: Duration.zero,
      );
      expect(withDomains.isEmpty, isFalse);
    });

    test('parses empty JSON without throwing', () {
      final empty = ResetDomainAnalysisResult.fromJson(
        const <String, Object?>{},
      );
      expect(empty.detectedDomains, isEmpty);
      expect(empty.detectedCrossings, isEmpty);
      expect(empty.analysisDiagnostics, isEmpty);
      expect(empty.analysisDuration, Duration.zero);
    });

    test('toString surfaces the salient fields', () {
      final result = ResetDomainAnalysisResult(
        detectedDomains: <ResetDomain>[dom('dom-a', 'rst_a')],
        detectedCrossings: <ResetCrossing>[
          crs('c1', ResetSeverity.critical),
        ],
        analysisDiagnostics: const <String>['ok'],
        analysisDuration: const Duration(milliseconds: 5),
      );
      final s = result.toString();
      expect(s, contains('ResetDomainAnalysisResult'));
      expect(s, contains('1 domains'));
      expect(s, contains('1 crossings'));
      expect(s, contains('1 critical'));
    });
  });
}
