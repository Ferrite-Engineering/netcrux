// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/models/bookmark.dart';
import 'package:netcrux/domain/models/bookmark_annotation_target.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/features/bookmarks/services/annotations_on_scope.dart';
import 'package:netcrux/features/bookmarks/services/bookmark_annotation_openers.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/viewer/widgets/schematic_context_menu_extension.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/session/bookmark_annotation_store_provider.dart';

/// Builds the "Add Bookmark…" / "Add Annotation…" entries for the
/// schematic right-click / long-press context menu, and "Show Annotation"
/// on an element that has a note in the scope on screen.
///
/// Reads the right-clicked [target] and maps it to a
/// [BookmarkAnnotationTarget] (kind + targetId). When the target is
/// [SelectedElementNone] (no element under the click — e.g. user
/// right-clicked on empty canvas), returns an empty list so the menu
/// does not show stale "Add for what?" entries.
///
/// "Show Annotation" is the keyboard route to what an annotation badge click
/// does: the canvas opens this menu with Shift+F10 or the Menu key.
List<SchematicContextMenuExtensionEntry> buildBookmarkAnnotationMenuEntries(
  WidgetRef ref,
  SelectedElement target,
) {
  final mapped = _mapTarget(target);
  if (mapped == null) return const <SchematicContextMenuExtensionEntry>[];
  final l10n = L10N.of(ref.context);
  // `ref` is the canvas's, inside the tab's scope, so these resolve the
  // tab's own annotations and the scope it shows.
  final annotated = annotationsOnElement(
    ref.read(bookmarkAnnotationSnapshotProvider).annotations,
    kind: mapped.kind,
    targetId: mapped.targetId,
    moduleName: ref.read(hierarchyTreeProvider).selected?.moduleName,
  ).isNotEmpty;
  return <SchematicContextMenuExtensionEntry>[
    if (annotated)
      SchematicContextMenuExtensionEntry(
        id: 'show-annotation-${mapped.kind.name}-${mapped.targetId}',
        label: l10n.bookmarkMenuShowAnnotation,
        onTap: (context, ref) async {
          ref.read(showAnnotationForTargetOpenerProvider)(
            context,
            ref,
            mapped,
          );
        },
      ),
    SchematicContextMenuExtensionEntry(
      id: 'add-bookmark-${mapped.kind.name}-${mapped.targetId}',
      label: l10n.bookmarkMenuAddBookmark,
      onTap: (context, ref) async {
        ref.read(addBookmarkDialogOpenerProvider)(
          context,
          ref,
          target: mapped,
        );
      },
    ),
    SchematicContextMenuExtensionEntry(
      id: 'add-annotation-${mapped.kind.name}-${mapped.targetId}',
      label: l10n.bookmarkMenuAddAnnotation,
      onTap: (context, ref) async {
        ref.read(addAnnotationDialogOpenerProvider)(
          context,
          ref,
          target: mapped,
        );
      },
    ),
  ];
}

/// Maps the canvas-side [SelectedElement] union into the persisted
/// [BookmarkAnnotationTarget] shape. Returns null when the selection
/// has no stable target (e.g. [SelectedElementNone] — the user right-
/// clicked on empty canvas).
BookmarkAnnotationTarget? _mapTarget(SelectedElement target) {
  return switch (target) {
    SelectedElementNone() => null,
    SelectedElementCell(:final cellId) => BookmarkAnnotationTarget(
      kind: BookmarkTargetKind.cell,
      targetId: cellId,
    ),
    SelectedElementPort(:final portId) => BookmarkAnnotationTarget(
      kind: BookmarkTargetKind.port,
      targetId: portId,
    ),
    SelectedElementBoundaryPort(:final portId) => BookmarkAnnotationTarget(
      kind: BookmarkTargetKind.boundaryPort,
      targetId: portId,
    ),
    SelectedElementWire(:final edgeId) => BookmarkAnnotationTarget(
      kind: BookmarkTargetKind.net,
      targetId: edgeId,
    ),
  };
}
