// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/models/analysis/analysis_panel_kind.dart';
import 'package:netcrux/domain/models/annotation.dart';
import 'package:netcrux/domain/models/annotation_target.dart';
import 'package:netcrux/domain/models/schematic/schematic_graph.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/features/annotations/providers/annotation_drafts_provider.dart';
import 'package:netcrux/features/annotations/providers/annotation_reveal_request.dart';
import 'package:netcrux/features/annotations/services/annotation_target_reveal.dart';
import 'package:netcrux/features/annotations/services/annotations_on_scope.dart';
import 'package:netcrux/features/annotations/widgets/inline_element_picker.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/inspector/providers/inspector_providers.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/features/workspace/services/active_tab_container.dart';
import 'package:netcrux/features/workspace/services/analysis_dock_actions.dart';
import 'package:netcrux/services/session/annotation_store_provider.dart';

/// Default [AddAnnotationDialogOpener]. Starts a new annotation in the
/// Inspector on either the supplied [target] (from the schematic context
/// menu) or, when [target] is null, the currently selected schematic
/// element's primary anchor. When neither is available the inline element
/// picker asks for one (the user invoked the action from the command palette
/// with nothing selected).
///
/// The element is selected, a new-annotation draft is started in the tab's
/// [annotationDraftsProvider] and the Inspector opens with focus on the
/// draft's title. The draft's Add button writes the annotation to the tab's
/// store and records `annotation.added`.
///
/// Re-entrancy guarded ([ModalGuard]): reached from the keyboard shortcut,
/// menu and command-palette `addAnnotation` action, and a double-fire must
/// not stack two pickers.
void openAddAnnotationDialog(
  BuildContext context,
  WidgetRef ref, {
  AnnotationTarget? target,
}) {
  unawaited(
    ModalGuard.run('netcruxAddAnnotation', () async {
      // Command-palette dispatch passes the root ref and no target. The
      // active selection, the schematic graph and the drafts live in the
      // active tab's per-tab container, so resolve it before reading any of
      // them: reading through the root ref would see an empty selection and
      // start a draft no tab shows. The context-menu path already supplies
      // a resolved target and skips both fallbacks.
      final tab =
          ref.activeTabContainerOrNull(context) ??
          ProviderScope.containerOf(context, listen: false);
      final resolved =
          target ??
          _targetFromContainer(tab) ??
          await showInlineElementPicker(context, container: tab);
      if (resolved == null) return;
      startAnnotationInInspector(tab, resolved);
    }),
  );
}

/// Selects [target] on the schematic of [tab] (the per-tab container),
/// starts a new-annotation draft on it and opens the Inspector with focus on
/// the draft's title.
void startAnnotationInInspector(
  ProviderContainer tab,
  AnnotationTarget target,
) {
  final element = selectedElementForAnnotationTarget(target);
  final key = tab
      .read(annotationDraftsProvider.notifier)
      .startNew(
        kind: target.kind,
        targetId: target.targetId,
        moduleName: _moduleOf(tab, target),
      );
  openInspectorFor(tab, element ?? const SelectedElement.none());
  tab.read(inspectorFocusRequestProvider.notifier).request(key);
}

/// The Annotations panel's Edit: selects the
/// annotated element (switching scope when it is in another one) and opens
/// the Inspector with focus on that annotation's title. Returns false,
/// changing nothing, when the shown design has no such element.
bool openAnnotationInInspector(ProviderContainer tab, Annotation annotation) {
  final found = revealAnnotationTarget(
    tab,
    kind: annotation.targetKind,
    targetId: annotation.targetId,
    moduleName: annotation.moduleName,
  );
  if (!found) return false;
  tab.read(inspectorControllerProvider).open();
  tab.read(inspectorFocusRequestProvider.notifier).request(annotation.id);
  return true;
}

/// The schematic element an annotation [target] names, or null for a scope
/// (which is not a selectable element) and for an id the canvas does not
/// mint.
SelectedElement? selectedElementForAnnotationTarget(AnnotationTarget target) {
  final id = target.targetId;
  switch (target.kind) {
    case AnnotationTargetKind.cell:
      return SelectedElement.cell(cellId: id);
    case AnnotationTargetKind.port:
      final cellId = cellIdOfPinId(id);
      if (cellId == null) return null;
      return SelectedElement.port(
        cellId: cellId,
        portId: id,
        portName: id.substring(cellId.length + 1),
      );
    case AnnotationTargetKind.boundaryPort:
      return SelectedElement.boundaryPort(
        portId: id,
        portName: id.startsWith('port:') ? id.substring('port:'.length) : id,
      );
    case AnnotationTargetKind.net:
      final netId = netIdOfEdgeId(id);
      if (netId == null) return null;
      return SelectedElement.wire(edgeId: id, netId: netId);
    case AnnotationTargetKind.scope:
      return null;
  }
}

/// Default [AnnotationsPanelOpener]: the right dock's Annotations tab
/// (`AnalysisPanelKind.annotations`). Opens it, brings it to the front when
/// another tab hides it, and closes it when it is already on screen
/// ([focusOrToggleAnalysisDock]). The tab's x closes it too.
///
/// A dock tab rather than a dialog: the list is used beside the schematic,
/// and a row click selects its element on a canvas the user can see. The
/// panel mounts inside the active tab's scope, so it lists that tab's
/// annotations.
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
  AnnotationTarget target,
) {
  final tab = ref.activeTabContainerOrNull(context);
  if (tab != null) {
    final moduleName = tab.read(hierarchyTreeProvider).selected?.moduleName;
    final matches = annotationsOnElement(
      tab.read(annotationSnapshotProvider).annotations,
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

/// Maps a [SelectedElement] union value to a [AnnotationTarget].
/// Returns null for the [SelectedElementNone] sentinel — there is no
/// stable target to annotate.
AnnotationTarget? mapSelectionToAnnotationTarget(
  SelectedElement selection,
) {
  return switch (selection) {
    SelectedElementNone() => null,
    SelectedElementCell(:final cellId) => AnnotationTarget(
      kind: AnnotationTargetKind.cell,
      targetId: cellId,
    ),
    SelectedElementPort(:final portId) => AnnotationTarget(
      kind: AnnotationTargetKind.port,
      targetId: portId,
    ),
    SelectedElementBoundaryPort(:final portId) => AnnotationTarget(
      kind: AnnotationTargetKind.boundaryPort,
      targetId: portId,
    ),
    SelectedElementWire(:final edgeId) => AnnotationTarget(
      kind: AnnotationTargetKind.net,
      targetId: edgeId,
    ),
  };
}

/// The module of the scope [tab] shows, recorded on a new annotation so its element id is read in that module. Null for a scope
/// target, whose dotted path names the scope itself, and when no tab is
/// active.
String? _moduleOf(ProviderContainer? tab, AnnotationTarget target) {
  if (tab == null || target.kind == AnnotationTargetKind.scope) return null;
  return tab.read(hierarchyTreeProvider).selected?.moduleName;
}

/// Reads the active selection from the active tab's [container] and maps
/// its primary anchor to an annotation target. Returns null when no tab is
/// active or nothing is selected.
AnnotationTarget? _targetFromContainer(ProviderContainer? container) {
  if (container == null) return null;
  final selection = container.read(selectedElementProvider);
  return mapSelectionToAnnotationTarget(selection.primary);
}
