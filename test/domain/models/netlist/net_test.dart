// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/netlist/bit_ref.dart';
import 'package:netcrux/domain/models/netlist/net.dart';

void main() {
  group('Net', () {
    test('fromJson parses name, bits, attributes, and hide_name', () {
      final net = Net.fromJson('data', const <String, Object?>{
        'hide_name': 0,
        'bits': <Object>[2, 3, '0', '1'],
        'attributes': <String, Object?>{'src': 'foo.v:5'},
      });
      expect(net.name, 'data');
      expect(net.bits, const <BitRef>[
        NetBit(2),
        NetBit(3),
        ConstantBit(ConstantBitValue.zero),
        ConstantBit(ConstantBitValue.one),
      ]);
      expect(net.attributes['src'], 'foo.v:5');
      expect(net.width, 4);
      expect(net.hideName, isFalse);
    });

    test('fromJson honors hide_name = 1', () {
      final net = Net.fromJson(r'$auto$net', const <String, Object?>{
        'hide_name': 1,
        'bits': <Object>[7],
        'attributes': <String, Object?>{},
      });
      expect(net.hideName, isTrue);
    });

    test('toJson round-trips through fromJson', () {
      const net = Net(
        name: 'd',
        bits: <BitRef>[NetBit(11), NetBit(12)],
        attributes: <String, String>{'src': 'x.v:1'},
      );
      final parsed = Net.fromJson('d', net.toJson());
      expect(parsed, equals(net));
    });

    test('equality and hashCode are value-based', () {
      const a = Net(
        name: 'd',
        bits: <BitRef>[NetBit(1)],
        attributes: <String, String>{'src': 'a'},
      );
      const b = Net(
        name: 'd',
        bits: <BitRef>[NetBit(1)],
        attributes: <String, String>{'src': 'a'},
      );
      const c = Net(
        name: 'd',
        bits: <BitRef>[NetBit(1), NetBit(2)],
        attributes: <String, String>{'src': 'a'},
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
    });

    test('copyWith replaces only specified fields', () {
      const net = Net(
        name: 'd',
        bits: <BitRef>[NetBit(1)],
        attributes: <String, String>{},
      );
      final renamed = net.copyWith(name: 'e');
      expect(renamed.name, 'e');
      expect(renamed.bits, net.bits);
    });
  });
}
