// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/models/annotation_target.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/features/annotations/services/annotation_actions.dart';
import 'package:netcrux/features/annotations/services/annotation_openers.dart';
import 'package:netcrux/features/annotations/services/annotations_on_scope.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/viewer/widgets/schematic_context_menu_extension.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/session/annotation_store_provider.dart';

/// Builds the "Add Annotation…" entry for the schematic right-click /
/// long-press context menu, and "Show Annotation" on an element that has a
/// note in the scope on screen.
///
/// Reads the right-clicked [target] and maps it to a
/// [AnnotationTarget] (kind + targetId). When the target is
/// [SelectedElementNone] (no element under the click — e.g. user
/// right-clicked on empty canvas), returns an empty list so the menu
/// does not show stale "Add for what?" entries.
///
/// "Show Annotation" is the keyboard route to what an annotation badge click
/// does: the canvas opens this menu with Shift+F10 or the Menu key.
List<SchematicContextMenuExtensionEntry> buildAnnotationMenuEntries(
  WidgetRef ref,
  SelectedElement target,
) {
  final mapped = mapSelectionToAnnotationTarget(target);
  if (mapped == null) return const <SchematicContextMenuExtensionEntry>[];
  final l10n = L10N.of(ref.context);
  // `ref` is the canvas's, inside the tab's scope, so these resolve the
  // tab's own annotations and the scope it shows.
  final annotated = annotationsOnElement(
    ref.read(annotationSnapshotProvider).annotations,
    kind: mapped.kind,
    targetId: mapped.targetId,
    moduleName: ref.read(hierarchyTreeProvider).selected?.moduleName,
  ).isNotEmpty;
  return <SchematicContextMenuExtensionEntry>[
    if (annotated)
      SchematicContextMenuExtensionEntry(
        id: 'show-annotation-${mapped.kind.name}-${mapped.targetId}',
        label: l10n.annotationMenuShow,
        onTap: (context, ref) async {
          ref.read(showAnnotationForTargetOpenerProvider)(
            context,
            ref,
            mapped,
          );
        },
      ),
    SchematicContextMenuExtensionEntry(
      id: 'add-annotation-${mapped.kind.name}-${mapped.targetId}',
      label: l10n.annotationMenuAdd,
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
