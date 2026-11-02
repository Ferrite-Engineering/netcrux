// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The expected gates come from the Boolean meaning of each function, written
// out by hand, never from the classifier's own output.

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/services/liberty/liberty_function.dart';

/// Every row of the truth table of [text] over [vars], `1` or `0` each, row
/// `i` binding bit `k` of `i` to `vars[k]`.
String _table(String text, List<String> vars) {
  final e = LibertyExpression.tryParse(text)!;
  return <String>[
    for (var row = 0; row < 1 << vars.length; row++)
      if (e.evaluate(vars, row)) '1' else '0',
  ].join();
}

void main() {
  group('LibertyExpression', () {
    test('inversion binds tighter than XOR, XOR than AND, AND than OR', () {
      // A + B C reads as A + (B C).
      expect(_table('A + B C', <String>['A', 'B', 'C']), '01010111');
      // !A ^ B reads as (!A) ^ B: true when A equals B.
      expect(_table('!A ^ B', <String>['A', 'B']), '1001');
      // A B ^ C reads as A (B ^ C).
      expect(_table('A B ^ C', <String>['A', 'B', 'C']), '00010100');
    });

    test('every spelling of AND, OR and NOT means the same', () {
      const and = '0001';
      for (final text in <String>['A&B', 'A*B', 'A B', '(A)(B)', 'A & B']) {
        expect(_table(text, <String>['A', 'B']), and, reason: text);
      }
      const or = '0111';
      for (final text in <String>['A|B', 'A+B', '(A + B)']) {
        expect(_table(text, <String>['A', 'B']), or, reason: text);
      }
      const nand = '1110';
      for (final text in <String>['!(A&B)', "(A B)'", '!A+!B', "A'+B'"]) {
        expect(_table(text, <String>['A', 'B']), nand, reason: text);
      }
    });

    test('constants and double inversion', () {
      expect(_table('1', <String>['A']), '11');
      expect(_table('0', <String>['A']), '00');
      expect(_table('!!A', <String>['A']), '01');
      expect(_table("A''", <String>['A']), '01');
    });

    test('names keep brackets and dots', () {
      expect(LibertyExpression.tryParse('D[0] & S.1')!.variables, <String>[
        'D[0]',
        'S.1',
      ]);
    });

    test('malformed text does not parse', () {
      for (final text in <String>['', 'A &', '(A', 'A)', '& B', '!', '+']) {
        expect(LibertyExpression.tryParse(text), isNull, reason: text);
      }
    });
  });

  group('classifyLibertyFunction', () {
    LibertyGate? classify(String f, List<String> inputs) =>
        classifyLibertyFunction(f, inputs);

    test('one input: buffer and inverter', () {
      expect(classify('A', <String>['A']), LibertyGate.buffer);
      expect(classify('!A', <String>['A']), LibertyGate.inverter);
      expect(classify("A'", <String>['A']), LibertyGate.inverter);
    });

    test('the simple gates over two to four inputs', () {
      expect(classify('A1 & A2', <String>['A1', 'A2']), LibertyGate.and);
      expect(
        classify('!(A & B & C)', <String>['A', 'B', 'C']),
        LibertyGate.nand,
      );
      expect(classify('!A + !B', <String>['A', 'B']), LibertyGate.nand);
      expect(classify('A+B+C+D', <String>['A', 'B', 'C', 'D']), LibertyGate.or);
      expect(classify('!(A|B)', <String>['A', 'B']), LibertyGate.nor);
      expect(classify('!A & !B', <String>['A', 'B']), LibertyGate.nor);
      expect(classify('A^B', <String>['A', 'B']), LibertyGate.xor);
      expect(classify('A^B^C', <String>['A', 'B', 'C']), LibertyGate.xor);
      expect(classify('!(A^B)', <String>['A', 'B']), LibertyGate.xnor);
      expect(classify('(A B) + (!A !B)', <String>['A', 'B']), LibertyGate.xnor);
    });

    test('a two-input mux, whichever pin selects', () {
      const pins = <String>['A0', 'A1', 'S'];
      expect(classify('(A0 & !S) | (A1 & S)', pins), LibertyGate.mux2);
      expect(classify('(S & A0) + (!S & A1)', pins), LibertyGate.mux2);
      // The sky130 form: the select is the last pin.
      expect(
        classify('(A0&!S)|(A1&S)', const <String>['A0', 'A1', 'S']),
        LibertyGate.mux2,
      );
    });

    test('compound gates, inverted muxes and constants are none', () {
      // AOI21: !((A1&A2)|B1).
      expect(classify('!((A1&A2)|B1)', <String>['A1', 'A2', 'B1']), isNull);
      // OAI21.
      expect(classify('!((A1|A2)&B1)', <String>['A1', 'A2', 'B1']), isNull);
      // An inverting mux.
      expect(classify('!((A0&!S)|(A1&S))', <String>['A0', 'A1', 'S']), isNull);
      // A majority gate.
      expect(classify('A B + B C + A C', <String>['A', 'B', 'C']), isNull);
    });

    test('a function that does not read every input, or reads another pin, '
        'is none', () {
      // A tri-state buffer's enable is not in its function.
      expect(classify('A', <String>['A', 'TE_B']), isNull);
      expect(classify('A & X', <String>['A', 'B']), isNull);
      expect(classify('!(A&B', <String>['A', 'B']), isNull);
    });

    test('more inputs than the table covers is none', () {
      final pins = <String>[for (var i = 0; i < 7; i++) 'A$i'];
      expect(classify(pins.join('&'), pins), isNull);
    });
  });
}
