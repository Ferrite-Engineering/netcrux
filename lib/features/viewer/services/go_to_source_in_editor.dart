// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_ide_layout/crux_ide_layout.dart' show showCruxInfoSnack;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/domain/models/source_location.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/host_bridge/editor_host_providers.dart';
import 'package:netcrux/services/host_bridge/element_source_location.dart';

/// The source location of [element] in the active tab's current scope, or
/// null when the netlist records none.
///
/// [ref] is a `ref` inside the tab's scope, so the hierarchy it reads is the
/// tab's own.
SourceLocation? sourceLocationInCurrentScope(
  WidgetRef ref,
  SelectedElement element,
) {
  final tree = ref.read(hierarchyTreeProvider);
  final model = tree.model;
  final module = model == null ? null : tree.selected?.resolve(model);
  if (module == null) return null;
  return sourceLocationOfElement(module, element);
}

/// Asks the editor hosting the viewer to show the RTL behind [element].
///
/// The location is whatever the netlist's `src` attribute says; the editor
/// resolves a relative or foreign path against the workspace. When the
/// netlist records no source for the element a message says so.
void goToSourceInEditor(
  BuildContext context,
  WidgetRef ref,
  SelectedElement element,
) {
  final location = sourceLocationInCurrentScope(ref, element);
  if (location == null) {
    showCruxInfoSnack(context, L10N.of(context).goToSourceInEditorUnavailable);
    return;
  }
  ref.read(editorHostBridgeProvider).openSource(location);
}
