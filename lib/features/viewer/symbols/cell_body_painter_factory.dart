// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:netcrux/domain/models/schematic/schematic_graph.dart';
import 'package:netcrux/features/viewer/symbols/symbol_painters.dart';

/// Factory that returns the [SymbolPainter] to use for a given
/// [SchematicCell]. The open-core default always returns
/// `painterFor(cell.kind)`; the Pro overlay overrides this
/// to first consult the [CustomCellSymbolRegistry] snapshot — if a
/// symbol is bound to `cell.type`, the Pro factory returns an
/// SVG-rendering painter; otherwise the built-in painter for
/// `cell.kind` runs unchanged.
///
/// The factory is invoked once per cell per paint by the schematic
/// renderer. It must stay cheap — Pro implementations cache the
/// painter per symbol so the per-cell cost is a Map lookup, not a
/// fresh SVG parse.
typedef CellBodyPainterFactory = SymbolPainter Function(SchematicCell cell);

/// The open-core default factory — always returns the built-in
/// [SymbolPainter] for `cell.kind`. Pure, stateless, safe to share
/// across paints.
SymbolPainter defaultCellBodyPainterFactory(SchematicCell cell) {
  return painterFor(cell.kind);
}
