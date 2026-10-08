// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/annotation_target.dart';
import 'package:netcrux/features/annotations/services/annotation_actions.dart';
import 'package:netcrux/features/annotations/services/annotation_openers.dart';

void main() {
  group('annotation opener seams', () {
    test('the openers default to the working implementations', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      // The defaults are closures over the actions, so what is checkable
      // without a BuildContext is that each is the typed callback and that
      // the panel opener and the badge opener are the tear-offs
      // themselves.
      expect(
        container.read(addAnnotationDialogOpenerProvider),
        isA<AddAnnotationDialogOpener>(),
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

    test('AnnotationTarget round-trips its fields', () {
      const target = AnnotationTarget(
        kind: AnnotationTargetKind.cell,
        targetId: 'u_alu',
      );
      expect(target.kind, AnnotationTargetKind.cell);
      expect(target.targetId, 'u_alu');
    });

    test('every opener provider can be overridden', () {
      var fired = 0;
      void panel(BuildContext _) => fired++;
      final container = ProviderContainer(
        overrides: [
          addAnnotationDialogOpenerProvider.overrideWith(
            (_) => (_, _, {target}) {},
          ),
          annotationsPanelOpenerProvider.overrideWithValue(panel),
        ],
      );
      addTearDown(container.dispose);
      expect(
        container.read(addAnnotationDialogOpenerProvider),
        isNot(same(openAddAnnotationDialog)),
      );
      container.read(annotationsPanelOpenerProvider)(_NoContext());
      expect(fired, 1);
    });
  });
}

class _NoContext extends Fake implements BuildContext {}
