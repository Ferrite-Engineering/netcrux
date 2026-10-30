// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/schematic/scope_layout_gate.dart';

void main() {
  group('ScopeLayoutGate', () {
    test('a scope at or under the limit is not deferred', () {
      expect(
        const ScopeLayoutGate(cellCount: 40000, limit: 40000).deferred,
        isFalse,
      );
      expect(
        const ScopeLayoutGate(cellCount: 1, limit: 40000).deferred,
        isFalse,
      );
      expect(ScopeLayoutGate.none.deferred, isFalse);
    });

    test('a scope over the limit is deferred', () {
      expect(
        const ScopeLayoutGate(cellCount: 40001, limit: 40000).deferred,
        isTrue,
      );
      expect(
        const ScopeLayoutGate(cellCount: 844208, limit: 40000).deferred,
        isTrue,
      );
    });

    test('a limit of zero or less turns the guard off', () {
      expect(
        const ScopeLayoutGate(cellCount: 5000000, limit: 0).deferred,
        isFalse,
      );
      expect(
        const ScopeLayoutGate(cellCount: 5000000, limit: -1).deferred,
        isFalse,
      );
    });

    test('an approved scope and a cone view are laid out', () {
      expect(
        const ScopeLayoutGate(
          cellCount: 844208,
          limit: 40000,
          approved: true,
        ).deferred,
        isFalse,
      );
      expect(
        const ScopeLayoutGate(
          cellCount: 844208,
          limit: 40000,
          inCone: true,
        ).deferred,
        isFalse,
      );
    });

    test('the memory estimate grows with the cell count', () {
      expect(estimateLayoutBytes(0), 0);
      expect(estimateLayoutBytes(1000), 1000 * kLayoutBytesPerCell);
      // The 844,208-cell flat scope of a one-million-gate design needs about
      // 105 GiB at the measured 130 KiB a cell.
      final gib = estimateLayoutBytes(844208) / (1024 * 1024 * 1024);
      expect(gib, closeTo(104.7, 0.5));
      expect(
        const ScopeLayoutGate(cellCount: 1000, limit: 10).estimatedBytes,
        estimateLayoutBytes(1000),
      );
    });

    test('equality and hash code follow every field', () {
      const a = ScopeLayoutGate(cellCount: 5, limit: 3);
      const b = ScopeLayoutGate(cellCount: 5, limit: 3);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(const ScopeLayoutGate(cellCount: 6, limit: 3)));
      expect(a, isNot(const ScopeLayoutGate(cellCount: 5, limit: 4)));
      expect(
        a,
        isNot(const ScopeLayoutGate(cellCount: 5, limit: 3, approved: true)),
      );
      expect(
        a,
        isNot(const ScopeLayoutGate(cellCount: 5, limit: 3, inCone: true)),
      );
    });

    test('the default limit is the measured one', () {
      expect(kDefaultLayoutCellLimit, 40000);
    });
  });
}
