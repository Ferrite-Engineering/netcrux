import 'package:netcrux/domain/interfaces/bookmark_annotation_store.dart';
import 'package:netcrux/domain/models/annotation.dart';
import 'package:netcrux/domain/models/bookmark.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'bookmark_annotation_state.g.dart';

/// State notifier holding a design's bookmark + annotation snapshot.
///
/// The companion [InSessionBookmarkAnnotationStore] reads from and writes to
/// this notifier so all mutations land in a single Riverpod-observable
/// place. `bookmarkAnnotationSnapshotProvider` watches it, so panel widgets
/// rebuild on every add / update / remove.
///
/// Re-bound in the per-tab override list, so each tab's bookmarks and
/// annotations belong to that tab's design.
@Riverpod(keepAlive: true)
class BookmarkAnnotationState extends _$BookmarkAnnotationState {
  @override
  BookmarkAnnotationSnapshot build() => BookmarkAnnotationSnapshot.empty;

  /// Replaces the snapshot in one shot. Used by every mutation path
  /// (add / update / remove / clear) to keep the snapshot derivation
  /// in one place.
  void replace(BookmarkAnnotationSnapshot snapshot) {
    if (state == snapshot) return;
    state = snapshot;
  }

  /// Convenience: mutate the bookmark list while leaving annotations
  /// untouched.
  void setBookmarks(List<Bookmark> bookmarks) {
    replace(
      BookmarkAnnotationSnapshot(
        bookmarks: List<Bookmark>.unmodifiable(bookmarks),
        annotations: state.annotations,
      ),
    );
  }

  /// Convenience: mutate the annotation list while leaving bookmarks
  /// untouched.
  void setAnnotations(List<Annotation> annotations) {
    replace(
      BookmarkAnnotationSnapshot(
        bookmarks: state.bookmarks,
        annotations: List<Annotation>.unmodifiable(annotations),
      ),
    );
  }
}
