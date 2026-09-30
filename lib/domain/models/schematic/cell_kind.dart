// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Coarse classification of a netlist cell into one of the symbols
/// the schematic canvas knows how to draw.
///
/// The taxonomy is kept tight: anything that isn't on the short
/// list of recognized primitives falls back to [generic] and gets
/// drawn as a labeled rectangle. The enum can be extended
/// without disrupting the layout pipeline — the renderer just gains a
/// new symbol painter for each entry.
///
/// Mapping is performed by [cellKindFromYosysType].
enum CellKind {
  /// AND gate — `$and`, `$reduce_and`, `$logic_and`.
  andGate,

  /// OR gate — `$or`, `$reduce_or`, `$logic_or`.
  orGate,

  /// Inverter — `$not`, `$reduce_bool` (single-bit invert).
  notGate,

  /// Multiplexer — `$mux`, `$pmux`.
  mux,

  /// Edge-triggered flip-flop — any cell whose type starts with
  /// `$dff` or `$adff` or `$sdff` (Yosys's flop family).
  flipFlop,

  /// Level-sensitive latch — `$dlatch`, `$adlatch`.
  latch,

  /// User-defined module instance, or any unrecognized primitive
  /// rendered as a labeled rectangle.
  generic,
}

/// Maps a Yosys cell type string (`$and`, `$mux`, `cpu`, …) into the
/// closest [CellKind] the renderer knows how to draw.
///
/// Recognition is *prefix-aware* for the families Yosys parametrizes
/// (`$adff_NN_NN_NN…`), so the schematic survives techmap variations
/// without the builder needing an exhaustive table.
CellKind cellKindFromYosysType(String type) {
  if (type.startsWith(r'$adff') ||
      type.startsWith(r'$sdff') ||
      type.startsWith(r'$dff') ||
      type.startsWith(r'$dffe') ||
      type.startsWith(r'$dffsr')) {
    return CellKind.flipFlop;
  }
  if (type.startsWith(r'$adlatch') || type.startsWith(r'$dlatch')) {
    return CellKind.latch;
  }
  switch (type) {
    case r'$and':
    case r'$reduce_and':
    case r'$logic_and':
      return CellKind.andGate;
    case r'$or':
    case r'$reduce_or':
    case r'$logic_or':
      return CellKind.orGate;
    case r'$not':
    case r'$reduce_bool':
      return CellKind.notGate;
    case r'$mux':
    case r'$pmux':
      return CellKind.mux;
  }
  return CellKind.generic;
}

/// True when [type] names an edge-triggered register cell: any Yosys
/// flop primitive (the [CellKind.flipFlop] family, `$dff*` / `$adff*` /
/// `$sdff*`) plus user-defined flops whose type name ends in `_dff` /
/// `_ff` / `_reg` (case-insensitive).
///
/// This is the shared sequential/combinational predicate for the
/// netlist analyses (clock-domain, reset-domain, FSM detection) that
/// walk register-to-register topology. Latches deliberately do *not*
/// count: level-sensitive storage breaks the Q→D hop assumptions those
/// walkers make, so a latch terminates a chain like any combinational
/// cell.
bool isRegisterCellType(String type) {
  if (cellKindFromYosysType(type) == CellKind.flipFlop) return true;
  final lower = type.toLowerCase();
  return lower.endsWith('_dff') ||
      lower.endsWith('_ff') ||
      lower.endsWith('_reg');
}
