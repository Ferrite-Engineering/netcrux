// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/source_file_content.dart';
import 'package:netcrux/domain/models/source_token.dart';

void main() {
  group('SourceFileContent', () {
    test('empty has zero lines / tokens / empty path', () {
      const e = SourceFileContent.empty;
      expect(e.lines, isEmpty);
      expect(e.tokens, isEmpty);
      expect(e.filePath, isEmpty);
      expect(e.isEmpty, isTrue);
    });

    test('equality is value-based on all four fields', () {
      const a = SourceFileContent(
        filePath: 'a.v',
        lines: ['line 1', 'line 2'],
        tokens: <SourceToken>[],
        checksum: 'abc',
      );
      const b = SourceFileContent(
        filePath: 'a.v',
        lines: ['line 1', 'line 2'],
        tokens: <SourceToken>[],
        checksum: 'abc',
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('different checksum breaks equality', () {
      const a = SourceFileContent(
        filePath: 'a.v',
        lines: <String>[],
        tokens: <SourceToken>[],
        checksum: 'abc',
      );
      const b = SourceFileContent(
        filePath: 'a.v',
        lines: <String>[],
        tokens: <SourceToken>[],
        checksum: 'def',
      );
      expect(a, isNot(equals(b)));
    });

    test('lineCount tracks lines length', () {
      const c = SourceFileContent(
        filePath: 'a.v',
        lines: ['1', '2', '3'],
        tokens: <SourceToken>[],
      );
      expect(c.lineCount, equals(3));
    });
  });
}
