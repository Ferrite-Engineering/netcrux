// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The netlist shims each re-export the whole model, `Cell` included.
import 'package:netcrux/domain/models/netlist/bit_ref.dart';
import 'package:netcrux/domain/models/netlist/module.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/netlist/port_direction.dart';

/// The ports a cell of [type] declares, in declaration order, with their
/// directions, or `null` when nothing in [model] or the Yosys cell library
/// describes the type.
///
/// A module of the netlist wins: a user module instance, a `$paramod`
/// derivative, or a cell-library black box such as `SB_LUT4`, all of which
/// `write_json` carries as modules with their port lists. Otherwise the
/// type is looked up among the Yosys internal cells in [_yosysCellPorts].
Map<String, PortDirection>? declaredPortsFor(NetlistModel model, String type) {
  final module = model.modules[type];
  if (module != null) {
    return <String, PortDirection>{
      for (final port in module.ports.values) port.name: port.direction,
    };
  }
  return _yosysCellPorts[type];
}

/// [module] with every cell's declared-but-unconnected ports added as
/// ports with no bits, so the layout places them and the canvas draws them.
///
/// Yosys leaves a port out of a cell's `connections` when the instance
/// connects nothing to it, and a cell that shows one pin fewer than its
/// symbol has reads as a different cell. A cell missing nothing is kept
/// as it is, and so is [module] when no cell misses anything, so the ELK
/// input of a design without such cells does not change. An added port is
/// placed in declaration order among the connected ones.
Module withDeclaredCellPorts(NetlistModel model, Module module) {
  Map<String, Cell>? patched;
  for (final entry in module.cells.entries) {
    final cell = entry.value;
    final declared = declaredPortsFor(model, cell.type);
    if (declared == null) continue;
    if (declared.keys.every(cell.connections.containsKey)) continue;
    final connections = <String, List<BitRef>>{
      for (final name in declared.keys)
        name: cell.connections[name] ?? const <BitRef>[],
      ...cell.connections,
    };
    final directions = <String, PortDirection>{
      for (final name in declared.keys)
        if (!cell.connections.containsKey(name)) name: declared[name]!,
      ...cell.portDirections,
    };
    (patched ??= Map<String, Cell>.of(module.cells))[entry.key] = cell.copyWith(
      connections: connections,
      portDirections: directions,
    );
  }
  return patched == null ? module : module.copyWith(cells: patched);
}

const PortDirection _in = PortDirection.input;
const PortDirection _out = PortDirection.output;

const _binary = <String, PortDirection>{'A': _in, 'B': _in, 'Y': _out};
const _unary = <String, PortDirection>{'A': _in, 'Y': _out};
const _mux = <String, PortDirection>{'A': _in, 'B': _in, 'S': _in, 'Y': _out};

/// The port lists of the Yosys internal cells a netlist names without
/// declaring, from the Yosys cell library (`techlibs/common/simlib.v` and
/// `simcells.v`). Only the word-level arithmetic, logic and multiplexer
/// cells and the plain gates are listed: their ports do not depend on
/// parameters, so the list is right for every instance.
const Map<String, Map<String, PortDirection>> _yosysCellPorts =
    <String, Map<String, PortDirection>>{
      r'$add': _binary,
      r'$sub': _binary,
      r'$mul': _binary,
      r'$div': _binary,
      r'$mod': _binary,
      r'$divfloor': _binary,
      r'$modfloor': _binary,
      r'$pow': _binary,
      r'$and': _binary,
      r'$or': _binary,
      r'$xor': _binary,
      r'$xnor': _binary,
      r'$shl': _binary,
      r'$shr': _binary,
      r'$sshl': _binary,
      r'$sshr': _binary,
      r'$shift': _binary,
      r'$shiftx': _binary,
      r'$lt': _binary,
      r'$le': _binary,
      r'$eq': _binary,
      r'$ne': _binary,
      r'$eqx': _binary,
      r'$nex': _binary,
      r'$ge': _binary,
      r'$gt': _binary,
      r'$logic_and': _binary,
      r'$logic_or': _binary,
      r'$not': _unary,
      r'$pos': _unary,
      r'$neg': _unary,
      r'$logic_not': _unary,
      r'$reduce_and': _unary,
      r'$reduce_or': _unary,
      r'$reduce_xor': _unary,
      r'$reduce_xnor': _unary,
      r'$reduce_bool': _unary,
      r'$mux': _mux,
      r'$pmux': _mux,
      r'$_AND_': _binary,
      r'$_NAND_': _binary,
      r'$_OR_': _binary,
      r'$_NOR_': _binary,
      r'$_XOR_': _binary,
      r'$_XNOR_': _binary,
      r'$_ANDNOT_': _binary,
      r'$_ORNOT_': _binary,
      r'$_NOT_': _unary,
      r'$_BUF_': _unary,
      r'$_MUX_': _mux,
      r'$_NMUX_': _mux,
    };
