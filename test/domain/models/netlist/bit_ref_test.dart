// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/netlist/bit_ref.dart';

void main() {
  group('BitRef.fromJson', () {
    test('parses integer net ids as NetBit', () {
      expect(BitRef.fromJson(42), const NetBit(42));
      expect(BitRef.fromJson(0), const NetBit(0));
    });

    test('parses string constants as ConstantBit', () {
      expect(
        BitRef.fromJson('0'),
        const ConstantBit(ConstantBitValue.zero),
      );
      expect(
        BitRef.fromJson('1'),
        const ConstantBit(ConstantBitValue.one),
      );
      expect(
        BitRef.fromJson('x'),
        const ConstantBit(ConstantBitValue.x),
      );
      expect(
        BitRef.fromJson('z'),
        const ConstantBit(ConstantBitValue.z),
      );
    });

    test('accepts uppercase X / Z for resilience', () {
      expect(
        BitRef.fromJson('X'),
        const ConstantBit(ConstantBitValue.x),
      );
      expect(
        BitRef.fromJson('Z'),
        const ConstantBit(ConstantBitValue.z),
      );
    });

    test('parses numeric strings as NetBit', () {
      expect(BitRef.fromJson('123'), const NetBit(123));
    });

    test('rejects unrecognized shapes with FormatException', () {
      expect(() => BitRef.fromJson(null), throwsFormatException);
      expect(() => BitRef.fromJson(const <int>[1]), throwsFormatException);
      expect(() => BitRef.fromJson('garbage'), throwsFormatException);
    });
  });

  group('BitRef equality and serialization', () {
    test('NetBit equality and hashCode are value-based', () {
      const a = NetBit(7);
      const b = NetBit(7);
      const c = NetBit(8);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
    });

    test('ConstantBit equality and hashCode are value-based', () {
      const a = ConstantBit(ConstantBitValue.x);
      const b = ConstantBit(ConstantBitValue.x);
      const c = ConstantBit(ConstantBitValue.z);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
    });

    test('toJson round-trips through fromJson', () {
      const inputs = <BitRef>[
        NetBit(42),
        ConstantBit(ConstantBitValue.zero),
        ConstantBit(ConstantBitValue.one),
        ConstantBit(ConstantBitValue.x),
        ConstantBit(ConstantBitValue.z),
      ];
      for (final bit in inputs) {
        expect(BitRef.fromJson(bit.toJson()), equals(bit));
      }
    });
  });
}
