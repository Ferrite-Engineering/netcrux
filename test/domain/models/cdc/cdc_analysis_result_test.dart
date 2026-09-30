// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/cdc/cdc_analysis_result.dart';
import 'package:netcrux/domain/models/cdc/cdc_crossing.dart';
import 'package:netcrux/domain/models/cdc/cdc_crossing_kind.dart';
import 'package:netcrux/domain/models/cdc/cdc_severity.dart';
import 'package:netcrux/domain/models/cdc/cdc_synchronizer_status.dart';
import 'package:netcrux/domain/models/cdc/clock_domain.dart';
import 'package:netcrux/domain/models/cdc/clock_domain_source_kind.dart';

void main() {
  group('CdcAnalysisResult', () {
    const sigA = ElementId(kind: ElementKind.signal, path: 'top.a');
    const sigB = ElementId(kind: ElementKind.signal, path: 'top.b');
    const clkA = ElementId(kind: ElementKind.signal, path: 'top.clk_a');
    const clkB = ElementId(kind: ElementKind.signal, path: 'top.clk_b');

    CdcAnalysisResult sample() => const CdcAnalysisResult(
      detectedDomains: <ClockDomain>[
        ClockDomain(
          id: 'dom-A',
          clockSignalId: clkA,
          clockSignalName: 'clk_a',
          sourceKind: ClockDomainSourceKind.primaryInput,
          memberRegisters: <ElementId>[],
          memberNets: <ElementId>[],
        ),
        ClockDomain(
          id: 'dom-B',
          clockSignalId: clkB,
          clockSignalName: 'clk_b',
          sourceKind: ClockDomainSourceKind.primaryInput,
          memberRegisters: <ElementId>[],
          memberNets: <ElementId>[],
        ),
      ],
      detectedCrossings: <CdcCrossing>[
        CdcCrossing(
          id: 'x-crit',
          sourceDomainId: 'dom-A',
          destinationDomainId: 'dom-B',
          signalId: sigA,
          signalName: 'a',
          crossingKind: CdcCrossingKind.multiBit,
          synchronizerStatus: CdcSynchronizerStatus.missingSynchronizer,
          severity: CdcSeverity.critical,
          confidence: CdcConfidence.high,
        ),
        CdcCrossing(
          id: 'x-warn',
          sourceDomainId: 'dom-A',
          destinationDomainId: 'dom-B',
          signalId: sigA,
          signalName: 'a_meta',
          crossingKind: CdcCrossingKind.singleBit,
          synchronizerStatus: CdcSynchronizerStatus.metastable,
          severity: CdcSeverity.warning,
          confidence: CdcConfidence.medium,
        ),
        CdcCrossing(
          id: 'x-info',
          sourceDomainId: 'dom-A',
          destinationDomainId: 'dom-B',
          signalId: sigB,
          signalName: 'b',
          crossingKind: CdcCrossingKind.singleBit,
          synchronizerStatus: CdcSynchronizerStatus.properTwoFlopSync,
          severity: CdcSeverity.info,
          confidence: CdcConfidence.high,
        ),
      ],
      analysisDiagnostics: <String>['ran in 0.1s'],
      analysisDuration: Duration(milliseconds: 100),
    );

    test('JSON round-trip preserves all fields', () {
      final original = sample();
      final json = original.toJson();
      final roundTripped = CdcAnalysisResult.fromJson(json);
      expect(roundTripped, equals(original));
    });

    test('empty has no domains, no crossings, no diagnostics', () {
      expect(CdcAnalysisResult.empty.isEmpty, isTrue);
      expect(CdcAnalysisResult.empty.detectedDomains, isEmpty);
      expect(CdcAnalysisResult.empty.detectedCrossings, isEmpty);
      expect(CdcAnalysisResult.empty.analysisDiagnostics, isEmpty);
      expect(CdcAnalysisResult.empty.analysisDuration, Duration.zero);
    });

    test('severity counts match per-crossing severity', () {
      final s = sample();
      expect(s.criticalCount, 1);
      expect(s.warningCount, 1);
      expect(s.infoCount, 1);
    });

    test('domainById / crossingById lookup', () {
      final s = sample();
      expect(s.domainById('dom-A')!.clockSignalName, 'clk_a');
      expect(s.domainById('missing'), isNull);
      expect(s.crossingById('x-warn')!.signalName, 'a_meta');
      expect(s.crossingById('missing'), isNull);
    });

    test('parses an empty / partial JSON map without throwing', () {
      final empty = CdcAnalysisResult.fromJson(const <String, Object?>{});
      expect(empty.isEmpty, isTrue);
    });

    test('toString surfaces aggregate counts', () {
      final s = sample().toString();
      expect(s, contains('CdcAnalysisResult'));
      expect(s, contains('2 domains'));
      expect(s, contains('3 crossings'));
    });
  });
}
