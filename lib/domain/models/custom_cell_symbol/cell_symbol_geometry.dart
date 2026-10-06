// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:netcrux/domain/models/custom_cell_symbol/custom_cell_symbol.dart';
import 'package:netcrux/domain/models/custom_cell_symbol/port_anchor.dart';

/// The part of a [CustomCellSymbol] the layout needs: the drawing's aspect
/// ratio and its port anchors.
///
/// The layout sizes a symbol-bearing cell's node to [aspect], so the
/// drawing fills the node without letterboxing, and pins each anchored port
/// to the node face its anchor names. See `buildElkInput`.
@immutable
class CellSymbolGeometry {
  /// Creates a geometry. [aspect] is width over height.
  const CellSymbolGeometry({required this.aspect, required this.anchors});

  /// The geometry of [symbol]: the aspect of the artwork as the renderer
  /// draws it ([svgIntrinsicSize]), falling back to the symbol's declared
  /// [CustomCellSymbol.width] and [CustomCellSymbol.height] when the
  /// content carries no usable size. Clamped to [minAspect]..[maxAspect]
  /// so a degenerate drawing cannot produce a sliver of a node.
  factory CellSymbolGeometry.fromSymbol(CustomCellSymbol symbol) {
    final intrinsic = symbol.kind == CustomCellSymbolKind.svg
        ? svgIntrinsicSize(symbol.content)
        : null;
    final width = intrinsic?.width ?? symbol.width;
    final height = intrinsic?.height ?? symbol.height;
    final raw = width > 0 && height > 0 ? width / height : 1.0;
    return CellSymbolGeometry(
      aspect: raw.clamp(minAspect, maxAspect),
      anchors: Map<String, PortAnchor>.unmodifiable(symbol.portAnchors),
    );
  }

  /// The narrowest node a symbol may ask for, as width over height.
  static const double minAspect = 0.2;

  /// The widest node a symbol may ask for, as width over height.
  static const double maxAspect = 5;

  /// Width over height of the drawing.
  final double aspect;

  /// Port name to anchor, as the symbol declares them.
  final Map<String, PortAnchor> anchors;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! CellSymbolGeometry) return false;
    if (other.aspect != aspect) return false;
    if (other.anchors.length != anchors.length) return false;
    for (final entry in anchors.entries) {
      if (other.anchors[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    aspect,
    Object.hashAllUnordered(
      anchors.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );

  @override
  String toString() =>
      'CellSymbolGeometry(aspect=$aspect, anchors=${anchors.length})';
}

/// The [CellSymbolGeometry] of every module type that has a custom symbol,
/// keyed by module type (the `type` of the cells it draws). Value-equal, so
/// a provider holding it only notifies when a geometry actually changed.
@immutable
class CellSymbolGeometries {
  /// Wraps [byType].
  const CellSymbolGeometries(this.byType);

  /// The geometries of every symbol in [symbols], a registry snapshot keyed
  /// by module type.
  factory CellSymbolGeometries.fromSnapshot(
    Map<String, CustomCellSymbol> symbols,
  ) {
    if (symbols.isEmpty) return none;
    return CellSymbolGeometries(
      Map<String, CellSymbolGeometry>.unmodifiable(<String, CellSymbolGeometry>{
        for (final entry in symbols.entries)
          entry.key: CellSymbolGeometry.fromSymbol(entry.value),
      }),
    );
  }

  /// No symbols: every cell keeps its built-in geometry.
  static const CellSymbolGeometries none = CellSymbolGeometries(
    <String, CellSymbolGeometry>{},
  );

  /// Module type to geometry.
  final Map<String, CellSymbolGeometry> byType;

  /// Whether no module type has a symbol.
  bool get isEmpty => byType.isEmpty;

  /// The geometry for cells of [type], or `null` when it has no symbol.
  CellSymbolGeometry? operator [](String type) => byType[type];

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! CellSymbolGeometries) return false;
    if (other.byType.length != byType.length) return false;
    for (final entry in byType.entries) {
      if (other.byType[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAllUnordered(
    byType.entries.map((e) => Object.hash(e.key, e.value)),
  );
}

/// The size an SVG document declares for itself, as the renderer reads it:
/// the root element's `viewBox` width and height when present, otherwise
/// its numeric `width` and `height` attributes (bare or `px`). `null` when
/// [content] has no root `<svg>` element or neither gives a positive size.
///
/// The viewBox wins over `width`/`height` because that is the box the
/// renderer scales into the cell. Pure string parsing, so the layout can
/// size a node without parsing the drawing.
SymbolArtworkSize? svgIntrinsicSize(String content) {
  final root = RegExp(r'<svg\b([^>]*)>', caseSensitive: false).firstMatch(
    content,
  );
  if (root == null) return null;
  // Group 1 is not optional in the pattern, so a match always has it.
  final attributes = root.group(1)!;
  String? attribute(String name) {
    final match = RegExp(
      r'(?:^|\s)'
      '$name'
      r'''\s*=\s*("([^"]*)"|'([^']*)')''',
    ).firstMatch(attributes);
    if (match == null) return null;
    return match.group(2) ?? match.group(3);
  }

  final viewBox = attribute('viewBox');
  if (viewBox != null && viewBox.trim().isNotEmpty) {
    final parts = viewBox.trim().split(RegExp(r'[\s,]+'));
    if (parts.length >= 4) {
      final width = double.tryParse(parts[2]);
      final height = double.tryParse(parts[3]);
      if (width != null && height != null && width > 0 && height > 0) {
        return SymbolArtworkSize(width, height);
      }
    }
  }
  double? dimension(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    final number = trimmed.endsWith('px')
        ? trimmed.substring(0, trimmed.length - 2)
        : trimmed;
    final value = double.tryParse(number);
    return value != null && value > 0 ? value : null;
  }

  final width = dimension(attribute('width'));
  final height = dimension(attribute('height'));
  if (width == null || height == null) return null;
  return SymbolArtworkSize(width, height);
}

/// A width and height pair, kept free of `dart:ui` so the domain layer
/// stays pure.
@immutable
class SymbolArtworkSize {
  /// Creates a size.
  const SymbolArtworkSize(this.width, this.height);

  /// Width.
  final double width;

  /// Height.
  final double height;

  @override
  bool operator ==(Object other) =>
      other is SymbolArtworkSize &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => 'SymbolArtworkSize($width, $height)';
}
