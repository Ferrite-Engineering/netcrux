// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/interfaces/annotation_store.dart';
import 'package:netcrux/domain/models/annotation.dart';
import 'package:netcrux/domain/models/annotation_target.dart';

void main() {
  group('NoopAnnotationStore', () {
    const store = NoopAnnotationStore();

    test('snapshot returns the canonical empty', () {
      expect(store.snapshot(), AnnotationSnapshot.empty);
      expect(store.snapshot().isEmpty, isTrue);
    });

    test('every mutation method is a silent no-op', () {
      const annotation = Annotation(
        id: 'a1',
        targetKind: AnnotationTargetKind.cell,
        targetId: 'u',
        body: 'noop',
        createdAtMillis: 1,
        updatedAtMillis: 1,
      );
      // All four method calls must complete without throwing and
      // leave the snapshot empty.
      store
        ..addAnnotation(annotation)
        ..updateAnnotation(annotation)
        ..removeAnnotation('a1')
        ..clear();
      expect(store.snapshot(), AnnotationSnapshot.empty);
    });
  });

  group('AnnotationSnapshot', () {
    test('empty is canonical', () {
      expect(AnnotationSnapshot.empty.annotations, isEmpty);
      expect(AnnotationSnapshot.empty.isEmpty, isTrue);
      expect(
        AnnotationSnapshot.empty,
        AnnotationSnapshot(annotations: List<Annotation>.empty()),
      );
    });

    test('equality is order-sensitive', () {
      const a1 = Annotation(
        id: 'a1',
        targetKind: AnnotationTargetKind.cell,
        targetId: 'u1',
        title: 'first',
        body: '',
        createdAtMillis: 1,
        updatedAtMillis: 1,
      );
      const a2 = Annotation(
        id: 'a2',
        targetKind: AnnotationTargetKind.cell,
        targetId: 'u2',
        body: 'second',
        createdAtMillis: 2,
        updatedAtMillis: 2,
      );
      const ordered = AnnotationSnapshot(annotations: <Annotation>[a1, a2]);
      const reversed = AnnotationSnapshot(annotations: <Annotation>[a2, a1]);
      const same = AnnotationSnapshot(annotations: <Annotation>[a1, a2]);
      expect(ordered, isNot(equals(reversed)));
      expect(ordered, same);
      expect(ordered.hashCode, same.hashCode);
    });
  });
}
