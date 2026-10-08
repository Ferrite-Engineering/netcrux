import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/annotation.dart';
import 'package:netcrux/domain/models/bookmark.dart';
import 'package:netcrux/features/bookmarks/services/annotations_on_scope.dart';

Annotation _a(
  String id,
  String targetId, {
  BookmarkTargetKind kind = BookmarkTargetKind.cell,
  String? moduleName,
}) => Annotation(
  id: id,
  targetKind: kind,
  targetId: targetId,
  body: 'b',
  createdAtMillis: 1,
  updatedAtMillis: 1,
  moduleName: moduleName,
);

void main() {
  test('a note applies in scopes of the module it was written in', () {
    final note = _a('a1', 'u_fifo', moduleName: 'rx');
    expect(annotationAppliesTo(note, 'rx'), isTrue);
    expect(annotationAppliesTo(note, 'tx'), isFalse);
  });

  test('a note with no recorded module applies in every scope', () {
    final note = _a('a1', 'u_fifo');
    expect(annotationAppliesTo(note, 'rx'), isTrue);
    expect(annotationAppliesTo(note, 'tx'), isTrue);
  });

  test('annotationsOnElement matches kind, id and module, oldest first', () {
    final notes = <Annotation>[
      _a('a1', 'u_fifo', moduleName: 'rx'),
      _a('a2', 'u_fifo', moduleName: 'tx'),
      _a('a3', 'u_fifo'),
      _a('a4', 'u_fifo:A', kind: BookmarkTargetKind.port, moduleName: 'rx'),
      _a('a5', 'u_other', moduleName: 'rx'),
    ];
    final found = annotationsOnElement(
      notes,
      kind: BookmarkTargetKind.cell,
      targetId: 'u_fifo',
      moduleName: 'rx',
    );
    expect(found.map((a) => a.id), <String>['a1', 'a3']);
  });
}
