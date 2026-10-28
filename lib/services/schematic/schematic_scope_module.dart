// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The netlist shims each re-export the whole model, `Cell` included.
import 'package:netcrux/domain/models/netlist/bit_ref.dart';
import 'package:netcrux/domain/models/netlist/module.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/services/schematic/declared_cell_ports.dart';

/// The module the schematic draws and lays out for [module] of [model]:
/// the cells it hides ([isHiddenFromSchematic]) left out, then every
/// remaining cell's declared-but-unconnected ports added
/// ([withDeclaredCellPorts]).
///
/// The graph builder and the layout both take their module from here, so
/// every cell the canvas draws has a place in the layout and the layout
/// places nothing the canvas does not draw. The hidden cells stay in the
/// netlist model, so search still finds them and the Inspector still
/// describes them.
Module schematicScopeModule(NetlistModel model, Module module) =>
    withDeclaredCellPorts(model, withoutHiddenCells(module));

/// Whether the schematic leaves [cell] out.
///
/// A memory-initialisation cell (`$meminit`, `$meminit_v2`) records the
/// initial contents of a memory, not hardware the memory is wired to: a
/// register file carries one per initialised word, and drawn they read as
/// a loose grid of unconnected boxes beside the logic. A cell whose every
/// connected bit is a constant is left out for the same reason: no wire
/// reaches it, so it has no place in the drawing. A cell with no connected
/// bits at all is kept, since nothing says what it is.
bool isHiddenFromSchematic(Cell cell) {
  if (cell.type == r'$meminit' || cell.type == r'$meminit_v2') return true;
  var anyBit = false;
  for (final bits in cell.connections.values) {
    for (final bit in bits) {
      if (bit is! ConstantBit) return false;
      anyBit = true;
    }
  }
  return anyBit;
}

/// [module] without the cells [isHiddenFromSchematic] leaves out, or
/// [module] itself when it has none, so the ELK input of a design without
/// such cells does not change.
Module withoutHiddenCells(Module module) {
  if (!module.cells.values.any(isHiddenFromSchematic)) return module;
  return module.copyWith(
    cells: <String, Cell>{
      for (final entry in module.cells.entries)
        if (!isHiddenFromSchematic(entry.value)) entry.key: entry.value,
    },
  );
}
