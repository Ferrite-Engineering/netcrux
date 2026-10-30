// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/features/inspector/services/parameter_value_text.dart';

void main() {
  group('parameterValueText', () {
    test('a 32-bit one reads as 1 and keeps its bits as the raw form', () {
      final text = parameterValueText('00000000000000000000000000000001');
      expect(text.display, '1');
      expect(text.raw, '00000000000000000000000000000001');
    });

    test('a single bit is already its number and has no raw form', () {
      for (final bit in <String>['0', '1']) {
        final text = parameterValueText(bit);
        expect(text.display, bit);
        expect(text.raw, isNull);
      }
    });

    test('a value of up to eight bits is decimal alone', () {
      final text = parameterValueText('00000000000000000000000011111111');
      expect(text.display, '255');
      expect(text.raw, '00000000000000000000000011111111');
    });

    test('a wider value gains its hex form, padded to the string width', () {
      final text = parameterValueText('00000000000000000000000100000000');
      expect(text.display, '256 (0x00000100)');
      expect(text.raw, '00000000000000000000000100000000');

      expect(
        parameterValueText('11111111111111110000000000000000').display,
        '4294901760 (0xFFFF0000)',
      );
    });

    test('a string wider than 64 bits shows hex alone', () {
      final bits = '1${'0' * 99}';
      final text = parameterValueText(bits);
      expect(text.display, '0x8${'0' * 24}');
      expect(text.raw, bits);
    });

    test('the largest 64-bit value stays exact in decimal', () {
      expect(
        parameterValueText('1' * 64).display,
        '18446744073709551615 (0xFFFFFFFFFFFFFFFF)',
      );
    });

    test('a string with x or z bits is left alone', () {
      for (final value in <String>['0000x001', '1z10', 'xxxxxxxx']) {
        final text = parameterValueText(value);
        expect(text.display, value);
        expect(text.raw, isNull);
      }
    });

    test('a real string is left alone', () {
      for (final value in <String>['sync_reset', r'\mem.v', '0.5', '']) {
        final text = parameterValueText(value);
        expect(text.display, value);
        expect(text.raw, isNull);
      }
    });

    test('a string Yosys marks with a trailing space is left alone', () {
      // Yosys appends a space to a string parameter that would otherwise
      // read as bits, so the two never collide.
      final text = parameterValueText('0101 ');
      expect(text.display, '0101 ');
      expect(text.raw, isNull);
    });
  });
}
