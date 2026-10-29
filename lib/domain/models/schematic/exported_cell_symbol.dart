// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:netcrux/domain/models/schematic/schematic_graph.dart';

/// The artwork an SVG export draws for a cell that has a custom symbol: the
/// export-side twin of what a `CellBodyPainterFactory` paints on the canvas.
@immutable
sealed class ExportedCellSymbol {
  const ExportedCellSymbol();
}

/// A custom symbol drawn from its SVG [document], already cleaned of active
/// content. The export scales it to fit the cell, centred and keeping its
/// aspect ratio, as the canvas does.
final class ExportedCellSymbolSvg extends ExportedCellSymbol {
  /// Wraps [document].
  const ExportedCellSymbolSvg(this.document);

  /// A whole SVG document, root `<svg>` element and all.
  final String document;
}

/// A custom symbol whose artwork cannot be drawn. The canvas falls back to
/// the generic box for it, and so does the export.
final class ExportedCellSymbolUnrenderable extends ExportedCellSymbol {
  /// The one instance.
  const ExportedCellSymbolUnrenderable();
}

/// Returns the custom symbol artwork for [cell], or `null` when the cell has
/// no custom symbol and draws its built-in symbol.
typedef CellSymbolSvgSource = ExportedCellSymbol? Function(SchematicCell cell);

/// The open-core default: no cell has a custom symbol.
ExportedCellSymbol? noCellSymbolSvg(SchematicCell cell) => null;
