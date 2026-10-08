import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:netcrux/domain/interfaces/annotation_store.dart';
import 'package:netcrux/domain/models/annotation.dart';
import 'package:netcrux/services/session/annotation_state.dart';

/// In-session implementation of [AnnotationStore].
///
/// Persists annotations into the [AnnotationState]
/// notifier, which is the single source of truth the panel widgets
/// `ref.watch` through `annotationSnapshotProvider`, so they rebuild
/// automatically on every mutation.
///
/// Bridging to session save/load: `SessionController` reads through the
/// store's `snapshot()` when saving and writes through `clear()` +
/// `addAnnotation` when loading, so annotations round-trip through
/// `.netcrux` files.
@immutable
class InSessionAnnotationStore implements AnnotationStore {
  /// Creates a store backed by the supplied [ref].
  const InSessionAnnotationStore(this._ref);

  final Ref _ref;

  AnnotationState get _notifier => _ref.read(annotationStateProvider.notifier);

  AnnotationSnapshot get _current => _ref.read(annotationStateProvider);

  @override
  AnnotationSnapshot snapshot() => _current;

  @override
  void addAnnotation(Annotation annotation) {
    final current = _current;
    final existingIndex = current.annotations.indexWhere(
      (a) => a.id == annotation.id,
    );
    final updated = List<Annotation>.of(current.annotations);
    if (existingIndex >= 0) {
      // Same-id add overwrites (last-write-wins per the AnnotationStore
      // contract).
      updated[existingIndex] = annotation;
    } else {
      updated.add(annotation);
    }
    _notifier.setAnnotations(updated);
  }

  @override
  void updateAnnotation(Annotation annotation) {
    final current = _current;
    final i = current.annotations.indexWhere((a) => a.id == annotation.id);
    if (i < 0) return;
    final updated = List<Annotation>.of(current.annotations);
    updated[i] = annotation;
    _notifier.setAnnotations(updated);
  }

  @override
  void removeAnnotation(String id) {
    final current = _current;
    final i = current.annotations.indexWhere((a) => a.id == id);
    if (i < 0) return;
    final updated = List<Annotation>.of(current.annotations)..removeAt(i);
    _notifier.setAnnotations(updated);
  }

  @override
  void clear() {
    _notifier.replace(AnnotationSnapshot.empty);
  }
}
