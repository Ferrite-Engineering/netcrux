// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_annotations/crux_annotations_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/features/annotations/services/annotation_drift.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/services/session/annotation_state.dart';

/// Each of the tab's annotations' status against the design and scope on
/// screen (resolved, drifted, outside the current scope, missing, or on a
/// whole scope), keyed by annotation id.
///
/// The root instance is empty: the root has no design. The per-tab override
/// list re-binds it with [annotationStatusesForTab], which reads the tab's
/// annotations and hierarchy, so it follows their scope. The Annotations
/// panel groups by it, and an on-canvas callout layer draws only the notes it
/// calls drawable.
final Provider<Map<String, CruxAnnotationStatus>> annotationStatusesProvider =
    Provider<Map<String, CruxAnnotationStatus>>(
      (_) => const <String, CruxAnnotationStatus>{},
      name: 'annotationStatusesProvider',
    );

/// Body of the per-tab [annotationStatusesProvider] binding.
///
/// Recomputed when the tab's annotations change, when the scope on screen
/// changes, and when a re-elaboration replaces the design, which is when a
/// note's element can change under it.
Map<String, CruxAnnotationStatus> annotationStatusesForTab(Ref ref) {
  final annotations = ref.watch(annotationStateProvider).annotations;
  final tree = ref.watch(hierarchyTreeProvider);
  return annotationStatuses(
    annotations,
    model: tree.model,
    currentModule: tree.selected?.moduleName,
  );
}
