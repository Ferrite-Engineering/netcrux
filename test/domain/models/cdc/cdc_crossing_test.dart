// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/cdc/cdc_crossing.dart';
import 'package:netcrux/domain/models/cdc/cdc_crossing_kind.dart';
import 'package:netcrux/domain/models/cdc/cdc_pulse_risk.dart';
import 'package:netcrux/domain/models/cdc/cdc_severity.dart';
import 'package:netcrux/domain/models/cdc/cdc_synchronizer_status.dart';

void main() {
  group('CdcCrossing', () {
    const signalId = ElementId(kind: ElementKind.signal, path: 'top.dut.x');
    const syncId = ElementId(
      kind: ElementKind.instance,
      path: 'top.dut.sync_0',
    );

    CdcCrossing sample() => const CdcCrossing(
      id: 'cross-1',
      sourceDomainId: 'dom-A',
      destinationDomainId: 'dom-B',
      signalId: signalId,
      signalName: 'x',
      crossingKind: CdcCrossingKind.singleBit,
      synchronizerStatus: CdcSynchronizerStatus.properTwoFlopSync,
      severity: CdcSeverity.info,
      confidence: CdcConfidence.high,
      synchronizerInstances: <ElementId>[syncId],
    );

    test('JSON round-trip preserves all fields', () {
      final original = sample();
      final json = original.toJson();
      final roundTripped = CdcCrossing.fromJson(json);
      expect(roundTripped, equals(original));
    });

    test('copyWith replaces only requested fields', () {
      final original = sample();
      final next = original.copyWith(severity: CdcSeverity.critical);
      expect(next.severity, CdcSeverity.critical);
      expect(next.id, original.id);
      expect(next.synchronizerInstances, original.synchronizerInstances);
    });

    test('equality and hashCode are field-by-field', () {
      expect(sample() == sample(), isTrue);
      expect(sample().hashCode, sample().hashCode);
      expect(
        sample() == sample().copyWith(signalName: 'other'),
        isFalse,
      );
    });

    test('toString surfaces salient fields', () {
      final s = sample().toString();
      expect(s, contains('CdcCrossing'));
      expect(s, contains('singleBit'));
      expect(s, contains('properTwoFlopSync'));
    });

    test('pulseRisk round-trips and is omitted from JSON when absent', () {
      expect(sample().toJson().containsKey('pulseRisk'), isFalse);
      expect(CdcCrossing.fromJson(sample().toJson()).pulseRisk, isNull);
      for (final risk in CdcPulseRisk.values) {
        final withRisk = sample().copyWith(pulseRisk: risk);
        expect(withRisk.toJson()['pulseRisk'], risk.name);
        expect(CdcCrossing.fromJson(withRisk.toJson()), equals(withRisk));
        expect(withRisk == sample(), isFalse);
        expect(withRisk.toString(), contains(risk.name));
        expect(
          withRisk.copyWith(clearPulseRisk: true).pulseRisk,
          isNull,
        );
      }
    });
  });

  group('CdcPulseRisk', () {
    test('null stays null; an unknown tag claims the least', () {
      expect(CdcPulseRisk.fromJsonString(null), isNull);
      expect(
        CdcPulseRisk.fromJsonString('garbage'),
        CdcPulseRisk.clockRatesUnknown,
      );
    });
  });

  group('CdcCrossing.severityWithPulseRisk', () {
    test('no pulse risk is the plain matrix', () {
      for (final kind in CdcCrossingKind.values) {
        for (final status in CdcSynchronizerStatus.values) {
          expect(
            CdcCrossing.severityWithPulseRisk(kind, status, null),
            CdcCrossing.severityFor(kind, status),
          );
        }
      }
    });

    test('a pulse risk raises info to warning and never lowers', () {
      for (final risk in CdcPulseRisk.values) {
        for (final kind in CdcCrossingKind.values) {
          for (final status in CdcSynchronizerStatus.values) {
            final base = CdcCrossing.severityFor(kind, status);
            final raised = CdcCrossing.severityWithPulseRisk(
              kind,
              status,
              risk,
            );
            expect(
              raised,
              base == CdcSeverity.info ? CdcSeverity.warning : base,
              reason: '$risk $kind $status',
            );
          }
        }
      }
    });
  });

  group('CdcCrossing.severityFor matrix', () {
    // Missing synchronizer is always critical regardless of kind.
    test('missing synchronizer is critical for every kind', () {
      for (final kind in CdcCrossingKind.values) {
        expect(
          CdcCrossing.severityFor(
            kind,
            CdcSynchronizerStatus.missingSynchronizer,
          ),
          CdcSeverity.critical,
          reason: 'kind=$kind',
        );
      }
    });

    test('metastable is critical for multi-bit, warning otherwise', () {
      expect(
        CdcCrossing.severityFor(
          CdcCrossingKind.multiBit,
          CdcSynchronizerStatus.metastable,
        ),
        CdcSeverity.critical,
      );
      for (final kind in <CdcCrossingKind>[
        CdcCrossingKind.singleBit,
        CdcCrossingKind.control,
        CdcCrossingKind.handshake,
      ]) {
        expect(
          CdcCrossing.severityFor(kind, CdcSynchronizerStatus.metastable),
          CdcSeverity.warning,
          reason: 'kind=$kind',
        );
      }
    });

    test(
      '2-flop / 3-flop sync are critical for multi-bit, info otherwise',
      () {
        for (final status in <CdcSynchronizerStatus>[
          CdcSynchronizerStatus.properTwoFlopSync,
          CdcSynchronizerStatus.properThreeFlopSync,
        ]) {
          expect(
            CdcCrossing.severityFor(CdcCrossingKind.multiBit, status),
            CdcSeverity.critical,
            reason: 'multi-bit + $status must be critical',
          );
          for (final kind in <CdcCrossingKind>[
            CdcCrossingKind.singleBit,
            CdcCrossingKind.control,
            CdcCrossingKind.handshake,
          ]) {
            expect(
              CdcCrossing.severityFor(kind, status),
              CdcSeverity.info,
              reason: '$kind + $status must be info',
            );
          }
        }
      },
    );

    test(
      'handshakeProtocol is warning on multi-bit, info on every other kind',
      () {
        expect(
          CdcCrossing.severityFor(
            CdcCrossingKind.multiBit,
            CdcSynchronizerStatus.handshakeProtocol,
          ),
          CdcSeverity.warning,
        );
        for (final kind in <CdcCrossingKind>[
          CdcCrossingKind.singleBit,
          CdcCrossingKind.control,
          CdcCrossingKind.handshake,
        ]) {
          expect(
            CdcCrossing.severityFor(
              kind,
              CdcSynchronizerStatus.handshakeProtocol,
            ),
            CdcSeverity.info,
            reason: 'kind=$kind',
          );
        }
      },
    );

    test('asyncFifo + customSynchronizer are info on every kind', () {
      for (final status in <CdcSynchronizerStatus>[
        CdcSynchronizerStatus.asyncFifo,
        CdcSynchronizerStatus.customSynchronizer,
      ]) {
        for (final kind in CdcCrossingKind.values) {
          expect(
            CdcCrossing.severityFor(kind, status),
            CdcSeverity.info,
            reason: 'kind=$kind status=$status',
          );
        }
      }
    });
  });

  group('CdcSeverity', () {
    test('round-trips through JSON string', () {
      for (final v in CdcSeverity.values) {
        expect(CdcSeverity.fromJsonString(v.toJsonString()), v);
      }
    });

    test('unknown raw string maps to warning (safe default)', () {
      expect(CdcSeverity.fromJsonString('nope'), CdcSeverity.warning);
    });
  });

  group('CdcConfidence', () {
    test('round-trips through JSON string', () {
      for (final v in CdcConfidence.values) {
        expect(CdcConfidence.fromJsonString(v.toJsonString()), v);
      }
    });

    test('unknown raw string maps to medium', () {
      expect(CdcConfidence.fromJsonString('nope'), CdcConfidence.medium);
    });
  });

  group('CdcSynchronizerStatus', () {
    test('round-trips through JSON string', () {
      for (final v in CdcSynchronizerStatus.values) {
        expect(CdcSynchronizerStatus.fromJsonString(v.toJsonString()), v);
      }
    });

    test('unknown raw string maps to missingSynchronizer (conservative)', () {
      expect(
        CdcSynchronizerStatus.fromJsonString('nope'),
        CdcSynchronizerStatus.missingSynchronizer,
      );
    });
  });

  group('CdcCrossingKind', () {
    test('round-trips through JSON string', () {
      for (final v in CdcCrossingKind.values) {
        expect(CdcCrossingKind.fromJsonString(v.toJsonString()), v);
      }
    });

    test('unknown raw string maps to singleBit (permissive default)', () {
      expect(CdcCrossingKind.fromJsonString('nope'), CdcCrossingKind.singleBit);
    });
  });
}
