import 'package:netcrux/domain/models/annotation.dart';
import 'package:netcrux/domain/models/bookmark.dart';

/// Whether [annotation] applies to the scope on screen, a scope of module
/// [moduleName].
///
/// Element ids are local to a module, so a note on module `rx`'s `u_fifo`
/// is not a note on module `tx`'s `u_fifo`. An annotation saved before the
/// module was recorded has no module name and applies wherever its id
/// matches.
bool annotationAppliesTo(Annotation annotation, String? moduleName) {
  final recorded = annotation.moduleName;
  return recorded == null || moduleName == null || recorded == moduleName;
}

/// The annotations on the element [kind] / [targetId] in a scope of module
/// [moduleName], oldest first.
List<Annotation> annotationsOnElement(
  Iterable<Annotation> annotations, {
  required BookmarkTargetKind kind,
  required String targetId,
  required String? moduleName,
}) => <Annotation>[
  for (final annotation in annotations)
    if (annotation.targetKind == kind &&
        annotation.targetId == targetId &&
        annotationAppliesTo(annotation, moduleName))
      annotation,
];
