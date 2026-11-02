// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/schematic/cell_kind.dart';
import 'package:netcrux/domain/models/schematic/liberty_cell_symbols.dart';
import 'package:netcrux/services/liberty/liberty_function.dart';
import 'package:netcrux/services/liberty/liberty_library.dart';

/// One cell of a design's cell libraries: the definition the design uses
/// (the first library's), the library it came from, and every library that
/// defines a cell of that name, in the project's order.
class LibertyCellRecord {
  /// Creates a record.
  LibertyCellRecord({
    required this.cell,
    required this.library,
    required List<LibertyLibrary> definedIn,
  }) : definedIn = List<LibertyLibrary>.unmodifiable(definedIn);

  /// The definition in use.
  final LibertyCell cell;

  /// The library [cell] came from.
  final LibertyLibrary library;

  /// Every library that defines the cell, [library] first: one per corner
  /// when a project lists a library for each.
  final List<LibertyLibrary> definedIn;

  /// How the cell is drawn, worked out on first use; `null` when it is
  /// drawn as a plain box with no supply pins to place.
  late final LibertyCellSymbol? symbol = libertyCellSymbolFor(cell);
}

/// The cells of a project's Liberty libraries by name, the first library to
/// define a name winning, as it does for elaboration.
class LibertyCellIndex {
  /// Indexes [libraries], in the project's order.
  LibertyCellIndex(List<LibertyLibrary> libraries) {
    final defining = <String, List<LibertyLibrary>>{};
    final first = <String, (LibertyCell, LibertyLibrary)>{};
    for (final library in libraries) {
      for (final cell in library.cells) {
        (defining[cell.name] ??= <LibertyLibrary>[]).add(library);
        first.putIfAbsent(cell.name, () => (cell, library));
      }
    }
    for (final entry in first.entries) {
      final (cell, library) = entry.value;
      _byName[entry.key] = LibertyCellRecord(
        cell: cell,
        library: library,
        definedIn: defining[entry.key]!,
      );
    }
  }

  /// No libraries.
  static final LibertyCellIndex empty = LibertyCellIndex(
    const <LibertyLibrary>[],
  );

  final Map<String, LibertyCellRecord> _byName = <String, LibertyCellRecord>{};

  /// The record of the cell named [name], or `null`.
  LibertyCellRecord? operator [](String name) => _byName[name];

  /// Whether no library defines any cell.
  bool get isEmpty => _byName.isEmpty;

  /// How many cells are indexed.
  int get length => _byName.length;

  /// The record cells of [type] in [model] are drawn and described from:
  /// `null` when no library defines [type], or when a module of the design
  /// does (a source definition wins over a library's, as it does for
  /// elaboration; the black-box module a library cell becomes does not
  /// count).
  LibertyCellRecord? forCellType(NetlistModel model, String type) {
    final record = _byName[type];
    if (record == null) return null;
    final module = model.modules[type];
    if (module != null && !module.isBlackBox) return null;
    return record;
  }

  /// The drawing of every cell type of [model] that comes from these
  /// libraries and is drawn differently from a plain box.
  LibertyCellSymbols symbolsFor(NetlistModel model) {
    if (isEmpty) return LibertyCellSymbols.none;
    final byType = <String, LibertyCellSymbol>{};
    for (final entry in _byName.entries) {
      final module = model.modules[entry.key];
      if (module != null && !module.isBlackBox) continue;
      final symbol = entry.value.symbol;
      if (symbol != null) byType[entry.key] = symbol;
    }
    if (byType.isEmpty) return LibertyCellSymbols.none;
    return LibertyCellSymbols(
      Map<String, LibertyCellSymbol>.unmodifiable(byType),
    );
  }
}

/// How [cell] is drawn: the symbol its function maps to, its clock pins and
/// its supply pins. `null` for a cell that keeps the plain box and has no
/// supply pin to place.
///
/// A gate symbol needs a cell with one output, scalar signal pins only, and
/// an output `function` that is one of the [LibertyGate]s over exactly its
/// inputs. A flip-flop or latch symbol needs a single `ff` or `latch` group
/// and outputs whose functions read only its state. Anything else, a
/// compound gate, a multi-output cell such as an adder, a cell with a
/// tri-state output, or a function that does not parse, keeps the box.
LibertyCellSymbol? libertyCellSymbolFor(LibertyCell cell) {
  final power = <String>{};
  final ground = <String>{};
  for (final entry in cell.pgPins.entries) {
    switch (_isPowerPin(entry.key, entry.value)) {
      case true:
        power.add(entry.key);
      case false:
        ground.add(entry.key);
      case null:
        break;
    }
  }
  final kind = _kindOf(cell);
  final clocks = kind == CellKind.flipFlop
      ? _clockPinsOf(cell)
      : const <String>{};
  if (kind == CellKind.generic && power.isEmpty && ground.isEmpty) {
    return null;
  }
  return LibertyCellSymbol(
    kind: kind,
    clockPins: clocks,
    powerPins: power,
    groundPins: ground,
  );
}

/// The symbol [cell]'s function maps to, or [CellKind.generic].
CellKind _kindOf(LibertyCell cell) {
  final inputs = <String>[];
  final outputs = <String>[];
  for (final port in cell.ports) {
    if (cell.pgPins.containsKey(port.name)) continue;
    if (port.isVector) return CellKind.generic;
    switch (port.direction) {
      case LibertyPortDirection.input:
        inputs.add(port.name);
      case LibertyPortDirection.output:
        outputs.add(port.name);
      case LibertyPortDirection.inout:
        return CellKind.generic;
    }
  }
  if (outputs.isEmpty || inputs.isEmpty || cell.hasOtherStorage) {
    return CellKind.generic;
  }
  // An output that can float is not the gate its function describes, even
  // when the enable is one of the function's inputs.
  if (outputs.any(cell.threeStatePins.contains)) return CellKind.generic;
  final storage = cell.storage;
  if (storage != null) {
    final state = storage.stateNames.toSet();
    for (final output in outputs) {
      final function = cell.functions[output];
      if (function == null) return CellKind.generic;
      final variables = LibertyExpression.tryParse(function)?.variables;
      if (variables == null ||
          variables.isEmpty ||
          !variables.every(state.contains)) {
        return CellKind.generic;
      }
    }
    return switch (storage.kind) {
      LibertyStorageKind.flipFlop => CellKind.flipFlop,
      LibertyStorageKind.latch => CellKind.latch,
    };
  }
  if (outputs.length != 1) return CellKind.generic;
  final function = cell.functions[outputs.single];
  if (function == null) return CellKind.generic;
  return switch (classifyLibertyFunction(function, inputs)) {
    LibertyGate.buffer => CellKind.buffer,
    LibertyGate.inverter => CellKind.notGate,
    LibertyGate.and => CellKind.andGate,
    LibertyGate.nand => CellKind.nandGate,
    LibertyGate.or => CellKind.orGate,
    LibertyGate.nor => CellKind.norGate,
    LibertyGate.xor => CellKind.xorGate,
    LibertyGate.xnor => CellKind.xnorGate,
    LibertyGate.mux2 => CellKind.mux,
    null => CellKind.generic,
  };
}

/// A flip-flop's clock pins: those marked `clock : true` and those its
/// `clocked_on` reads, when they are inputs of the cell.
Set<String> _clockPinsOf(LibertyCell cell) {
  final inputs = <String>{
    for (final port in cell.ports)
      if (port.direction == LibertyPortDirection.input) port.name,
  };
  final clockedOn = cell.storage?.clockedOn;
  return <String>{
    for (final pin in cell.clockPins)
      if (inputs.contains(pin)) pin,
    if (clockedOn != null)
      for (final pin
          in LibertyExpression.tryParse(clockedOn)?.variables ??
              const <String>[])
        if (inputs.contains(pin)) pin,
  };
}

/// Whether the supply pin [name] of [pgType] is a power pin (`true`), a
/// ground pin (`false`), or neither as far as can be told (`null`, left
/// where its direction puts it). The `pg_type` decides; without one, the
/// usual names do.
bool? _isPowerPin(String name, String? pgType) {
  switch (pgType) {
    case 'primary_power' ||
        'backup_power' ||
        'internal_power' ||
        'nwell' ||
        'deepnwell':
      return true;
    case 'primary_ground' ||
        'backup_ground' ||
        'internal_ground' ||
        'pwell' ||
        'deeppwell':
      return false;
  }
  final upper = name.toUpperCase();
  if (upper.startsWith('VDD') ||
      upper.startsWith('VCC') ||
      upper == 'VPWR' ||
      upper == 'VPB') {
    return true;
  }
  if (upper.startsWith('VSS') ||
      upper.startsWith('GND') ||
      upper == 'VGND' ||
      upper == 'VNB') {
    return false;
  }
  return null;
}
