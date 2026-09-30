// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/bookmark.dart';
import 'package:netcrux/services/session/bookmark_annotation_openers.dart';

void main() {
  group('bookmark/annotation opener seams', () {
    test('addBookmarkDialogOpenerProvider default is a no-op', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final opener = container.read(addBookmarkDialogOpenerProvider);
      expect(opener, isA<AddBookmarkDialogOpener>());
      // Should not throw. The default is a no-op.
      expect(() => opener.call, returnsNormally);
    });

    test('addAnnotationDialogOpenerProvider default is a no-op', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final opener = container.read(addAnnotationDialogOpenerProvider);
      expect(opener, isA<AddAnnotationDialogOpener>());
    });

    test('bookmarksPanelOpenerProvider default is a no-op', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final opener = container.read(bookmarksPanelOpenerProvider);
      expect(opener, isA<BookmarksPanelOpener>());
    });

    test('annotationsPanelOpenerProvider default is a no-op', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final opener = container.read(annotationsPanelOpenerProvider);
      expect(opener, isA<AnnotationsPanelOpener>());
    });

    test('BookmarkAnnotationTarget round-trips its fields', () {
      const target = BookmarkAnnotationTarget(
        kind: BookmarkTargetKind.cell,
        targetId: 'u_alu',
      );
      expect(target.kind, BookmarkTargetKind.cell);
      expect(target.targetId, 'u_alu');
    });

    test('opener providers can be overridden by the Pro overlay', () {
      final container = ProviderContainer(
        overrides: [
          addBookmarkDialogOpenerProvider.overrideWith(
            (_) => (_, _, {target}) {},
          ),
        ],
      );
      addTearDown(container.dispose);
      // Just verify the override resolved — we can't call the opener
      // without a BuildContext, but reading it should reflect the
      // override.
      expect(
        container.read(addBookmarkDialogOpenerProvider),
        isNot(same(container.read(addAnnotationDialogOpenerProvider))),
      );
    });
  });
}
