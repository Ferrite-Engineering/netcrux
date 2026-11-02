// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The netlist shims each re-export the whole model, `Cell` included.
import 'package:netcrux/domain/models/netlist/bit_ref.dart';
import 'package:netcrux/domain/models/netlist/module.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/netlist/port_direction.dart';
import 'package:netcrux/domain/models/schematic/liberty_cell_symbols.dart';
import 'package:netcrux/services/schematic/declared_cell_ports.dart';

/// The module the schematic draws and lays out for [module] of [model]:
/// the cells it hides ([isHiddenFromSchematic]) left out, then every
/// remaining cell's declared-but-unconnected ports added
/// ([withDeclaredCellPorts]), then, in a scope that connects no supply pin
/// of its cell libraries, the unconnected supply pins taken away again
/// ([withoutUnconnectedSupplyPins]).
///
/// The graph builder and the layout both take their module from here, so
/// every cell the canvas draws has a place in the layout and the layout
/// places nothing the canvas does not draw. The hidden cells stay in the
/// netlist model, so search still finds them and the Inspector still
/// describes them.
Module schematicScopeModule(
  NetlistModel model,
  Module module, {
  LibertyCellSymbols liberty = LibertyCellSymbols.none,
}) => withoutUnconnectedSupplyPins(
  withDeclaredCellPorts(model, withoutHiddenCells(module)),
  liberty,
  scope: module,
);

/// Whether any cell of [module] connects one of the power or ground pins
/// ([LibertyCellSymbol.isSupplyPin]) its cell library declares to a net or a
/// constant.
///
/// A netlist after place and route, or one written for power-aware
/// simulation, wires its supplies; one straight out of synthesis does not.
bool scopeConnectsSupplyPins(Module module, LibertyCellSymbols liberty) {
  if (liberty.isEmpty) return false;
  for (final cell in module.cells.values) {
    final library = liberty[cell.type];
    if (library == null) continue;
    for (final entry in cell.connections.entries) {
      if (entry.value.isNotEmpty && library.isSupplyPin(entry.key)) {
        return true;
      }
    }
  }
  return false;
}

/// [module] without the unconnected power and ground pins of its
/// cell-library cells, when no cell of [scope] (by default [module] itself)
/// connects any supply pin ([scopeConnectsSupplyPins]); otherwise [module]
/// unchanged.
///
/// A synthesized netlist leaves every cell's supplies to place and route,
/// and drawn, each cell carries four unconnected pins on sky130. Once any
/// instance of the scope is wired to a supply, every supply pin is drawn,
/// connected or not, so a missing connection stays in sight. Signal pins
/// are never taken away, and neither is a supply pin that is connected.
/// [module] itself is returned when nothing is taken away, so the ELK
/// input of a design without such pins does not change.
Module withoutUnconnectedSupplyPins(
  Module module,
  LibertyCellSymbols liberty, {
  Module? scope,
}) {
  if (liberty.isEmpty) return module;
  if (scopeConnectsSupplyPins(scope ?? module, liberty)) return module;
  Map<String, Cell>? patched;
  for (final entry in module.cells.entries) {
    final cell = entry.value;
    final library = liberty[cell.type];
    if (library == null) continue;
    bool hidden(String pin, List<BitRef> bits) =>
        bits.isEmpty && library.isSupplyPin(pin);
    if (!cell.connections.entries.any((e) => hidden(e.key, e.value))) {
      continue;
    }
    final connections = <String, List<BitRef>>{
      for (final pin in cell.connections.entries)
        if (!hidden(pin.key, pin.value)) pin.key: pin.value,
    };
    (patched ??= Map<String, Cell>.of(module.cells))[entry.key] = cell.copyWith(
      connections: connections,
      portDirections: <String, PortDirection>{
        for (final direction in cell.portDirections.entries)
          if (connections.containsKey(direction.key) ||
              !library.isSupplyPin(direction.key))
            direction.key: direction.value,
      },
    );
  }
  return patched == null ? module : module.copyWith(cells: patched);
}

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
