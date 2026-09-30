// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/custom_cell_symbol/custom_cell_symbol.dart';
import 'package:netcrux/domain/models/custom_cell_symbol/custom_cell_symbol_match.dart';

void main() {
  group('CustomCellSymbolMatch', () {
    const symbol = CustomCellSymbol(
      id: 'symbol-1',
      moduleType: 'my_alu',
      kind: CustomCellSymbolKind.svg,
      content: '<svg/>',
      width: 120,
      height: 80,
      portAnchors: {},
      createdAt: '',
      updatedAt: '',
    );

    test('equality is field-by-field', () {
      const a = CustomCellSymbolMatch(
        symbol: symbol,
        kind: CustomCellSymbolMatchKind.exactMatch,
      );
      const b = CustomCellSymbolMatch(
        symbol: symbol,
        kind: CustomCellSymbolMatchKind.exactMatch,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('different kinds break equality', () {
      const exact = CustomCellSymbolMatch(
        symbol: symbol,
        kind: CustomCellSymbolMatchKind.exactMatch,
      );
      const pattern = CustomCellSymbolMatch(
        symbol: symbol,
        kind: CustomCellSymbolMatchKind.patternMatch,
      );
      expect(exact, isNot(equals(pattern)));
    });

    test('CustomCellSymbolMatchKind enum carries the v1 + future values', () {
      expect(
        CustomCellSymbolMatchKind.values,
        containsAll(<CustomCellSymbolMatchKind>[
          CustomCellSymbolMatchKind.exactMatch,
          CustomCellSymbolMatchKind.patternMatch,
          CustomCellSymbolMatchKind.wildcardFallback,
        ]),
      );
    });

    test('toString includes the kind name', () {
      const m = CustomCellSymbolMatch(
        symbol: symbol,
        kind: CustomCellSymbolMatchKind.exactMatch,
      );
      expect(m.toString(), contains('exactMatch'));
    });
  });
}
