// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart' show cxpDesignIdMetadataKey;
import 'package:crux_cxp_ui/crux_cxp_ui.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/project/providers/current_project_provider.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/services/remote/cxp/cxp_selection_resolver.dart';
import 'package:netcrux/services/remote/cxp/cxp_workspace_link.dart';

/// The active tab's schematic selection as a cross-probe selection, or null
/// when nothing is selected or no design is loaded.
///
/// [read] must resolve the tab's own providers: a `ref` inside the tab's scope
/// (the docked panel, the schematic's context menu) or the tab's container's
/// `read` (the command, which acts on the active tab from the workspace).
CrossProbeSelection? netcruxCrossProbeSelection(CruxCxpReader read) =>
    netcruxCrossProbeSelectionOf(read, read(selectedElementProvider).primary);

/// [element], selected in the active tab's current scope, as a cross-probe
/// selection, or null when it cannot be named or no design is loaded.
///
/// It goes through the same [resolveCxpSelection] the automatic emitter uses,
/// so every outbound reference is byte-identical, and carries the shared
/// `crux.design_id` so a receiver that cannot resolve the element locally can
/// open the design from the shared workspace. [read] is as for
/// [netcruxCrossProbeSelection].
CrossProbeSelection? netcruxCrossProbeSelectionOf(
  CruxCxpReader read,
  SelectedElement element,
) {
  final tree = read(hierarchyTreeProvider);
  final resolved = resolveCxpSelection(
    element: element,
    model: tree.model,
    scope: tree.selected,
  );
  if (resolved == null) return null;
  final designId = cxpDesignIdForProject(read(currentProjectProvider));
  return resolved.toCrossProbeSelection(<String, Object?>{
    cxpDesignIdMetadataKey: ?designId,
  });
}
