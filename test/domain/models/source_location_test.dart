// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/source_location.dart';

void main() {
  group('SourceLocation', () {
    test('equality is value-based on all four fields', () {
      const a = SourceLocation(filePath: 'a.v', line: 10);
      const b = SourceLocation(filePath: 'a.v', line: 10);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('differs when filePath differs', () {
      const a = SourceLocation(filePath: 'a.v', line: 10);
      const b = SourceLocation(filePath: 'b.v', line: 10);
      expect(a, isNot(equals(b)));
    });

    test('differs when line differs', () {
      const a = SourceLocation(filePath: 'a.v', line: 10);
      const b = SourceLocation(filePath: 'a.v', line: 11);
      expect(a, isNot(equals(b)));
    });

    test('differs when column or lengthChars differs', () {
      const a = SourceLocation(filePath: 'a.v', line: 10, column: 5);
      const b = SourceLocation(filePath: 'a.v', line: 10, column: 6);
      const c = SourceLocation(filePath: 'a.v', line: 10, lengthChars: 3);
      expect(a, isNot(equals(b)));
      expect(a, isNot(equals(c)));
    });

    test('toString contains path, line, column, length', () {
      const loc = SourceLocation(
        filePath: 'a.v',
        line: 10,
        column: 3,
        lengthChars: 7,
      );
      expect(loc.toString(), contains('a.v:10'));
      expect(loc.toString(), contains(':3'));
      expect(loc.toString(), contains('+7'));
    });
  });
}
