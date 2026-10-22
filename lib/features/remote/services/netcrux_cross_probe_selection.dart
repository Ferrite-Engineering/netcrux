// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart'
    show ElementId, ElementKind, cxpDesignIdMetadataKey;
import 'package:crux_cxp_ui/crux_cxp_ui.dart';
import 'package:netcrux/domain/models/schematic/cell_kind.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/project/providers/current_project_provider.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/services/remote/cxp/cxp_design_names.dart';
import 'package:netcrux/services/remote/cxp/cxp_selection_resolver.dart';
import 'package:netcrux/services/remote/cxp/cxp_workspace_link.dart';
import 'package:netcrux/services/remote/cxp/netcrux_name_resolver.dart';

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

/// The register cell [cellId] of the active tab's current scope as a
/// cross-probe of its RTL name: one `signal` candidate, the net the
/// register's `Q` drives (`top.u_div.cnt_q`), with `crux.design_id`. What
/// "Show timing paths through this register" sends SimCrux, which filters
/// its worst paths to those through it.
///
/// Null when [cellId] is not a register of the scope or no named net
/// carries its output. [read] is as for [netcruxCrossProbeSelection].
///
/// Not [netcruxCrossProbeSelectionOf]: that names a cell as an `instance`,
/// which a path table cannot filter on.
CrossProbeSelection? netcruxRegisterSignalSelectionOf(
  CruxCxpReader read,
  String cellId,
) {
  final tree = read(hierarchyTreeProvider);
  final model = tree.model;
  final scope = tree.selected;
  if (model == null || scope == null) return null;
  final module = scope.resolve(model);
  final cell = module?.cells[cellId];
  if (module == null || cell == null || !isRegisterCellType(cell.type)) {
    return null;
  }
  final net = registerOutputNetName(module, cellId);
  if (net == null) return null;
  final path =
      '${scope.canonicalPath(model)}.'
      '${NetcruxNameResolver.escapeSegment(net)}';
  final designId = cxpDesignIdForProject(read(currentProjectProvider));
  return CrossProbeSelection(
    candidates: <ElementId>[ElementId(kind: ElementKind.signal, path: path)],
    displayName: net,
    metadata: <String, Object?>{cxpDesignIdMetadataKey: ?designId},
  );
}
