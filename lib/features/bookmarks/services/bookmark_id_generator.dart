/// Generates stable per-session bookmark / annotation ids.
///
/// Uses `millisecondsSinceEpoch` + a per-instance counter so two
/// creates in the same millisecond don't collide. The id is opaque to
/// the rest of the system — anything string-valued is fine — but a
/// time-prefix makes ids sort naturally by creation order during
/// debugging. A future enhancement may move to a true UUID; the
/// `Bookmark.id` / `Annotation.id` fields are forward-compatible
/// because the contract is just "opaque non-empty string."
class BookmarkIdGenerator {
  /// Creates a fresh generator. Per-instance counter starts at 0.
  BookmarkIdGenerator({
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  int _counter = 0;

  /// Returns a fresh bookmark id.
  String nextBookmarkId() {
    final ms = _clock().millisecondsSinceEpoch;
    final c = _counter++;
    return 'bm-$ms-$c';
  }

  /// Returns a fresh annotation id.
  String nextAnnotationId() {
    final ms = _clock().millisecondsSinceEpoch;
    final c = _counter++;
    return 'an-$ms-$c';
  }
}
