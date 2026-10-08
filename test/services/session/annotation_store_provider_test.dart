// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/interfaces/annotation_store.dart';
import 'package:netcrux/domain/models/annotation.dart';
import 'package:netcrux/domain/models/annotation_target.dart';
import 'package:netcrux/services/session/annotation_store_provider.dart';
import 'package:netcrux/services/session/in_session_annotation_store.dart';

class _FakeAnnotationStore implements AnnotationStore {
  _FakeAnnotationStore();
  final List<Annotation> _annotations = [];

  @override
  AnnotationSnapshot snapshot() => AnnotationSnapshot(
    annotations: List<Annotation>.unmodifiable(_annotations),
  );

  @override
  void addAnnotation(Annotation annotation) => _annotations.add(annotation);

  @override
  void updateAnnotation(Annotation annotation) {
    final i = _annotations.indexWhere((a) => a.id == annotation.id);
    if (i >= 0) _annotations[i] = annotation;
  }

  @override
  void removeAnnotation(String id) =>
      _annotations.removeWhere((a) => a.id == id);

  @override
  void clear() => _annotations.clear();
}

void main() {
  group('annotationStoreProvider', () {
    test('the default is the in-session store', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final store = container.read(annotationStoreProvider);
      expect(store, isA<InSessionAnnotationStore>());
    });

    test('override replaces the default', () {
      final fake = _FakeAnnotationStore();
      final container = ProviderContainer(
        overrides: [
          annotationStoreProvider.overrideWith((_) => fake),
        ],
      );
      addTearDown(container.dispose);

      final store = container.read(annotationStoreProvider);
      expect(identical(store, fake), isTrue);
    });
  });

  group('annotationSnapshotProvider', () {
    test('the default snapshot starts empty', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final snap = container.read(annotationSnapshotProvider);
      expect(snap, AnnotationSnapshot.empty);
    });

    test('the snapshot follows the default store without an invalidate', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final seen = <int>[];
      container.listen(
        annotationSnapshotProvider,
        (_, next) => seen.add(next.annotations.length),
      );

      container
          .read(annotationStoreProvider)
          .addAnnotation(
            const Annotation(
              id: 'a1',
              targetKind: AnnotationTargetKind.cell,
              targetId: 'u',
              title: 'one',
              body: '',
              createdAtMillis: 1,
              updatedAtMillis: 1,
            ),
          );

      expect(
        container.read(annotationSnapshotProvider).annotations,
        hasLength(1),
      );
      expect(seen, <int>[1], reason: 'watchers are notified of the write');
    });
  });
}
