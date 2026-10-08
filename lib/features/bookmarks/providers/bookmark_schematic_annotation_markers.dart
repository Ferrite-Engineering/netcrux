import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/features/bookmarks/services/annotations_on_scope.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/services/schematic/schematic_annotation_markers_provider.dart';
import 'package:netcrux/services/session/bookmark_annotation_state.dart';

/// Body of the `schematicAnnotationMarkersProvider` binding: the tab's
/// annotations that apply to the scope its hierarchy shows, as canvas
/// markers.
///
/// Reads the per-tab annotation state and the per-tab hierarchy, so it is
/// registered in `netcruxTabOverridesFactory` (derived providers follow
/// their source's scope). Returns `null` when the scope carries no
/// badgeable annotation, so the painter skips its pass.
SchematicAnnotationMarkers? bookmarkSchematicAnnotationMarkers(Ref ref) {
  final annotations = ref.watch(bookmarkAnnotationStateProvider).annotations;
  if (annotations.isEmpty) return null;
  final moduleName = ref.watch(hierarchyTreeProvider).selected?.moduleName;
  final markers = SchematicAnnotationMarkers.from(<SchematicAnnotationMarker>[
    for (final annotation in annotations)
      // A hidden layer's notes stay in the panel but leave the canvas.
      if (!annotation.hidden && annotationAppliesTo(annotation, moduleName))
        SchematicAnnotationMarker(
          kind: annotation.targetKind,
          targetId: annotation.targetId,
          annotationIds: <String>[annotation.id],
        ),
  ]);
  return markers.isEmpty ? null : markers;
}
