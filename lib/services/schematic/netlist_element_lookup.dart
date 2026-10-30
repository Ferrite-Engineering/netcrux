// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The netlist shims each re-export the whole model, `Cell` included.
import 'package:netcrux/domain/models/netlist/bit_ref.dart';
import 'package:netcrux/domain/models/netlist/module.dart';
import 'package:netcrux/domain/models/netlist/net.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/domain/models/selection/selection.dart';
import 'package:netcrux/services/schematic/declared_cell_ports.dart';
import 'package:netcrux/services/schematic/net_edge_enumeration.dart';
import 'package:netcrux/services/schematic/schematic_scope_module.dart';

// Lookups in a scope's netlist module that answer what the schematic graph of
// the scope would: whether it draws a cell, a pin or a boundary port, and
// which wires it draws for a net.
//
// A caller that only needs to know whether an element is there, or which
// wire ids it has, uses these instead of building the whole
// `SchematicGraph`. Building the graph walks every cell of the scope, and
// for a scope held back for being over the layout limit that walk is the
// cost the limit exists to avoid. Each lookup agrees with the graph for the
// same module: the graph is built from the same `schematicScopeModule` and
// the same `enumerateNetEdges`.

/// Whether the schematic draws a cell named [cellId] in [module]: it is in
/// the netlist and not one of the cells the schematic leaves out
/// ([isHiddenFromSchematic]).
bool schematicDrawsCell(Module module, String cellId) {
  final cell = module.cells[cellId];
  return cell != null && cell.name == cellId && !isHiddenFromSchematic(cell);
}

/// Whether the schematic draws a pin [portName] on the cell [cellId] of
/// [module]: the cell is drawn, and the pin is one it connects or its
/// module or Yosys primitive declares.
bool schematicDrawsCellPort(
  NetlistModel model,
  Module module,
  String cellId,
  String portName,
) {
  if (!schematicDrawsCell(module, cellId)) return false;
  final cell = module.cells[cellId]!;
  return cell.connections.containsKey(portName) ||
      (declaredPortsFor(model, cell.type)?.containsKey(portName) ?? false);
}

/// Whether [module] has a boundary port named [portName].
bool schematicDrawsBoundaryPort(Module module, String portName) =>
    module.ports.values.any((port) => port.name == portName);

/// The wire [Selection] for [net] of [module]: one wire per bit of the net
/// that has a drawn edge, the first such bit primary; null when no bit has
/// one.
///
/// What `buildWholeNetWireSelection` gives for the schematic graph of
/// [module], read from the edges of this net alone.
Selection? wholeNetWireSelection(Module module, Net net) {
  final bits = net.bits.whereType<NetBit>().toList();
  if (bits.isEmpty) return null;
  final firstEdgeOf = <int, String>{
    for (final group in enumerateNetEdges(
      module,
      onlyNetIds: <int>{for (final bit in bits) bit.netId},
      skipHiddenCells: true,
    ))
      group.netId: group.edges.first.id,
  };
  SelectedElement? primary;
  final elements = <SelectedElement>{};
  for (final bit in bits) {
    final edgeId = firstEdgeOf[bit.netId];
    if (edgeId == null) continue;
    final wire = SelectedElement.wire(edgeId: edgeId, netId: bit.netId);
    primary ??= wire;
    elements.add(wire);
  }
  if (primary == null) return null;
  return Selection(elements: elements, primary: primary);
}
