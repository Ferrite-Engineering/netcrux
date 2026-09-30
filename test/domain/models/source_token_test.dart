// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/source_token.dart';

void main() {
  group('SourceToken', () {
    test('equality is value-based across every field', () {
      const a = SourceToken(
        line: 5,
        columnStart: 1,
        columnEnd: 7,
        kind: SourceTokenKind.keyword,
      );
      const b = SourceToken(
        line: 5,
        columnStart: 1,
        columnEnd: 7,
        kind: SourceTokenKind.keyword,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('differing kind breaks equality', () {
      const a = SourceToken(
        line: 5,
        columnStart: 1,
        columnEnd: 7,
        kind: SourceTokenKind.keyword,
      );
      const b = SourceToken(
        line: 5,
        columnStart: 1,
        columnEnd: 7,
        kind: SourceTokenKind.identifier,
      );
      expect(a, isNot(equals(b)));
    });

    test('width is columnEnd - columnStart', () {
      const t = SourceToken(
        line: 1,
        columnStart: 3,
        columnEnd: 10,
        kind: SourceTokenKind.identifier,
      );
      expect(t.widthChars, equals(7));
    });

    test('associatedElementId breaks equality when present on one side', () {
      const eid = ElementId(kind: ElementKind.instance, path: 'top.alu');
      const withId = SourceToken(
        line: 3,
        columnStart: 1,
        columnEnd: 8,
        kind: SourceTokenKind.identifier,
        associatedElementId: eid,
      );
      const noId = SourceToken(
        line: 3,
        columnStart: 1,
        columnEnd: 8,
        kind: SourceTokenKind.identifier,
      );
      expect(withId, isNot(equals(noId)));
    });
  });
}
