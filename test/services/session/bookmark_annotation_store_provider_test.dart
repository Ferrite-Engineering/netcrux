// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/interfaces/bookmark_annotation_store.dart';
import 'package:netcrux/domain/models/annotation.dart';
import 'package:netcrux/domain/models/bookmark.dart';
import 'package:netcrux/services/session/bookmark_annotation_store_provider.dart';

class _FakeBookmarkStore implements BookmarkAnnotationStore {
  _FakeBookmarkStore();
  final List<Bookmark> _bookmarks = [];
  final List<Annotation> _annotations = [];

  @override
  BookmarkAnnotationSnapshot snapshot() => BookmarkAnnotationSnapshot(
    bookmarks: List<Bookmark>.unmodifiable(_bookmarks),
    annotations: List<Annotation>.unmodifiable(_annotations),
  );

  @override
  void addBookmark(Bookmark bookmark) => _bookmarks.add(bookmark);

  @override
  void updateBookmark(Bookmark bookmark) {
    final i = _bookmarks.indexWhere((b) => b.id == bookmark.id);
    if (i >= 0) _bookmarks[i] = bookmark;
  }

  @override
  void removeBookmark(String id) => _bookmarks.removeWhere((b) => b.id == id);

  @override
  void addAnnotation(Annotation annotation) => _annotations.add(annotation);

  @override
  void updateAnnotation(Annotation annotation) {
    final i = _annotations.indexWhere((a) => a.id == annotation.id);
    if (i >= 0) _annotations[i] = annotation;
  }

  @override
  void removeAnnotation(String id) =>
      _annotations.removeWhere((a) => a.id == id);

  @override
  void clear() {
    _bookmarks.clear();
    _annotations.clear();
  }
}

void main() {
  group('bookmarkAnnotationStoreProvider', () {
    test('open-core default returns a NoopBookmarkAnnotationStore', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final store = container.read(bookmarkAnnotationStoreProvider);
      expect(store, isA<NoopBookmarkAnnotationStore>());
    });

    test('override replaces the default (Pro overlay pattern)', () {
      final fake = _FakeBookmarkStore();
      final container = ProviderContainer(
        overrides: [
          bookmarkAnnotationStoreProvider.overrideWith((_) => fake),
        ],
      );
      addTearDown(container.dispose);

      final store = container.read(bookmarkAnnotationStoreProvider);
      expect(identical(store, fake), isTrue);
    });
  });

  group('bookmarkAnnotationSnapshotProvider', () {
    test('open-core default snapshot is empty', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final snap = container.read(bookmarkAnnotationSnapshotProvider);
      expect(snap, BookmarkAnnotationSnapshot.empty);
    });

    test('with overridden store, snapshot reflects writes', () {
      final fake = _FakeBookmarkStore();
      final container = ProviderContainer(
        overrides: [
          bookmarkAnnotationStoreProvider.overrideWith((_) => fake),
        ],
      );
      addTearDown(container.dispose);

      // Initially empty.
      expect(
        container.read(bookmarkAnnotationSnapshotProvider).isEmpty,
        isTrue,
      );

      fake.addBookmark(
        const Bookmark(
          id: 'b1',
          name: 'one',
          targetKind: BookmarkTargetKind.cell,
          targetId: 'u',
          createdAtMillis: 1,
        ),
      );

      // The snapshot is computed on each read — verify the next read
      // reflects the new bookmark. Whether widget watchers rebuild
      // automatically is a Pro-overlay concern (the
      // InSessionBookmarkAnnotationStore wraps mutations in a
      // notifier); the open-core provider contract is simply
      // "read returns the current snapshot."
      container.invalidate(bookmarkAnnotationSnapshotProvider);
      expect(
        container.read(bookmarkAnnotationSnapshotProvider).bookmarks,
        hasLength(1),
      );
    });
  });
}
