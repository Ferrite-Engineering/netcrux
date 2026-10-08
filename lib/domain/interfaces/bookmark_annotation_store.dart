// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:netcrux/domain/models/annotation.dart';
import 'package:netcrux/domain/models/bookmark.dart';

/// Immutable snapshot of a [BookmarkAnnotationStore]'s contents.
///
/// The store streams snapshots so the Pro panel widgets can `ref.watch`
/// a single observable instead of subscribing to two collections
/// independently. Empty by default; the open-core no-op store returns
/// the canonical [empty] instance on every read.
@immutable
class BookmarkAnnotationSnapshot {
  /// Creates a snapshot.
  const BookmarkAnnotationSnapshot({
    required this.bookmarks,
    required this.annotations,
  });

  /// Canonical empty snapshot — equality identical to a freshly-built
  /// `BookmarkAnnotationSnapshot(bookmarks: [], annotations: [])`.
  static const BookmarkAnnotationSnapshot empty = BookmarkAnnotationSnapshot(
    bookmarks: <Bookmark>[],
    annotations: <Annotation>[],
  );

  /// Bookmarks in creation order (the store guarantees this).
  final List<Bookmark> bookmarks;

  /// Annotations in creation order.
  final List<Annotation> annotations;

  /// True when there are no bookmarks or annotations.
  bool get isEmpty => bookmarks.isEmpty && annotations.isEmpty;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! BookmarkAnnotationSnapshot) return false;
    if (other.bookmarks.length != bookmarks.length) return false;
    if (other.annotations.length != annotations.length) return false;
    for (var i = 0; i < bookmarks.length; i++) {
      if (other.bookmarks[i] != bookmarks[i]) return false;
    }
    for (var i = 0; i < annotations.length; i++) {
      if (other.annotations[i] != annotations[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    Object.hashAll(bookmarks),
    Object.hashAll(annotations),
  );
}

/// Extension-point service for persisting bookmarks + annotations
/// associated with the active project.
///
/// `InSessionBookmarkAnnotationStore` is the default implementation: it
/// holds the data in the tab's state so it round-trips through `.netcrux`
/// session save/load. [NoopBookmarkAnnotationStore] silently ignores writes
/// and always returns [BookmarkAnnotationSnapshot.empty].
///
/// The interface is intentionally read-as-snapshot + imperative-writes
/// rather than a CRUD provider. The panel widgets call into the
/// store imperatively (add / remove / update) and `ref.watch` the
/// `bookmarkAnnotationSnapshotProvider` that surfaces the current
/// snapshot. This keeps the open-core seam small (one interface, one
/// snapshot type, one provider) while preserving the freedom to swap
/// storage backends later (e.g. an Enterprise per-org service that
/// persists annotations outside the session file).
abstract interface class BookmarkAnnotationStore {
  /// Returns the current snapshot. Pure read — never throws.
  BookmarkAnnotationSnapshot snapshot();

  /// Adds [bookmark]. If a bookmark with the same id already exists,
  /// it is replaced (last-write-wins; the Pro panel handles this by
  /// regenerating the id only on fresh creates).
  void addBookmark(Bookmark bookmark);

  /// Updates the bookmark with id [bookmark.id]. No-op when no
  /// bookmark with that id exists — callers that need to detect
  /// "not found" should consult [snapshot] first.
  void updateBookmark(Bookmark bookmark);

  /// Removes the bookmark with id [id]. No-op when not found.
  void removeBookmark(String id);

  /// Adds [annotation]. Same last-write-wins semantics as
  /// [addBookmark].
  void addAnnotation(Annotation annotation);

  /// Updates the annotation with id [annotation.id]. No-op when no
  /// annotation with that id exists.
  void updateAnnotation(Annotation annotation);

  /// Removes the annotation with id [id]. No-op when not found.
  void removeAnnotation(String id);

  /// Removes every bookmark and annotation. Used by session-reset
  /// flows where the store backs a session that is being closed.
  void clear();
}

/// Open-core no-op default. Always returns
/// [BookmarkAnnotationSnapshot.empty]; all mutation methods are
/// silent no-ops so the open-core dispatch path (Pro panel call
/// sites → store) is testable without the Pro implementation
/// present.
class NoopBookmarkAnnotationStore implements BookmarkAnnotationStore {
  /// Creates the open-core no-op default.
  const NoopBookmarkAnnotationStore();

  @override
  BookmarkAnnotationSnapshot snapshot() => BookmarkAnnotationSnapshot.empty;

  @override
  void addBookmark(Bookmark bookmark) {}

  @override
  void updateBookmark(Bookmark bookmark) {}

  @override
  void removeBookmark(String id) {}

  @override
  void addAnnotation(Annotation annotation) {}

  @override
  void updateAnnotation(Annotation annotation) {}

  @override
  void removeAnnotation(String id) {}

  @override
  void clear() {}
}
