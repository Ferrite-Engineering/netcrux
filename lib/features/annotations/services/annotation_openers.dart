// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/models/annotation_target.dart';
import 'package:netcrux/features/annotations/services/annotation_actions.dart';

/// Opens the Add Annotation dialog. When [target] is non-null the dialog
/// is pre-populated for that element; otherwise the opener resolves the
/// currently selected schematic element from the provided [ref].
typedef AddAnnotationDialogOpener =
    void Function(
      BuildContext context,
      WidgetRef ref, {
      AnnotationTarget? target,
    });

/// Opens the Annotations panel, the list of the active design's annotations,
/// as the right dock's Annotations tab (`AnalysisPanelKind.annotations`), or
/// closes that tab when it is already open, matching the other View-menu
/// panel toggles.
typedef AnnotationsPanelOpener = void Function(BuildContext context);

/// Opens the Annotations panel, or brings it to the front, scrolled to the
/// first annotation on [target] and flashing it. Reached from a click on an
/// annotated element's badge and from its *Show Annotation* context-menu
/// entry. [ref] resolves the active tab, whose annotations the panel lists.
typedef ShowAnnotationForTargetOpener =
    void Function(
      BuildContext context,
      WidgetRef ref,
      AnnotationTarget target,
    );

/// Extension point for the Add Annotation dialog opener. The default mounts
/// the dialog; a test or an embedder replaces it with `.overrideWith`.
final addAnnotationDialogOpenerProvider = Provider<AddAnnotationDialogOpener>(
  (_) => openAddAnnotationDialog,
  name: 'addAnnotationDialogOpenerProvider',
);

/// Extension point for showing the Annotations panel.
final annotationsPanelOpenerProvider = Provider<AnnotationsPanelOpener>(
  (_) => openAnnotationsPanel,
  name: 'annotationsPanelOpenerProvider',
);

/// Extension point for opening the Annotations panel at an element's note.
/// The schematic gesture handler calls it when a click lands on an
/// annotation badge, and the *Show Annotation* context-menu entry calls it
/// too.
final showAnnotationForTargetOpenerProvider =
    Provider<ShowAnnotationForTargetOpener>(
      (_) => openAnnotationForTarget,
      name: 'showAnnotationForTargetOpenerProvider',
    );
