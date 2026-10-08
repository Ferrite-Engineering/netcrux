import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/interfaces/bookmark_annotation_store.dart';
import 'package:netcrux/domain/models/annotation.dart';
import 'package:netcrux/domain/models/bookmark.dart';
import 'package:netcrux/services/session/bookmark_annotation_state.dart';
import 'package:netcrux/services/session/bookmark_annotation_store_provider.dart';
import 'package:netcrux/services/session/in_session_bookmark_annotation_store.dart';

void main() {
  group('InSessionBookmarkAnnotationStore', () {
    /// Builds a container with the same overrides the Pro overlay
    /// applies in `proOverrides` for the bookmark / annotation
    /// surface. Tests construct one of these and use the
    /// `BookmarkAnnotationStore` interface as the API under test.
    ProviderContainer makeContainer() {
      final container = ProviderContainer(
        overrides: <Override>[
          bookmarkAnnotationStoreProvider.overrideWith(
            InSessionBookmarkAnnotationStore.new,
          ),
          bookmarkAnnotationSnapshotProvider.overrideWith(
            (ref) => ref.watch(bookmarkAnnotationStateProvider),
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('initial snapshot is empty', () {
      final container = makeContainer();
      final store = container.read(bookmarkAnnotationStoreProvider);
      expect(store, isA<InSessionBookmarkAnnotationStore>());
      expect(store.snapshot(), BookmarkAnnotationSnapshot.empty);
      expect(
        container.read(bookmarkAnnotationSnapshotProvider),
        BookmarkAnnotationSnapshot.empty,
      );
    });

    test('addBookmark appends + publishes a new snapshot', () {
      final container = makeContainer();
      final store = container.read(bookmarkAnnotationStoreProvider);
      const bookmark = Bookmark(
        id: 'b1',
        name: 'Clock root',
        targetKind: BookmarkTargetKind.net,
        targetId: 'e_clk',
        createdAtMillis: 100,
      );
      store.addBookmark(bookmark);
      final snap = container.read(bookmarkAnnotationSnapshotProvider);
      expect(snap.bookmarks.single, bookmark);
      expect(snap.annotations, isEmpty);
    });

    test('addBookmark with existing id overwrites (last-write-wins)', () {
      final container = makeContainer();
      final store = container.read(bookmarkAnnotationStoreProvider);
      const v1 = Bookmark(
        id: 'b1',
        name: 'first',
        targetKind: BookmarkTargetKind.cell,
        targetId: 'u_a',
        createdAtMillis: 100,
      );
      const v2 = Bookmark(
        id: 'b1',
        name: 'second',
        targetKind: BookmarkTargetKind.cell,
        targetId: 'u_a',
        createdAtMillis: 100,
      );
      store
        ..addBookmark(v1)
        ..addBookmark(v2);
      final snap = container.read(bookmarkAnnotationSnapshotProvider);
      expect(snap.bookmarks, hasLength(1));
      expect(snap.bookmarks.single.name, 'second');
    });

    test('updateBookmark mutates an existing entry', () {
      final container = makeContainer();
      final store = container.read(bookmarkAnnotationStoreProvider);
      const original = Bookmark(
        id: 'b1',
        name: 'first',
        targetKind: BookmarkTargetKind.cell,
        targetId: 'u_a',
        createdAtMillis: 100,
      );
      store
        ..addBookmark(original)
        ..updateBookmark(original.copyWith(name: 'renamed'));
      expect(
        container
            .read(bookmarkAnnotationSnapshotProvider)
            .bookmarks
            .single
            .name,
        'renamed',
      );
    });

    test('updateBookmark on missing id is a silent no-op', () {
      final container = makeContainer();
      final store = container.read(bookmarkAnnotationStoreProvider);
      const orphan = Bookmark(
        id: 'unknown',
        name: 'orphan',
        targetKind: BookmarkTargetKind.cell,
        targetId: 'u',
        createdAtMillis: 1,
      );
      store.updateBookmark(orphan);
      expect(
        container.read(bookmarkAnnotationSnapshotProvider).bookmarks,
        isEmpty,
      );
    });

    test('removeBookmark drops the entry', () {
      final container = makeContainer();
      container.read(bookmarkAnnotationStoreProvider)
        ..addBookmark(
          const Bookmark(
            id: 'b1',
            name: 'a',
            targetKind: BookmarkTargetKind.cell,
            targetId: 'u',
            createdAtMillis: 1,
          ),
        )
        ..addBookmark(
          const Bookmark(
            id: 'b2',
            name: 'b',
            targetKind: BookmarkTargetKind.cell,
            targetId: 'u',
            createdAtMillis: 2,
          ),
        )
        ..removeBookmark('b1');
      final snap = container.read(bookmarkAnnotationSnapshotProvider);
      expect(snap.bookmarks, hasLength(1));
      expect(snap.bookmarks.single.id, 'b2');
    });

    test('annotations follow the same add / update / remove semantics', () {
      final container = makeContainer();
      final store = container.read(bookmarkAnnotationStoreProvider);
      const a1 = Annotation(
        id: 'a1',
        targetKind: BookmarkTargetKind.cell,
        targetId: 'u_a',
        body: 'first',
        createdAtMillis: 100,
        updatedAtMillis: 100,
      );
      store.addAnnotation(a1);
      expect(
        container
            .read(bookmarkAnnotationSnapshotProvider)
            .annotations
            .single
            .body,
        'first',
      );
      store.updateAnnotation(
        a1.copyWith(body: 'second', updatedAtMillis: 200),
      );
      expect(
        container
            .read(bookmarkAnnotationSnapshotProvider)
            .annotations
            .single
            .body,
        'second',
      );
      store.removeAnnotation('a1');
      expect(
        container.read(bookmarkAnnotationSnapshotProvider).annotations,
        isEmpty,
      );
    });

    test('clear empties both lists', () {
      final container = makeContainer();
      container.read(bookmarkAnnotationStoreProvider)
        ..addBookmark(
          const Bookmark(
            id: 'b1',
            name: 'a',
            targetKind: BookmarkTargetKind.cell,
            targetId: 'u',
            createdAtMillis: 1,
          ),
        )
        ..addAnnotation(
          const Annotation(
            id: 'a1',
            targetKind: BookmarkTargetKind.cell,
            targetId: 'u',
            body: 'x',
            createdAtMillis: 1,
            updatedAtMillis: 1,
          ),
        )
        ..clear();
      expect(
        container.read(bookmarkAnnotationSnapshotProvider),
        BookmarkAnnotationSnapshot.empty,
      );
    });
  });
}
