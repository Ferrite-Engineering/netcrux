// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/annotation.dart';
import 'package:netcrux/domain/models/annotation_target.dart';

void main() {
  group('Annotation', () {
    test('equality + hashCode', () {
      const a = Annotation(
        id: 'a1',
        targetKind: AnnotationTargetKind.cell,
        targetId: 'u_alu',
        body: 'Suspect: glitchy clock domain crossing here.',
        createdAtMillis: 1000,
        updatedAtMillis: 1000,
      );
      const b = Annotation(
        id: 'a1',
        targetKind: AnnotationTargetKind.cell,
        targetId: 'u_alu',
        body: 'Suspect: glitchy clock domain crossing here.',
        createdAtMillis: 1000,
        updatedAtMillis: 1000,
      );
      const c = Annotation(
        id: 'a1',
        targetKind: AnnotationTargetKind.cell,
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
        targetKind: AnnotationTargetKind.net,
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
        targetKind: AnnotationTargetKind.cell,
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
        targetKind: AnnotationTargetKind.scope,
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
        targetKind: AnnotationTargetKind.cell,
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
      targetKind: AnnotationTargetKind.cell,
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
        targetKind: AnnotationTargetKind.cell,
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

  group('title', () {
    const titled = Annotation(
      id: 'a1',
      targetKind: AnnotationTargetKind.cell,
      targetId: 'u_fifo',
      title: 'Reset value',
      body: 'Resets to **IDLE**.',
      createdAtMillis: 1,
      updatedAtMillis: 1,
    );

    test('round-trips through JSON and takes part in equality', () {
      expect(titled.toJson()['title'], 'Reset value');
      expect(Annotation.fromJson(titled.toJson()), titled);
      expect(titled, isNot(titled.copyWith(title: 'Other')));
      expect(titled.hashCode, isNot(titled.copyWith(title: 'Other').hashCode));
    });

    test('an untitled annotation writes no title key', () {
      expect(
        titled.copyWith(clearTitle: true).toJson().containsKey('title'),
        isFalse,
      );
    });

    test('a title-only annotation has an empty body and reads back', () {
      const titleOnly = Annotation(
        id: 'a2',
        targetKind: AnnotationTargetKind.net,
        targetId: 'e_4_0',
        title: 'Clock root',
        body: '',
        createdAtMillis: 1,
        updatedAtMillis: 1,
      );
      expect(Annotation.fromJson(titleOnly.toJson()), titleOnly);
      final json = Map<String, Object?>.of(titleOnly.toJson())..remove('body');
      expect(Annotation.fromJson(json), titleOnly);
    });

    test('fromJson folds a title onto one line and drops a blank one', () {
      final json = Map<String, Object?>.of(titled.toJson())
        ..['title'] = '  Reset\n  value ';
      expect(Annotation.fromJson(json)!.title, 'Reset value');
      json['title'] = '   ';
      expect(Annotation.fromJson(json)!.title, isNull);
    });

    test('heading is the title, else the first non-blank body line', () {
      expect(titled.heading, 'Reset value');
      expect(
        titled
            .copyWith(clearTitle: true, body: '\n\n  First line\nSecond')
            .heading,
        'First line',
      );
      expect(titled.copyWith(clearTitle: true, body: '').heading, isEmpty);
    });

    test('normalizeAnnotationTitle', () {
      expect(normalizeAnnotationTitle(null), isNull);
      expect(normalizeAnnotationTitle(' \t '), isNull);
      expect(normalizeAnnotationTitle(' a\n b '), 'a b');
    });
  });

  group('fromLegacyBookmarkJson', () {
    test('name becomes the title and note the body', () {
      final note = Annotation.fromLegacyBookmarkJson(const <String, Object?>{
        'id': 'bm-1-0',
        'name': 'State register',
        'targetKind': 'cell',
        'targetId': r'$procdff$17',
        'createdAtMillis': 10,
        'note': ' Check the reset value ',
        'moduleName': 'fsm_lock',
        'author': 'me',
      });
      expect(
        note,
        const Annotation(
          id: 'bm-1-0',
          targetKind: AnnotationTargetKind.cell,
          targetId: r'$procdff$17',
          title: 'State register',
          body: 'Check the reset value',
          createdAtMillis: 10,
          updatedAtMillis: 10,
          author: 'me',
          moduleName: 'fsm_lock',
        ),
      );
    });

    test('an entry without a note has an empty body', () {
      final note = Annotation.fromLegacyBookmarkJson(const <String, Object?>{
        'id': 'bm-1-1',
        'name': 'Unlock input',
        'targetKind': 'boundaryPort',
        'targetId': 'port:unlock',
        'createdAtMillis': 11,
      });
      expect(note!.title, 'Unlock input');
      expect(note.body, isEmpty);
      expect(note.author, isNull);
      expect(note.moduleName, isNull);
    });

    test('rejects what fromJson rejects', () {
      expect(
        Annotation.fromLegacyBookmarkJson(const <String, Object?>{'id': 'x'}),
        isNull,
      );
      expect(
        Annotation.fromLegacyBookmarkJson(const <String, Object?>{
          'id': 'x',
          'name': 'n',
          'targetKind': 'transaction',
          'targetId': 'u',
          'createdAtMillis': 1,
        }),
        isNull,
      );
    });
  });
}
