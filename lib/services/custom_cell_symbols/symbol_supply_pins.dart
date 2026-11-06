// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:netcrux/domain/models/custom_cell_symbol/custom_cell_symbol.dart';
import 'package:netcrux/domain/models/schematic/cell_kind.dart';
import 'package:netcrux/domain/models/schematic/liberty_cell_symbols.dart';

/// [liberty] with the supply pins the custom [symbols] name
/// ([CustomCellSymbol.powerPins], [CustomCellSymbol.groundPins]) added for
/// the cell types whose cell library says nothing about supplies.
///
/// A type whose Liberty description declares any `pg_pin` keeps it exactly:
/// the library is the better authority on which pins carry a supply. A type
/// with a Liberty description but no `pg_pin` keeps its gate symbol and
/// clock pins and gains the symbol's supply pins. A type with no Liberty
/// description at all gains an entry drawn as a box (which its custom symbol
/// replaces on the canvas) whose only purpose is the supply rule:
/// unconnected supply pins are hidden in a scope that wires no supply
/// ([withoutUnconnectedSupplyPins]), and all of them are drawn once any is
/// wired.
///
/// [liberty] itself is returned when no symbol names a supply pin, so a
/// design without such symbols lays out exactly as before.
LibertyCellSymbols withSymbolSupplyPins(
  LibertyCellSymbols liberty,
  Map<String, CustomCellSymbol> symbols,
) {
  Map<String, LibertyCellSymbol>? merged;
  for (final entry in symbols.entries) {
    final symbol = entry.value;
    if (symbol.powerPins.isEmpty && symbol.groundPins.isEmpty) continue;
    final existing = liberty[entry.key];
    if (existing != null &&
        (existing.hasSupplyPins || existing.otherSupplyPins.isNotEmpty)) {
      continue;
    }
    (merged ??= Map<String, LibertyCellSymbol>.of(
      liberty.byType,
    ))[entry.key] = LibertyCellSymbol(
      kind: existing?.kind ?? CellKind.generic,
      clockPins: existing?.clockPins ?? const <String>{},
      powerPins: symbol.powerPins,
      groundPins: symbol.groundPins,
    );
  }
  if (merged == null) return liberty;
  return LibertyCellSymbols(
    Map<String, LibertyCellSymbol>.unmodifiable(merged),
  );
}
