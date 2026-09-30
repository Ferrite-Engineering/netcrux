// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/netlist/bit_ref.dart';
import 'package:netcrux/domain/models/netlist/port.dart';
import 'package:netcrux/domain/models/netlist/port_direction.dart';

void main() {
  group('Port', () {
    test('fromJson parses direction and bits', () {
      final port = Port.fromJson('clk', const <String, Object?>{
        'direction': 'input',
        'bits': <Object>[2],
      });
      expect(port.name, 'clk');
      expect(port.direction, PortDirection.input);
      expect(port.bits, const <BitRef>[NetBit(2)]);
      expect(port.width, 1);
    });

    test('fromJson tolerates a missing bits array', () {
      final port = Port.fromJson('w', const <String, Object?>{
        'direction': 'output',
      });
      expect(port.bits, isEmpty);
      expect(port.width, 0);
    });

    test('toJson round-trips through fromJson', () {
      const port = Port(
        name: 'data',
        direction: PortDirection.output,
        bits: <BitRef>[
          NetBit(7),
          NetBit(8),
          ConstantBit(ConstantBitValue.x),
        ],
      );
      final json = port.toJson();
      final parsed = Port.fromJson('data', json);
      expect(parsed, equals(port));
    });

    test('equality and hashCode are value-based', () {
      const a = Port(
        name: 'p',
        direction: PortDirection.input,
        bits: <BitRef>[NetBit(1), NetBit(2)],
      );
      const b = Port(
        name: 'p',
        direction: PortDirection.input,
        bits: <BitRef>[NetBit(1), NetBit(2)],
      );
      const c = Port(
        name: 'p',
        direction: PortDirection.output,
        bits: <BitRef>[NetBit(1), NetBit(2)],
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
    });

    test('copyWith replaces only specified fields', () {
      const port = Port(
        name: 'a',
        direction: PortDirection.input,
        bits: <BitRef>[NetBit(1)],
      );
      final copy = port.copyWith(direction: PortDirection.output);
      expect(copy.name, 'a');
      expect(copy.direction, PortDirection.output);
      expect(copy.bits, port.bits);
    });
  });
}
