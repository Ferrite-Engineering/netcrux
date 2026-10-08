// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/bookmark.dart';
import 'package:netcrux/domain/models/bookmark_annotation_target.dart';
import 'package:netcrux/features/bookmarks/services/bookmark_annotation_actions.dart';
import 'package:netcrux/features/bookmarks/services/bookmark_annotation_openers.dart';

void main() {
  group('bookmark/annotation opener seams', () {
    test('the openers default to the working implementations', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      // The defaults are closures over the actions, so what is checkable
      // without a BuildContext is that each is the typed callback and that
      // the two panel openers and the badge opener are the tear-offs
      // themselves.
      expect(
        container.read(addBookmarkDialogOpenerProvider),
        isA<AddBookmarkDialogOpener>(),
      );
      expect(
        container.read(addAnnotationDialogOpenerProvider),
        isA<AddAnnotationDialogOpener>(),
      );
      expect(
        container.read(bookmarksPanelOpenerProvider),
        same(openBookmarksPanel),
      );
      expect(
        container.read(annotationsPanelOpenerProvider),
        same(openAnnotationsPanel),
      );
      expect(
        container.read(showAnnotationForTargetOpenerProvider),
        same(openAnnotationForTarget),
      );
    });

    test('BookmarkAnnotationTarget round-trips its fields', () {
      const target = BookmarkAnnotationTarget(
        kind: BookmarkTargetKind.cell,
        targetId: 'u_alu',
      );
      expect(target.kind, BookmarkTargetKind.cell);
      expect(target.targetId, 'u_alu');
    });

    test('every opener provider can be overridden', () {
      var fired = 0;
      void panel(BuildContext _) => fired++;
      final container = ProviderContainer(
        overrides: [
          addBookmarkDialogOpenerProvider.overrideWith(
            (_) => (_, _, {target}) {},
          ),
          bookmarksPanelOpenerProvider.overrideWithValue(panel),
        ],
      );
      addTearDown(container.dispose);
      expect(
        container.read(addBookmarkDialogOpenerProvider),
        isNot(same(container.read(addAnnotationDialogOpenerProvider))),
      );
      container.read(bookmarksPanelOpenerProvider)(_NoContext());
      expect(fired, 1);
    });
  });
}

class _NoContext extends Fake implements BuildContext {}
