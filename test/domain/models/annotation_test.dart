// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/annotation.dart';
import 'package:netcrux/domain/models/bookmark.dart';

void main() {
  group('Annotation', () {
    test('equality + hashCode', () {
      const a = Annotation(
        id: 'a1',
        targetKind: BookmarkTargetKind.cell,
        targetId: 'u_alu',
        body: 'Suspect: glitchy clock domain crossing here.',
        createdAtMillis: 1000,
        updatedAtMillis: 1000,
      );
      const b = Annotation(
        id: 'a1',
        targetKind: BookmarkTargetKind.cell,
        targetId: 'u_alu',
        body: 'Suspect: glitchy clock domain crossing here.',
        createdAtMillis: 1000,
        updatedAtMillis: 1000,
      );
      const c = Annotation(
        id: 'a1',
        targetKind: BookmarkTargetKind.cell,
        targetId: 'u_alu',
        body: 'Different body',
        createdAtMillis: 1000,
        updatedAtMillis: 1000,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('copyWith updates body + updatedAtMillis explicitly', () {
      const original = Annotation(
        id: 'a1',
        targetKind: BookmarkTargetKind.net,
        targetId: 'e_42',
        body: 'old',
        createdAtMillis: 100,
        updatedAtMillis: 100,
      );
      final edited = original.copyWith(
        body: 'new body',
        updatedAtMillis: 200,
      );
      expect(edited.body, 'new body');
      expect(edited.updatedAtMillis, 200);
      expect(edited.createdAtMillis, 100);
    });

    test('toJson + fromJson round-trip with author', () {
      const annotation = Annotation(
        id: 'a1',
        targetKind: BookmarkTargetKind.cell,
        targetId: 'u_alu',
        body: '# Note\nMarkdown body.',
        createdAtMillis: 12345,
        updatedAtMillis: 67890,
        author: 'martin',
      );
      final json = annotation.toJson();
      final restored = Annotation.fromJson(json);
      expect(restored, equals(annotation));
    });

    test('toJson omits null author', () {
      const annotation = Annotation(
        id: 'a1',
        targetKind: BookmarkTargetKind.scope,
        targetId: 'top',
        body: 'unattributed',
        createdAtMillis: 1,
        updatedAtMillis: 1,
      );
      expect(annotation.toJson().containsKey('author'), isFalse);
    });

    test('fromJson returns null on missing required fields', () {
      expect(
        Annotation.fromJson(const <String, Object?>{'id': 'a1'}),
        isNull,
      );
      expect(
        Annotation.fromJson(const <String, Object?>{
          'id': '',
          'targetKind': 'cell',
          'targetId': 'u',
          'body': 'x',
          'createdAtMillis': 1,
          'updatedAtMillis': 1,
        }),
        isNull,
      );
    });

    test('fromJson returns null on unknown targetKind', () {
      expect(
        Annotation.fromJson(const <String, Object?>{
          'id': 'a1',
          'targetKind': 'transaction',
          'targetId': 'u',
          'body': 'x',
          'createdAtMillis': 1,
          'updatedAtMillis': 1,
        }),
        isNull,
      );
    });
  });
}
