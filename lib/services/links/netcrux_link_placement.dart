// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:netcrux/domain/models/netlist/hierarchy_node.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/domain/models/selection/selection.dart';
import 'package:netcrux/services/links/netcrux_link.dart';
import 'package:netcrux/services/remote/cxp/cxp_design_names.dart';
import 'package:netcrux/services/schematic/netlist_element_lookup.dart';

/// Where a link's cell or net is in a design: the scope to show, what to
/// select there, and the cell to reveal.
@immutable
class NetCruxLinkPlacement {
  /// A placement in [scope].
  const NetCruxLinkPlacement({
    required this.scope,
    required this.selection,
    this.revealCell,
  });

  /// The scope that holds the element.
  final HierarchyNode scope;

  /// What selects it on that scope's schematic.
  final Selection selection;

  /// The cell to bring into view, when there is one.
  final String? revealCell;
}

/// Finds the cell or net [name] of a link in [model], or null when the
/// design has no such element or does not draw it.
///
/// [name] is a hierarchical name, its scopes separated by `.`: rooted at the
/// top module (`top.u_cpu.pc_reg`) or written from just below it
/// (`u_cpu.pc_reg`), the rooted reading first. Each instance segment walks
/// one level down; what is left once a segment names no child instance is the
/// element's name in that scope, so a flattened name is found too. A `cell`
/// is a drawn cell of that scope; a `net` is a net, a bit select (`data[3]`)
/// naming the whole net, that the schematic draws or whose driver it draws.
/// Never matched by its last segment alone in another scope.
///
/// The app opens a link through this, and the headless `netcrux` commands
/// give a location a link only when this finds its element, so a document
/// never carries a link the app cannot place.
NetCruxLinkPlacement? findNetCruxLinkElement(
  NetlistModel model,
  NetCruxLinkElementKind kind,
  String name,
) {
  final top = model.topModule?.name;
  final candidates = <String>[
    name,
    if (top != null && !name.startsWith('$top.')) '$top.$name',
  ];
  for (final candidate in candidates) {
    final scoped = scopeOfHierarchicalName(model, candidate);
    final module = scoped?.scope.resolve(model);
    if (scoped == null || module == null) continue;
    switch (kind) {
      case NetCruxLinkElementKind.cell:
        if (!module.cells.containsKey(scoped.leaf) ||
            !schematicDrawsCell(module, scoped.leaf)) {
          continue;
        }
        return NetCruxLinkPlacement(
          scope: scoped.scope,
          selection: Selection.single(
            SelectedElement.cell(cellId: scoped.leaf),
          ),
          revealCell: scoped.leaf,
        );
      case NetCruxLinkElementKind.net:
        final net = findNetNamed(module, scoped.leaf);
        final selection = net == null ? null : selectionForNet(module, net);
        if (net == null || selection == null) continue;
        return NetCruxLinkPlacement(
          scope: scoped.scope,
          selection: selection,
          revealCell: switch (selection.primary) {
            SelectedElementCell(:final cellId) => cellId,
            _ => driverCellOf(module, net),
          },
        );
    }
  }
  return null;
}
