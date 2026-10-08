import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/interfaces/annotation_store.dart';
import 'package:netcrux/domain/models/annotation.dart';
import 'package:netcrux/domain/models/annotation_target.dart';
import 'package:netcrux/services/session/annotation_state.dart';
import 'package:netcrux/services/session/annotation_store_provider.dart';
import 'package:netcrux/services/session/in_session_annotation_store.dart';

Annotation _note(String id, {String body = 'x', String? title, int at = 1}) =>
    Annotation(
      id: id,
      targetKind: AnnotationTargetKind.cell,
      targetId: 'u_$id',
      title: title,
      body: body,
      createdAtMillis: at,
      updatedAtMillis: at,
    );

void main() {
  group('InSessionAnnotationStore', () {
    /// Builds a container with the store, state and snapshot bound the way
    /// the per-tab override list binds them. Tests use the `AnnotationStore`
    /// interface as the API under test.
    ProviderContainer makeContainer() {
      final container = ProviderContainer(
        overrides: <Override>[
          annotationStoreProvider.overrideWith(InSessionAnnotationStore.new),
          annotationSnapshotProvider.overrideWith(
            (ref) => ref.watch(annotationStateProvider),
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('initial snapshot is empty', () {
      final container = makeContainer();
      final store = container.read(annotationStoreProvider);
      expect(store, isA<InSessionAnnotationStore>());
      expect(store.snapshot(), AnnotationSnapshot.empty);
      expect(
        container.read(annotationSnapshotProvider),
        AnnotationSnapshot.empty,
      );
    });

    test('addAnnotation appends + publishes a new snapshot', () {
      final container = makeContainer();
      final note = _note('a1', title: 'Clock root', body: '');
      container.read(annotationStoreProvider).addAnnotation(note);
      expect(
        container.read(annotationSnapshotProvider).annotations.single,
        note,
      );
    });

    test('addAnnotation with an existing id overwrites (last-write-wins)', () {
      final container = makeContainer();
      container.read(annotationStoreProvider)
        ..addAnnotation(_note('a1', body: 'first'))
        ..addAnnotation(_note('a1', body: 'second'));
      final snap = container.read(annotationSnapshotProvider);
      expect(snap.annotations, hasLength(1));
      expect(snap.annotations.single.body, 'second');
    });

    test('updateAnnotation mutates an existing entry', () {
      final container = makeContainer();
      final original = _note('a1', body: 'first', at: 100);
      container.read(annotationStoreProvider)
        ..addAnnotation(original)
        ..updateAnnotation(
          original.copyWith(
            title: 'Renamed',
            body: 'second',
            updatedAtMillis: 200,
          ),
        );
      final updated = container
          .read(annotationSnapshotProvider)
          .annotations
          .single;
      expect(updated.title, 'Renamed');
      expect(updated.body, 'second');
      expect(updated.updatedAtMillis, 200);
    });

    test('updateAnnotation on a missing id is a silent no-op', () {
      final container = makeContainer();
      container.read(annotationStoreProvider).updateAnnotation(_note('nope'));
      expect(container.read(annotationSnapshotProvider).annotations, isEmpty);
    });

    test('removeAnnotation drops the entry and keeps the order', () {
      final container = makeContainer();
      container.read(annotationStoreProvider)
        ..addAnnotation(_note('a1'))
        ..addAnnotation(_note('a2'))
        ..addAnnotation(_note('a3'))
        ..removeAnnotation('a2')
        ..removeAnnotation('missing');
      expect(
        container.read(annotationSnapshotProvider).annotations.map((a) => a.id),
        <String>['a1', 'a3'],
      );
    });

    test('clear empties the list', () {
      final container = makeContainer();
      container.read(annotationStoreProvider)
        ..addAnnotation(_note('a1'))
        ..addAnnotation(_note('a2'))
        ..clear();
      expect(
        container.read(annotationSnapshotProvider),
        AnnotationSnapshot.empty,
      );
    });
  });
}
