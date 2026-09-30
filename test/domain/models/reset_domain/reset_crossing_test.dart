// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/reset_domain/reset_crossing.dart';
import 'package:netcrux/domain/models/reset_domain/reset_crossing_kind.dart';
import 'package:netcrux/domain/models/reset_domain/reset_polarity.dart';
import 'package:netcrux/domain/models/reset_domain/reset_severity.dart';
import 'package:netcrux/domain/models/reset_domain/reset_synchronizer_status.dart';

void main() {
  group('ResetCrossing', () {
    const sigId = ElementId(kind: ElementKind.signal, path: 'top.q');
    const instA = ElementId(kind: ElementKind.signal, path: 'top.sync_a');
    const instB = ElementId(kind: ElementKind.signal, path: 'top.sync_b');

    ResetCrossing sample() => const ResetCrossing(
      id: 'crs-1',
      sourceDomainId: 'dom-a',
      destinationDomainId: 'dom-b',
      signalId: sigId,
      signalName: 'top.q',
      crossingKind: ResetCrossingKind.resetDeassertCrossing,
      synchronizerStatus: ResetSynchronizerStatus.properAsyncAssertSyncDeassert,
      severity: ResetSeverity.info,
      confidence: ResetConfidence.high,
      sourcePolarity: ResetPolarity.activeLow,
      synchronizerInstances: <ElementId>[instA, instB],
    );

    test('JSON round-trip preserves all fields', () {
      final original = sample();
      final json = original.toJson();
      final roundTripped = ResetCrossing.fromJson(json);
      expect(roundTripped, equals(original));
      expect(roundTripped.toJson(), equals(json));
    });

    test('copyWith replaces only requested fields', () {
      final original = sample();
      final next = original.copyWith(
        severity: ResetSeverity.critical,
      );
      expect(next.severity, ResetSeverity.critical);
      expect(next.signalId, original.signalId);
      expect(next.id, original.id);
    });

    test('equality + hashCode match field-by-field', () {
      expect(sample() == sample(), isTrue);
      expect(sample().hashCode, sample().hashCode);
      final mutated = sample().copyWith(signalName: 'top.other');
      expect(mutated == sample(), isFalse);
    });

    test('parses an empty / partial JSON map without throwing', () {
      final empty = ResetCrossing.fromJson(const <String, Object?>{});
      expect(empty.id, '');
      expect(empty.sourceDomainId, '');
      expect(empty.destinationDomainId, '');
      expect(
        empty.crossingKind,
        ResetCrossingKind.resetDeassertCrossing,
      );
      expect(
        empty.synchronizerStatus,
        ResetSynchronizerStatus.missingSynchronizer,
      );
      expect(empty.synchronizerInstances, isEmpty);
      expect(empty.sourcePolarity, ResetPolarity.unknown);
    });

    test('toString surfaces the salient fields for debug printing', () {
      final s = sample().toString();
      expect(s, contains('ResetCrossing'));
      expect(s, contains('top.q'));
      expect(s, contains('dom-a'));
      expect(s, contains('dom-b'));
    });
  });

  group('ResetCrossing.severityFor — full matrix', () {
    // Severity is keyed entirely off the (kind × status) pair, with a
    // confidence drop for dataCrossesResetBoundary + missing. Polarity
    // is part of the public API but isn't yet a severity input in
    // v1 — it's reserved for v2 polish (opposite-polarity glitch
    // analysis).

    test('proper async-assert + sync-deassert is info for every kind', () {
      for (final kind in ResetCrossingKind.values) {
        expect(
          ResetCrossing.severityFor(
            kind,
            ResetSynchronizerStatus.properAsyncAssertSyncDeassert,
            ResetPolarity.activeLow,
          ),
          ResetSeverity.info,
          reason: 'kind=$kind',
        );
      }
    });

    test('proper sync/sync is info for every kind', () {
      for (final kind in ResetCrossingKind.values) {
        expect(
          ResetCrossing.severityFor(
            kind,
            ResetSynchronizerStatus.properSyncAssertSyncDeassert,
            ResetPolarity.activeHigh,
          ),
          ResetSeverity.info,
          reason: 'kind=$kind',
        );
      }
    });

    test('vendor reset synchronizer is info for every kind', () {
      for (final kind in ResetCrossingKind.values) {
        expect(
          ResetCrossing.severityFor(
            kind,
            ResetSynchronizerStatus.properResetSynchronizer,
            ResetPolarity.activeHigh,
          ),
          ResetSeverity.info,
        );
      }
    });

    test('custom synchronizer is info for every kind', () {
      for (final kind in ResetCrossingKind.values) {
        expect(
          ResetCrossing.severityFor(
            kind,
            ResetSynchronizerStatus.customSynchronizer,
            ResetPolarity.activeHigh,
          ),
          ResetSeverity.info,
        );
      }
    });

    test('glitchProne is warning for every crossing kind', () {
      expect(
        ResetCrossing.severityFor(
          ResetCrossingKind.dataCrossesResetBoundary,
          ResetSynchronizerStatus.glitchProne,
          ResetPolarity.activeHigh,
        ),
        ResetSeverity.warning,
      );
      expect(
        ResetCrossing.severityFor(
          ResetCrossingKind.resetDeassertCrossing,
          ResetSynchronizerStatus.glitchProne,
          ResetPolarity.activeLow,
        ),
        ResetSeverity.warning,
      );
    });

    test('missing synchronizer on reset deassert is always critical', () {
      for (final pol in ResetPolarity.values) {
        expect(
          ResetCrossing.severityFor(
            ResetCrossingKind.resetDeassertCrossing,
            ResetSynchronizerStatus.missingSynchronizer,
            pol,
          ),
          ResetSeverity.critical,
          reason: 'polarity=$pol',
        );
      }
    });

    test('missing synchronizer on data crossing — critical at high '
        'confidence, warning at medium/low', () {
      expect(
        ResetCrossing.severityFor(
          ResetCrossingKind.dataCrossesResetBoundary,
          ResetSynchronizerStatus.missingSynchronizer,
          ResetPolarity.activeHigh,
        ),
        ResetSeverity.critical,
      );
      expect(
        ResetCrossing.severityFor(
          ResetCrossingKind.dataCrossesResetBoundary,
          ResetSynchronizerStatus.missingSynchronizer,
          ResetPolarity.activeHigh,
          confidence: ResetConfidence.medium,
        ),
        ResetSeverity.warning,
      );
      expect(
        ResetCrossing.severityFor(
          ResetCrossingKind.dataCrossesResetBoundary,
          ResetSynchronizerStatus.missingSynchronizer,
          ResetPolarity.activeHigh,
          confidence: ResetConfidence.low,
        ),
        ResetSeverity.warning,
      );
    });
  });

  group('ResetSeverity / ResetConfidence enums', () {
    test('ResetSeverity JSON round-trip preserves every value', () {
      for (final v in ResetSeverity.values) {
        expect(ResetSeverity.fromJsonString(v.toJsonString()), v);
      }
    });

    test('ResetSeverity unknown raw maps to warning', () {
      expect(
        ResetSeverity.fromJsonString('garbage'),
        ResetSeverity.warning,
      );
    });

    test('ResetConfidence JSON round-trip preserves every value', () {
      for (final v in ResetConfidence.values) {
        expect(ResetConfidence.fromJsonString(v.toJsonString()), v);
      }
    });

    test('ResetConfidence unknown raw maps to medium', () {
      expect(
        ResetConfidence.fromJsonString('garbage'),
        ResetConfidence.medium,
      );
    });
  });

  group('ResetCrossingKind / ResetSynchronizerStatus enums', () {
    test('ResetCrossingKind JSON round-trip preserves every value', () {
      for (final v in ResetCrossingKind.values) {
        expect(ResetCrossingKind.fromJsonString(v.toJsonString()), v);
      }
    });

    test('ResetCrossingKind unknown raw maps to resetDeassertCrossing', () {
      expect(
        ResetCrossingKind.fromJsonString('garbage'),
        ResetCrossingKind.resetDeassertCrossing,
      );
    });

    test('ResetSynchronizerStatus JSON round-trip preserves every value', () {
      for (final v in ResetSynchronizerStatus.values) {
        expect(
          ResetSynchronizerStatus.fromJsonString(v.toJsonString()),
          v,
        );
      }
    });

    test('ResetSynchronizerStatus unknown raw maps to missingSynchronizer', () {
      expect(
        ResetSynchronizerStatus.fromJsonString('garbage'),
        ResetSynchronizerStatus.missingSynchronizer,
      );
    });
  });
}
