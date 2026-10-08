import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/features/bookmarks/services/bookmark_id_generator.dart';

void main() {
  group('BookmarkIdGenerator', () {
    test('produces bookmark / annotation ids with the expected prefix', () {
      final gen = BookmarkIdGenerator(
        clock: () => DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );
      expect(gen.nextBookmarkId(), startsWith('bm-1700000000000-'));
      expect(gen.nextAnnotationId(), startsWith('an-1700000000000-'));
    });

    test('produces unique ids even at the same millisecond', () {
      final gen = BookmarkIdGenerator(
        clock: () => DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );
      final ids = <String>{
        gen.nextBookmarkId(),
        gen.nextBookmarkId(),
        gen.nextAnnotationId(),
        gen.nextBookmarkId(),
      };
      expect(ids, hasLength(4));
    });
  });
}
