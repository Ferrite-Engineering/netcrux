import 'package:netcrux/domain/interfaces/annotation_store.dart';
import 'package:netcrux/domain/models/annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'annotation_state.g.dart';

/// State notifier holding a design's annotation snapshot.
///
/// The companion [InSessionAnnotationStore] reads from and writes to this
/// notifier so all mutations land in a single Riverpod-observable place.
/// `annotationSnapshotProvider` watches it, so panel widgets rebuild on
/// every add / update / remove.
///
/// Re-bound in the per-tab override list, so each tab's annotations belong
/// to that tab's design.
@Riverpod(keepAlive: true)
class AnnotationState extends _$AnnotationState {
  @override
  AnnotationSnapshot build() => AnnotationSnapshot.empty;

  /// Replaces the snapshot in one shot. Used by every mutation path
  /// (add / update / remove / clear) to keep the snapshot derivation
  /// in one place.
  void replace(AnnotationSnapshot snapshot) {
    if (state == snapshot) return;
    state = snapshot;
  }

  /// Replaces the annotation list.
  void setAnnotations(List<Annotation> annotations) {
    replace(
      AnnotationSnapshot(
        annotations: List<Annotation>.unmodifiable(annotations),
      ),
    );
  }
}
