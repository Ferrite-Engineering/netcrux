// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/features/viewer/widgets/annotation_menu_entries.dart';
import 'package:netcrux/features/viewer/widgets/cross_probe_menu_entries.dart';
import 'package:netcrux/features/viewer/widgets/editor_host_menu_entries.dart';
import 'package:netcrux/features/viewer/widgets/schematic_context_menu_extension.dart';

/// Extension-point provider: the builders that inject extra entries into the
/// schematic right-click / long-press context menu.
///
/// Open core resolves it to the cross-probe builder, so "Cross-probe to" is on
/// the menu first, the annotation builder, so "Add Annotation…" and "Show
/// Annotation" are on the menu at every tier, and the editor-host builder,
/// which adds "Go to Source in Editor" only when an editor hosts the viewer.
/// The Pro overlay's `proOverrides` replaces the list with one that carries
/// the cross-probe and annotation builders and one builder per Pro feature.
///
/// Declared as a manual `Provider` (not `@Riverpod`-codegen) so the
/// Pro overlay can override with `.overrideWith` without taking the
/// build_runner generator dep. Matches the
/// [coneOfInfluenceServiceProvider] / [xTraceServiceProvider] /
/// [annotationStoreProvider] pattern.
final schematicContextMenuExtensionsProvider =
    Provider<List<SchematicContextMenuExtensionBuilder>>(
      (ref) => kOpenCoreSchematicContextMenuBuilders,
      name: 'schematicContextMenuExtensionsProvider',
    );

/// The builders open core registers. Each is called at menu-open time with
/// the canvas's own tab-scoped ref, so the per-tab state it reads is the
/// state of the tab the menu opened in.
const List<SchematicContextMenuExtensionBuilder>
kOpenCoreSchematicContextMenuBuilders = <SchematicContextMenuExtensionBuilder>[
  buildCrossProbeMenuEntries,
  buildAnnotationMenuEntries,
  buildEditorHostMenuEntries,
];
