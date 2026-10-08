// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:netcrux/domain/models/annotation.dart';

/// Immutable snapshot of an [AnnotationStore]'s contents.
///
/// The store streams snapshots so the panel widgets can `ref.watch` a
/// single observable. Empty by default; the no-op store returns the
/// canonical [empty] instance on every read.
@immutable
class AnnotationSnapshot {
  /// Creates a snapshot.
  const AnnotationSnapshot({required this.annotations});

  /// Canonical empty snapshot — equality identical to a freshly-built
  /// `AnnotationSnapshot(annotations: [])`.
  static const AnnotationSnapshot empty = AnnotationSnapshot(
    annotations: <Annotation>[],
  );

  /// Annotations in creation order (the store guarantees this).
  final List<Annotation> annotations;

  /// True when there are no annotations.
  bool get isEmpty => annotations.isEmpty;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! AnnotationSnapshot) return false;
    if (other.annotations.length != annotations.length) return false;
    for (var i = 0; i < annotations.length; i++) {
      if (other.annotations[i] != annotations[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(annotations);
}

/// Extension-point service for persisting the annotations associated with
/// the active project.
///
/// `InSessionAnnotationStore` is the default implementation: it holds the
/// data in the tab's state so it round-trips through `.netcrux` session
/// save/load. [NoopAnnotationStore] silently ignores writes and always
/// returns [AnnotationSnapshot.empty].
///
/// The interface is intentionally read-as-snapshot + imperative-writes
/// rather than a CRUD provider. The panel widgets call into the store
/// imperatively (add / remove / update) and `ref.watch` the
/// `annotationSnapshotProvider` that surfaces the current snapshot. This
/// keeps the seam small (one interface, one snapshot type, one provider)
/// while preserving the freedom to swap storage backends later (e.g. an
/// Enterprise per-org service that persists annotations outside the
/// session file).
abstract interface class AnnotationStore {
  /// Returns the current snapshot. Pure read — never throws.
  AnnotationSnapshot snapshot();

  /// Adds [annotation]. If an annotation with the same id already exists,
  /// it is replaced (last-write-wins; the dialog regenerates the id only
  /// on fresh creates).
  void addAnnotation(Annotation annotation);

  /// Updates the annotation with id [annotation.id]. No-op when no
  /// annotation with that id exists — callers that need to detect
  /// "not found" should consult [snapshot] first.
  void updateAnnotation(Annotation annotation);

  /// Removes the annotation with id [id]. No-op when not found.
  void removeAnnotation(String id);

  /// Removes every annotation. Used by session-reset flows where the store
  /// backs a session that is being closed.
  void clear();
}

/// No-op default. Always returns [AnnotationSnapshot.empty]; all mutation
/// methods are silent no-ops so a dispatch path (panel call sites → store)
/// is testable without a backing store.
class NoopAnnotationStore implements AnnotationStore {
  /// Creates the no-op store.
  const NoopAnnotationStore();

  @override
  AnnotationSnapshot snapshot() => AnnotationSnapshot.empty;

  @override
  void addAnnotation(Annotation annotation) {}

  @override
  void updateAnnotation(Annotation annotation) {}

  @override
  void removeAnnotation(String id) {}

  @override
  void clear() {}
}
