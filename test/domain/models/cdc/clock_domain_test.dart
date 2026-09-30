// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/cdc/clock_domain.dart';
import 'package:netcrux/domain/models/cdc/clock_domain_source_kind.dart';

void main() {
  group('ClockDomain', () {
    const clockId = ElementId(kind: ElementKind.signal, path: 'top.clk_100');
    const regId = ElementId(kind: ElementKind.signal, path: 'top.dut.r0');
    const netId = ElementId(kind: ElementKind.signal, path: 'top.dut.q0');

    ClockDomain sample() => const ClockDomain(
      id: 'dom-1',
      clockSignalId: clockId,
      clockSignalName: 'clk_100',
      frequencyHint: '100MHz',
      sourceKind: ClockDomainSourceKind.primaryInput,
      memberRegisters: <ElementId>[regId],
      memberNets: <ElementId>[netId],
    );

    test('JSON round-trip preserves all fields', () {
      final original = sample();
      final json = original.toJson();
      final roundTripped = ClockDomain.fromJson(json);
      expect(roundTripped, equals(original));
      expect(roundTripped.toJson(), equals(json));
    });

    test('copyWith replaces only requested fields', () {
      final original = sample();
      final next = original.copyWith(clockSignalName: 'clk_50');
      expect(next.clockSignalName, 'clk_50');
      expect(next.clockSignalId, original.clockSignalId);
      expect(next.id, original.id);
    });

    test('clearFrequencyHint zeroes the hint', () {
      final original = sample();
      final next = original.copyWith(clearFrequencyHint: true);
      expect(next.frequencyHint, isNull);
    });

    test('equality + hashCode match field-by-field', () {
      expect(sample() == sample(), isTrue);
      expect(sample().hashCode, sample().hashCode);
      final mutated = sample().copyWith(clockSignalName: 'other');
      expect(mutated == sample(), isFalse);
    });

    test('parses an empty / partial JSON map without throwing', () {
      final empty = ClockDomain.fromJson(const <String, Object?>{});
      expect(empty.id, '');
      expect(empty.memberNets, isEmpty);
      expect(empty.memberRegisters, isEmpty);
      expect(empty.frequencyHint, isNull);
      expect(empty.sourceKind, ClockDomainSourceKind.unknown);
    });

    test('omits the frequencyHint key in toJson when null', () {
      final noHint = sample().copyWith(clearFrequencyHint: true);
      expect(noHint.toJson().containsKey('frequencyHint'), isFalse);
    });

    test('toString surfaces the salient fields for debug printing', () {
      final s = sample().toString();
      expect(s, contains('ClockDomain'));
      expect(s, contains('clk_100'));
      expect(s, contains('primaryInput'));
    });
  });
}
