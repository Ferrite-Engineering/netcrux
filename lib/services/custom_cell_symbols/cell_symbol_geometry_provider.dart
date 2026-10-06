// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/models/custom_cell_symbol/cell_symbol_geometry.dart';
import 'package:netcrux/domain/models/custom_cell_symbol/custom_cell_symbol.dart';
import 'package:netcrux/services/custom_cell_symbols/custom_cell_symbol_registry_provider.dart';

/// The layout geometry of every registered custom cell symbol, derived from
/// [customCellSymbolSnapshotProvider].
///
/// The layout pipeline watches this rather than the snapshot itself:
/// [CellSymbolGeometries] is value-equal and carries only what changes a
/// layout (aspect and anchors), so editing a symbol's author or notes, or a
/// snapshot that re-emits the same symbols, never re-solves the scope.
/// Open-core always resolves to [CellSymbolGeometries.none].
final cellSymbolGeometriesProvider = Provider<CellSymbolGeometries>(
  (ref) {
    final snapshot =
        ref.watch(customCellSymbolSnapshotProvider).value ??
        const <String, CustomCellSymbol>{};
    return CellSymbolGeometries.fromSnapshot(snapshot);
  },
  name: 'cellSymbolGeometriesProvider',
);
