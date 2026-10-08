import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:netcrux/domain/interfaces/bookmark_annotation_store.dart';
import 'package:netcrux/domain/models/annotation.dart';
import 'package:netcrux/domain/models/bookmark.dart';
import 'package:netcrux/services/session/bookmark_annotation_state.dart';

/// In-session implementation of [BookmarkAnnotationStore].
///
/// Persists bookmarks + annotations into the [BookmarkAnnotationState]
/// notifier, which is the single source of truth the panel widgets
/// `ref.watch` through `bookmarkAnnotationSnapshotProvider`, so they rebuild
/// automatically on every mutation.
///
/// Bridging to session save/load: `SessionController` reads through the
/// store's `snapshot()` when saving and writes through `clear()` +
/// `addBookmark` / `addAnnotation` when loading, so bookmarks + annotations
/// round-trip through `.netcrux` files.
@immutable
class InSessionBookmarkAnnotationStore implements BookmarkAnnotationStore {
  /// Creates a store backed by the supplied [ref].
  const InSessionBookmarkAnnotationStore(this._ref);

  final Ref _ref;

  BookmarkAnnotationState get _notifier =>
      _ref.read(bookmarkAnnotationStateProvider.notifier);

  BookmarkAnnotationSnapshot get _current =>
      _ref.read(bookmarkAnnotationStateProvider);

  @override
  BookmarkAnnotationSnapshot snapshot() => _current;

  @override
  void addBookmark(Bookmark bookmark) {
    final current = _current;
    final existingIndex = current.bookmarks.indexWhere(
      (b) => b.id == bookmark.id,
    );
    final updated = List<Bookmark>.of(current.bookmarks);
    if (existingIndex >= 0) {
      // Same-id add overwrites (last-write-wins per the
      // BookmarkAnnotationStore contract).
      updated[existingIndex] = bookmark;
    } else {
      updated.add(bookmark);
    }
    _notifier.setBookmarks(updated);
  }

  @override
  void updateBookmark(Bookmark bookmark) {
    final current = _current;
    final i = current.bookmarks.indexWhere((b) => b.id == bookmark.id);
    if (i < 0) return; // not found — silent no-op per contract
    final updated = List<Bookmark>.of(current.bookmarks);
    updated[i] = bookmark;
    _notifier.setBookmarks(updated);
  }

  @override
  void removeBookmark(String id) {
    final current = _current;
    final i = current.bookmarks.indexWhere((b) => b.id == id);
    if (i < 0) return; // not found — silent no-op per contract
    final updated = List<Bookmark>.of(current.bookmarks)..removeAt(i);
    _notifier.setBookmarks(updated);
  }

  @override
  void addAnnotation(Annotation annotation) {
    final current = _current;
    final existingIndex = current.annotations.indexWhere(
      (a) => a.id == annotation.id,
    );
    final updated = List<Annotation>.of(current.annotations);
    if (existingIndex >= 0) {
      updated[existingIndex] = annotation;
    } else {
      updated.add(annotation);
    }
    _notifier.setAnnotations(updated);
  }

  @override
  void updateAnnotation(Annotation annotation) {
    final current = _current;
    final i = current.annotations.indexWhere((a) => a.id == annotation.id);
    if (i < 0) return;
    final updated = List<Annotation>.of(current.annotations);
    updated[i] = annotation;
    _notifier.setAnnotations(updated);
  }

  @override
  void removeAnnotation(String id) {
    final current = _current;
    final i = current.annotations.indexWhere((a) => a.id == id);
    if (i < 0) return;
    final updated = List<Annotation>.of(current.annotations)..removeAt(i);
    _notifier.setAnnotations(updated);
  }

  @override
  void clear() {
    _notifier.replace(BookmarkAnnotationSnapshot.empty);
  }
}
