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
      expect(annotation.toJson().containsKey('moduleName'), isFalse);
    });

    test('moduleName round-trips and takes part in equality', () {
      const annotation = Annotation(
        id: 'a1',
        targetKind: BookmarkTargetKind.cell,
        targetId: 'u_fifo',
        body: 'Overflows at full rate.',
        createdAtMillis: 1,
        updatedAtMillis: 1,
        moduleName: 'rx_path',
      );
      final restored = Annotation.fromJson(annotation.toJson());
      expect(restored, annotation);
      expect(restored!.moduleName, 'rx_path');
      expect(annotation, isNot(annotation.copyWith(moduleName: 'tx_path')));
    });

    test('an annotation saved without moduleName loads with none', () {
      final restored = Annotation.fromJson(const <String, Object?>{
        'id': 'a1',
        'targetKind': 'cell',
        'targetId': 'u_alu',
        'body': 'b',
        'createdAtMillis': 1,
        'updatedAtMillis': 1,
      });
      expect(restored!.moduleName, isNull);
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

  group('session fields', () {
    const sessionNote = Annotation(
      id: 'a9',
      targetKind: BookmarkTargetKind.cell,
      targetId: 'u_alu',
      body: 'why is this here',
      createdAtMillis: 1,
      updatedAtMillis: 2,
      author: 'Grace',
      authorId: 'p-grace',
      colorArgb: 0xFF00AA88,
      sessionLayerId: 'session:ABC123',
      sessionLayerLabel: 'Session ABC123 · 2026-10-08',
      hidden: true,
    );

    test('round-trip through JSON', () {
      expect(Annotation.fromJson(sessionNote.toJson()), sessionNote);
    });

    test('a note written outside a session writes none of them', () {
      const plain = Annotation(
        id: 'a1',
        targetKind: BookmarkTargetKind.cell,
        targetId: 'u',
        body: 'x',
        createdAtMillis: 1,
        updatedAtMillis: 1,
      );
      expect(
        plain.toJson().keys,
        isNot(anyOf(contains('authorId'), contains('hidden'))),
      );
      expect(plain.hidden, isFalse);
    });

    test('keeping your own note clears its author id, nothing else', () {
      final kept = sessionNote.copyWith(clearAuthorId: true);
      expect(kept.authorId, isNull);
      expect(kept.colorArgb, sessionNote.colorArgb);
      expect(kept.sessionLayerId, sessionNote.sessionLayerId);
    });
  });
}
