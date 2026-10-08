// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/interfaces/bookmark_annotation_store.dart';
import 'package:netcrux/domain/models/analysis/analysis_panel_kind.dart';
import 'package:netcrux/domain/models/bookmark.dart';
import 'package:netcrux/domain/models/bookmark_annotation_target.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/features/bookmarks/providers/annotation_reveal_request.dart';
import 'package:netcrux/features/bookmarks/services/annotations_on_scope.dart';
import 'package:netcrux/features/bookmarks/widgets/annotation_dialog.dart';
import 'package:netcrux/features/bookmarks/widgets/bookmark_dialog.dart';
import 'package:netcrux/features/bookmarks/widgets/inline_element_picker.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/features/workspace/services/active_tab_container.dart';
import 'package:netcrux/features/workspace/services/analysis_dock_actions.dart';
import 'package:netcrux/services/session/bookmark_annotation_store_provider.dart';
import 'package:netcrux/services/telemetry/annotation_telemetry.dart';
import 'package:netcrux/services/telemetry/netcrux_telemetry_vocabulary.dart';

/// Default [AddBookmarkDialogOpener]. Mounts the
/// existing [showBookmarkDialog] with either the supplied [target] (e.g.
/// from the schematic context menu) or — when [target] is null — the
/// currently selected schematic element's primary anchor. When neither
/// is available the inline element picker asks for one (the user invoked the
/// action from the command palette with nothing selected).
///
/// Re-entrancy guarded ([ModalGuard]): reached from the keyboard shortcut /
/// menu / command-palette `addBookmark` action — a double-fire must not
/// stack two pickers/dialogs across the picker→dialog chain.
void openAddBookmarkDialog(
  BuildContext context,
  WidgetRef ref, {
  BookmarkAnnotationTarget? target,
}) {
  unawaited(
    ModalGuard.run('netcruxAddBookmark', () async {
      // Command-palette dispatch passes the root ref and no target. The
      // active selection and the schematic graph live in the active tab's
      // per-tab container, so resolve it before reading either — reading
      // through the root ref would see an empty selection and an empty
      // graph. The context-menu path already supplies a resolved target
      // and skips both fallbacks.
      final tabContainer = ref.activeTabContainerOrNull(context);
      final store = _storeOf(tabContainer, context);
      final resolved =
          target ??
          _targetFromContainer(tabContainer) ??
          await showInlineElementPicker(context, container: tabContainer);
      if (resolved == null) return;
      if (!context.mounted) return;
      final created = await showBookmarkDialog(
        context: context,
        ref: ref,
        targetKind: resolved.kind,
        targetId: resolved.targetId,
        moduleName: _moduleOf(tabContainer, resolved),
      );
      if (created == null) return;
      // The bookmark belongs to the active tab's design, so it is written
      // to that tab's store. The command palette and menu bar pass the
      // root ref, whose store no tab reads.
      store.addBookmark(created);
      recordAnnotationAdded(
        ref.read(telemetryServiceProvider),
        NetcruxAnnotationKind.bookmark,
      );
    }),
  );
}

/// Default [AddAnnotationDialogOpener].
///
/// Re-entrancy guarded ([ModalGuard]): reached from the keyboard shortcut /
/// menu / command-palette `addAnnotation` action — a double-fire must not
/// stack two pickers/dialogs across the picker→dialog chain.
void openAddAnnotationDialog(
  BuildContext context,
  WidgetRef ref, {
  BookmarkAnnotationTarget? target,
}) {
  unawaited(
    ModalGuard.run('netcruxAddAnnotation', () async {
      final tabContainer = ref.activeTabContainerOrNull(context);
      final store = _storeOf(tabContainer, context);
      final resolved =
          target ??
          _targetFromContainer(tabContainer) ??
          await showInlineElementPicker(context, container: tabContainer);
      if (resolved == null) return;
      if (!context.mounted) return;
      final created = await showAnnotationDialog(
        context: context,
        ref: ref,
        targetKind: resolved.kind,
        targetId: resolved.targetId,
        moduleName: _moduleOf(tabContainer, resolved),
      );
      if (created == null) return;
      store.addAnnotation(created);
      recordAnnotationAdded(
        ref.read(telemetryServiceProvider),
        NetcruxAnnotationKind.annotation,
      );
    }),
  );
}

/// Default [BookmarksPanelOpener]: the right dock's
/// Bookmarks tab (`AnalysisPanelKind.bookmarks`). Opens it, brings it to
/// the front when another tab hides it, and closes it when it is already
/// on screen ([focusOrToggleAnalysisDock]). The tab's x closes it too.
///
/// A dock tab rather than a dialog: the list is used beside the schematic,
/// and a row click selects its element on a canvas the user can see. The
/// panel mounts inside the active tab's scope, so it lists that tab's
/// bookmarks.
void openBookmarksPanel(BuildContext context) =>
    focusOrToggleAnalysisDock(context, AnalysisPanelKind.bookmarks);

/// Default [AnnotationsPanelOpener]: the right dock's
/// Annotations tab, with the same open, focus and close semantics as
/// [openBookmarksPanel].
void openAnnotationsPanel(BuildContext context) =>
    focusOrToggleAnalysisDock(context, AnalysisPanelKind.annotations);

/// Default [ShowAnnotationForTargetOpener], reached
/// from an annotation badge click and the *Show Annotation* context-menu
/// entry. Asks the active tab's Annotations panel to scroll to and flash
/// the oldest annotation on [target] in the scope on screen, then opens
/// the Annotations tab or brings it to the front. Never closes it: the
/// user asked to see a note.
void openAnnotationForTarget(
  BuildContext context,
  WidgetRef ref,
  BookmarkAnnotationTarget target,
) {
  final tab = ref.activeTabContainerOrNull(context);
  if (tab != null) {
    final moduleName = tab.read(hierarchyTreeProvider).selected?.moduleName;
    final matches = annotationsOnElement(
      tab.read(bookmarkAnnotationSnapshotProvider).annotations,
      kind: target.kind,
      targetId: target.targetId,
      moduleName: moduleName,
    );
    if (matches.isNotEmpty) {
      tab
          .read(annotationRevealRequestProvider.notifier)
          .request(matches.first.id);
    }
  }
  openAnalysisDock(context, AnalysisPanelKind.annotations);
}

/// Maps a [SelectedElement] union value to a [BookmarkAnnotationTarget].
/// Returns null for the [SelectedElementNone] sentinel — there is no
/// stable target to bookmark.
BookmarkAnnotationTarget? mapSelectionToBookmarkTarget(
  SelectedElement selection,
) {
  return switch (selection) {
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

/// The module of the scope [tab] shows, recorded on a new bookmark or
/// annotation so its element id is read in that module. Null for a scope
/// target, whose dotted path names the scope itself, and when no tab is
/// active.
String? _moduleOf(ProviderContainer? tab, BookmarkAnnotationTarget target) {
  if (tab == null || target.kind == BookmarkTargetKind.scope) return null;
  return tab.read(hierarchyTreeProvider).selected?.moduleName;
}

/// The bookmark store of the active tab, or of [context]'s scope when no tab
/// container can be resolved (a test harness mounting the opener without a
/// workspace).
BookmarkAnnotationStore _storeOf(
  ProviderContainer? tab,
  BuildContext context,
) => (tab ?? ProviderScope.containerOf(context, listen: false)).read(
  bookmarkAnnotationStoreProvider,
);

/// Reads the active selection from the active tab's [container] and maps
/// its primary anchor to a bookmark target. Returns null when no tab is
/// active or nothing is selected.
BookmarkAnnotationTarget? _targetFromContainer(ProviderContainer? container) {
  if (container == null) return null;
  final selection = container.read(selectedElementProvider);
  return mapSelectionToBookmarkTarget(selection.primary);
}
