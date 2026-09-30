// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/cdc/clock_domain_source_kind.dart';

void main() {
  group('ClockDomainSourceKind', () {
    test('round-trips through toJsonString / fromJsonString', () {
      for (final value in ClockDomainSourceKind.values) {
        expect(
          ClockDomainSourceKind.fromJsonString(value.toJsonString()),
          value,
        );
      }
    });

    test('unknown raw string maps to unknown', () {
      expect(
        ClockDomainSourceKind.fromJsonString('nonsense'),
        ClockDomainSourceKind.unknown,
      );
    });

    test('exposes every documented variant', () {
      expect(
        ClockDomainSourceKind.values.map((v) => v.name).toSet(),
        equals(<String>{
          'primaryInput',
          'pll',
          'gatedClock',
          'clockMux',
          'divider',
          'unknown',
        }),
      );
    });
  });
}
