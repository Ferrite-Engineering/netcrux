// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/interfaces/bookmark_annotation_store.dart';
import 'package:netcrux/domain/models/annotation.dart';
import 'package:netcrux/domain/models/bookmark.dart';

void main() {
  group('NoopBookmarkAnnotationStore', () {
    const store = NoopBookmarkAnnotationStore();

    test('snapshot returns the canonical empty', () {
      expect(store.snapshot(), BookmarkAnnotationSnapshot.empty);
      expect(store.snapshot().isEmpty, isTrue);
    });

    test('every mutation method is a silent no-op', () {
      const bookmark = Bookmark(
        id: 'b1',
        name: 'noop',
        targetKind: BookmarkTargetKind.cell,
        targetId: 'u',
        createdAtMillis: 1,
      );
      const annotation = Annotation(
        id: 'a1',
        targetKind: BookmarkTargetKind.cell,
        targetId: 'u',
        body: 'noop',
        createdAtMillis: 1,
        updatedAtMillis: 1,
      );
      // All eight method calls must complete without throwing and
      // leave the snapshot empty.
      store
        ..addBookmark(bookmark)
        ..updateBookmark(bookmark)
        ..removeBookmark('b1')
        ..addAnnotation(annotation)
        ..updateAnnotation(annotation)
        ..removeAnnotation('a1')
        ..clear();
      expect(store.snapshot(), BookmarkAnnotationSnapshot.empty);
    });
  });

  group('BookmarkAnnotationSnapshot', () {
    test('empty is canonical', () {
      expect(BookmarkAnnotationSnapshot.empty.bookmarks, isEmpty);
      expect(BookmarkAnnotationSnapshot.empty.annotations, isEmpty);
      expect(BookmarkAnnotationSnapshot.empty.isEmpty, isTrue);
    });

    test('equality is order-sensitive on bookmarks + annotations', () {
      const b1 = Bookmark(
        id: 'b1',
        name: 'first',
        targetKind: BookmarkTargetKind.cell,
        targetId: 'u1',
        createdAtMillis: 1,
      );
      const b2 = Bookmark(
        id: 'b2',
        name: 'second',
        targetKind: BookmarkTargetKind.cell,
        targetId: 'u2',
        createdAtMillis: 2,
      );
      const ordered = BookmarkAnnotationSnapshot(
        bookmarks: <Bookmark>[b1, b2],
        annotations: <Annotation>[],
      );
      const reversed = BookmarkAnnotationSnapshot(
        bookmarks: <Bookmark>[b2, b1],
        annotations: <Annotation>[],
      );
      expect(ordered, isNot(equals(reversed)));
    });
  });
}
