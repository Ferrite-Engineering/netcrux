// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/reset_domain/reset_domain.dart';
import 'package:netcrux/domain/models/reset_domain/reset_polarity.dart';
import 'package:netcrux/domain/models/reset_domain/reset_source_kind.dart';
import 'package:netcrux/domain/models/reset_domain/reset_synchronicity.dart';

void main() {
  group('ResetDomain', () {
    const resetId = ElementId(kind: ElementKind.signal, path: 'top.rst_n');
    const regId = ElementId(kind: ElementKind.signal, path: 'top.dut.r0');
    const netId = ElementId(kind: ElementKind.signal, path: 'top.dut.q0');

    ResetDomain sample() => const ResetDomain(
      id: 'dom-1',
      resetSignalId: resetId,
      resetSignalName: 'rst_n',
      polarity: ResetPolarity.activeLow,
      synchronicity: ResetSynchronicity.asyncAssertSyncDeassert,
      sourceKind: ResetSourceKind.primaryInput,
      memberRegisters: <ElementId>[regId],
      memberNets: <ElementId>[netId],
    );

    test('JSON round-trip preserves all fields', () {
      final original = sample();
      final json = original.toJson();
      final roundTripped = ResetDomain.fromJson(json);
      expect(roundTripped, equals(original));
      expect(roundTripped.toJson(), equals(json));
    });

    test('copyWith replaces only requested fields', () {
      final original = sample();
      final next = original.copyWith(resetSignalName: 'por_reset');
      expect(next.resetSignalName, 'por_reset');
      expect(next.resetSignalId, original.resetSignalId);
      expect(next.polarity, original.polarity);
      expect(next.id, original.id);
    });

    test('equality + hashCode match field-by-field', () {
      expect(sample() == sample(), isTrue);
      expect(sample().hashCode, sample().hashCode);
      final mutated = sample().copyWith(resetSignalName: 'other');
      expect(mutated == sample(), isFalse);
    });

    test('parses an empty / partial JSON map without throwing', () {
      final empty = ResetDomain.fromJson(const <String, Object?>{});
      expect(empty.id, '');
      expect(empty.memberNets, isEmpty);
      expect(empty.memberRegisters, isEmpty);
      expect(empty.polarity, ResetPolarity.unknown);
      expect(empty.synchronicity, ResetSynchronicity.unknown);
      expect(empty.sourceKind, ResetSourceKind.unknown);
    });

    test('toString surfaces the salient fields for debug printing', () {
      final s = sample().toString();
      expect(s, contains('ResetDomain'));
      expect(s, contains('rst_n'));
      expect(s, contains('activeLow'));
      expect(s, contains('asyncAssertSyncDeassert'));
      expect(s, contains('primaryInput'));
    });
  });

  group('ResetPolarity', () {
    test('JSON round-trip preserves every value', () {
      for (final v in ResetPolarity.values) {
        expect(ResetPolarity.fromJsonString(v.toJsonString()), v);
      }
    });

    test('unknown raw maps to unknown', () {
      expect(
        ResetPolarity.fromJsonString('garbage'),
        ResetPolarity.unknown,
      );
    });
  });

  group('ResetSynchronicity', () {
    test('JSON round-trip preserves every value', () {
      for (final v in ResetSynchronicity.values) {
        expect(ResetSynchronicity.fromJsonString(v.toJsonString()), v);
      }
    });

    test('unknown raw maps to unknown', () {
      expect(
        ResetSynchronicity.fromJsonString('garbage'),
        ResetSynchronicity.unknown,
      );
    });
  });

  group('ResetSourceKind', () {
    test('JSON round-trip preserves every value', () {
      for (final v in ResetSourceKind.values) {
        expect(ResetSourceKind.fromJsonString(v.toJsonString()), v);
      }
    });

    test('unknown raw maps to unknown', () {
      expect(
        ResetSourceKind.fromJsonString('garbage'),
        ResetSourceKind.unknown,
      );
    });
  });
}
