// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:netcrux/domain/models/custom_cell_symbol/cell_symbol_geometry.dart';
import 'package:netcrux/domain/models/layout/bounding_box.dart';
import 'package:netcrux/domain/models/layout/node_position.dart';
import 'package:netcrux/domain/models/netlist/port_direction.dart';
import 'package:netcrux/domain/models/schematic/exported_cell_symbol.dart';
import 'package:netcrux/domain/models/schematic/laid_out_graph.dart';
import 'package:netcrux/domain/models/schematic/pin_tie.dart';
import 'package:netcrux/domain/models/schematic/schematic_graph.dart';
import 'package:netcrux/domain/models/schematic/symbol_shapes.dart';

/// The colours an SVG export is drawn in, as CSS colour strings: the canvas
/// theme roles each mark takes its colour from.
@immutable
class SvgExportPalette {
  /// Creates a palette.
  const SvgExportPalette({
    required this.background,
    required this.body,
    required this.stroke,
    required this.label,
    required this.wire,
    required this.port,
    required this.pin,
    required this.undriven,
  });

  /// The dark palette an export without a theme is drawn in.
  static const SvgExportPalette dark = SvgExportPalette(
    background: '#1A1A1A',
    body: '#2B2B2B',
    stroke: '#E0E0E0',
    label: '#E0E0E0',
    wire: '#9AA0A6',
    port: '#FFB627',
    pin: '#FFB627',
    undriven: '#F2B8B5',
  );

  /// The canvas background (`surface`); also the backing behind labels.
  final String background;

  /// Symbol body fill (`surfaceContainerHighest`).
  final String body;

  /// Symbol outline (`onSurface`).
  final String stroke;

  /// Label text (`onSurface`).
  final String label;

  /// Wires and constant pin stubs (`onSurfaceVariant`).
  final String wire;

  /// Module ports (`tertiary`).
  final String port;

  /// Cell pin dots (`primary`).
  final String pin;

  /// Undriven pin dots and stubs (`error`).
  final String undriven;
}

/// Produces an SVG document representing a [LaidOutGraph].
///
/// Pure function: no I/O, no Flutter. Used by the export controller when the
/// user picks "Save as SVG…" and by `tool/render_schematic.dart`. Draws what
/// the canvas draws at detail zoom: each cell's symbol from the same shape
/// description the canvas painters use (`symbol_shapes.dart`), or its custom
/// symbol artwork; cell labels, pin dots and constant or undriven pin stubs;
/// the wires; and the module ports with their names.
class SvgExporter {
  /// Creates an exporter.
  const SvgExporter();

  /// Font size of cell, pin and module port labels (the canvas's
  /// `labelSmall`).
  static const double labelFontSize = 11;

  /// Serializes [graph] into a self-contained SVG document.
  ///
  /// With a [frame] (layout coordinates) the document shows that part of the
  /// layout, its size the frame's, and its background covers the frame.
  /// Without one it is sized to the layout bounds from the origin, as the
  /// Save as SVG export has always written it.
  ///
  /// [customSymbols] gives the artwork of cells with a custom symbol; every
  /// other cell draws the built-in symbol for its kind. [palette] colours the
  /// drawing.
  String toSvg(
    LaidOutGraph graph, {
    BoundingBox? frame,
    CellSymbolSvgSource customSymbols = noCellSymbolSvg,
    SvgExportPalette palette = SvgExportPalette.dark,
  }) {
    final bounds = graph.layout.bounds;
    final x = frame?.x ?? 0;
    final y = frame?.y ?? 0;
    final width = frame?.width ?? bounds.width;
    final height = frame?.height ?? bounds.height;
    final viewBox = frame == null
        ? '0 0 ${_n(width)} ${_n(height)}'
        : '${_n(x)} ${_n(y)} ${_n(width)} ${_n(height)}';
    final buffer = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln(
        '<svg xmlns="http://www.w3.org/2000/svg" '
        'width="${_n(width)}" '
        'height="${_n(height)}" '
        'viewBox="$viewBox">',
      )
      ..writeln(
        frame == null
            ? '  <rect width="100%" height="100%" '
                  'fill="${palette.background}" />'
            : '  <rect x="${_n(x)}" '
                  'y="${_n(y)}" '
                  'width="${_n(width)}" '
                  'height="${_n(height)}" fill="${palette.background}" />',
      );

    final outsideLabels = <(SchematicCell, NodePosition)>[];

    // Cells: body, then label or pin names, then pin marks.
    for (final cell in graph.graph.cells) {
      final pos = graph.layout.findNode(cell.id);
      if (pos == null) continue;
      final box = pos.bounds;
      final custom = customSymbols(cell);
      if (custom is ExportedCellSymbolSvg) {
        _writeCustomSymbol(buffer, cell, box, custom.document);
      } else {
        final shape = custom is ExportedCellSymbolUnrenderable
            ? genericBoxShape(box.width, box.height)
            : symbolShapeFor(cell.kind, box.width, box.height);
        _writeShape(buffer, cell, box, shape, palette);
      }
      final anchoredPins = graph.symbolCells[cell.id];
      if (anchoredPins == null) {
        _writeText(
          buffer,
          cell.displayLabel,
          x: box.x + box.width / 2,
          y: box.y + box.height / 2,
          anchor: 'middle',
          baseline: 'middle',
          fontSize: labelFontSize,
          fill: palette.label,
          cssClass: 'cell-label',
          maxWidth: box.width - 8,
          elideStart: true,
        );
      } else {
        _writePinNames(buffer, cell, pos, anchoredPins, palette);
        outsideLabels.add((cell, pos));
      }
      _writePinMarks(buffer, cell, pos, palette);
    }

    // Edges.
    for (final edge in graph.layout.edges) {
      if (edge.points.length < 2) continue;
      final pts = edge.points.map((p) => '${_n(p.x)},${_n(p.y)}').join(' ');
      buffer.writeln(
        '  <polyline points="$pts" fill="none" '
        'stroke="${palette.wire}" stroke-width="1.2" '
        'stroke-linecap="round" />',
      );
    }

    // Boundary ports, each named on the side its wire does not use.
    for (final port in graph.graph.boundaryPorts) {
      final pos = graph.layout.findNode(port.id);
      if (pos == null) continue;
      final b = pos.bounds;
      buffer.writeln(
        '  <rect x="${b.x}" y="${b.y}" '
        'width="${b.width}" '
        'height="${b.height}" '
        'fill="${palette.port}" />',
      );
      final input = port.direction == PortDirection.input;
      _writeText(
        buffer,
        port.name,
        x: input
            ? b.x - SchematicDetailMarks.boundaryLabelGap
            : b.right + SchematicDetailMarks.boundaryLabelGap,
        y: b.y + b.height / 2,
        anchor: input ? 'end' : 'start',
        baseline: 'middle',
        fontSize: labelFontSize,
        fill: palette.label,
        cssClass: 'port-label',
        maxWidth: 80,
      );
    }

    // Labels of custom-symbol cells, outside the drawing and over the wires.
    for (final (cell, pos) in outsideLabels) {
      _writeOutsideLabel(buffer, graph, cell, pos, palette);
    }

    buffer.writeln('</svg>');
    return buffer.toString();
  }

  void _writeShape(
    StringBuffer buffer,
    SchematicCell cell,
    BoundingBox box,
    List<SymbolPrimitive> shape,
    SvgExportPalette palette,
  ) {
    buffer.writeln(
      '  <g class="cell" data-kind="${cell.kind.name}" '
      'transform="translate(${_n(box.x)},${_n(box.y)})">',
    );
    for (final element in symbolShapeSvgElements(
      shape,
      body: palette.body,
      stroke: palette.stroke,
    )) {
      buffer.writeln('    $element');
    }
    buffer.writeln('  </g>');
  }

  void _writeCustomSymbol(
    StringBuffer buffer,
    SchematicCell cell,
    BoundingBox box,
    String document,
  ) {
    final size = svgIntrinsicSize(document);
    final viewBox = size == null
        ? ''
        : ' viewBox="0 0 ${_n(size.width)} ${_n(size.height)}"';
    buffer
      ..writeln(
        '  <svg class="cell custom-symbol" '
        'data-type="${_escape(cell.type)}" '
        'x="${_n(box.x)}" y="${_n(box.y)}" '
        'width="${_n(box.width)}" height="${_n(box.height)}"$viewBox '
        'preserveAspectRatio="xMidYMid meet" overflow="hidden">',
      )
      ..writeln(_stripProlog(document))
      ..writeln('  </svg>');
  }

  void _writePinNames(
    StringBuffer buffer,
    SchematicCell cell,
    NodePosition pos,
    Set<String> anchoredPins,
    SvgExportPalette palette,
  ) {
    const fontSize = labelFontSize * 0.8;
    const inset = SchematicDetailMarks.pinNameInset;
    final width = pos.bounds.width;
    final height = pos.bounds.height;
    for (final port in cell.ports) {
      if (!anchoredPins.contains(port.name)) continue;
      final box = pos.ports[port.id];
      if (box == null) continue;
      final cx = pos.bounds.x + box.x + box.width / 2;
      final cy = pos.bounds.y + box.y + box.height / 2;
      final left = pos.bounds.x;
      final top = pos.bounds.y;
      final face = symbolPinFace(box, width, height);
      final vertical =
          face == SchematicPortSide.west || face == SchematicPortSide.east;
      final (tx, ty, anchor, baseline) = switch (face) {
        SchematicPortSide.west => (left + inset, cy, 'start', 'middle'),
        SchematicPortSide.east => (left + width - inset, cy, 'end', 'middle'),
        SchematicPortSide.north => (cx, top + inset, 'middle', 'hanging'),
        SchematicPortSide.south => (
          cx,
          top + height - inset,
          'middle',
          'text-after-edge',
        ),
      };
      _writeText(
        buffer,
        port.name,
        x: tx,
        y: ty,
        anchor: anchor,
        baseline: baseline,
        fontSize: fontSize,
        fill: palette.label,
        cssClass: 'pin-name',
        maxWidth: math.max(1, (vertical ? width / 2 : width) - 2 * inset),
      );
    }
  }

  void _writePinMarks(
    StringBuffer buffer,
    SchematicCell cell,
    NodePosition pos,
    SvgExportPalette palette,
  ) {
    for (final port in cell.ports) {
      final box = pos.ports[port.id];
      if (box == null) continue;
      final cx = pos.bounds.x + box.x + box.width / 2;
      final cy = pos.bounds.y + box.y + box.height / 2;
      final tie = port.tie;
      final undriven = tie.kind == PinTieKind.undriven;
      if (tie.kind == PinTieKind.constant || undriven) {
        final outward = tieStubOutward(box, pos.bounds.width);
        final endX = cx + outward * SchematicDetailMarks.tieStubLength;
        final colour = undriven ? palette.undriven : palette.wire;
        final strokeWidth = undriven
            ? SchematicDetailMarks.undrivenStubWidth
            : SchematicDetailMarks.constantStubWidth;
        buffer.writeln(
          '  <line class="tie-stub" x1="${_n(cx)}" y1="${_n(cy)}" '
          'x2="${_n(endX)}" y2="${_n(cy)}" stroke="$colour" '
          'stroke-width="${_n(strokeWidth)}" />',
        );
        if (undriven) {
          const ring = SchematicDetailMarks.undrivenRingRadius;
          buffer.writeln(
            '  <circle class="undriven-ring" '
            'cx="${_n(endX + outward * ring)}" cy="${_n(cy)}" '
            'r="${_n(ring)}" fill="none" stroke="$colour" '
            'stroke-width="${_n(strokeWidth)}" />',
          );
        } else if (tie.constantText case final text?) {
          const gap = SchematicDetailMarks.tieLabelGap;
          _writeText(
            buffer,
            text,
            x: outward < 0 ? endX - gap : endX + gap,
            y: cy,
            anchor: outward < 0 ? 'end' : 'start',
            baseline: 'middle',
            fontSize: SchematicDetailMarks.tieLabelFontSize,
            fill: colour,
            cssClass: 'tie-label',
            maxWidth: 28,
          );
        }
      }
      buffer.writeln(
        '  <circle class="pin" cx="${_n(cx)}" cy="${_n(cy)}" '
        'r="${_n(SchematicDetailMarks.pinDotRadius)}" '
        'fill="${undriven ? palette.undriven : palette.pin}" />',
      );
    }
  }

  void _writeOutsideLabel(
    StringBuffer buffer,
    LaidOutGraph graph,
    SchematicCell cell,
    NodePosition pos,
    SvgExportPalette palette,
  ) {
    final label = cell.displayLabel;
    final maxWidth = math.max(
      pos.bounds.width,
      SchematicDetailMarks.outsideLabelMinWidth,
    );
    final width = math.min(
      estimateTextWidth(
        fitLabel(label, maxWidth, labelFontSize, elideStart: true),
        labelFontSize,
      ),
      maxWidth,
    );
    const height = labelFontSize * 1.4;
    final box = outsideLabelBox(
      pos.bounds,
      width,
      height,
      isFree: (candidate) => _isFreeOfOtherNodes(graph, candidate, cell.id),
    );
    buffer.writeln(
      '  <rect class="label-backing" x="${_n(box.x - 1)}" '
      'y="${_n(box.y - 1)}" width="${_n(box.width + 2)}" '
      'height="${_n(box.height + 2)}" fill="${palette.background}" '
      'fill-opacity="0.85" />',
    );
    _writeText(
      buffer,
      label,
      x: box.x + box.width / 2,
      y: box.y + box.height / 2,
      anchor: 'middle',
      baseline: 'middle',
      fontSize: labelFontSize,
      fill: palette.label,
      cssClass: 'cell-label',
      maxWidth: maxWidth,
      elideStart: true,
    );
  }

  static bool _isFreeOfOtherNodes(
    LaidOutGraph graph,
    BoundingBox rect,
    String selfId,
  ) {
    for (final node in graph.layout.nodes) {
      if (node.id == selfId) continue;
      final b = node.bounds;
      if (b.x < rect.right &&
          rect.x < b.right &&
          b.y < rect.bottom &&
          rect.y < b.bottom) {
        return false;
      }
    }
    return true;
  }

  static void _writeText(
    StringBuffer buffer,
    String text, {
    required double x,
    required double y,
    required String anchor,
    required String baseline,
    required double fontSize,
    required String fill,
    required String cssClass,
    double? maxWidth,
    bool elideStart = false,
  }) {
    final shown = maxWidth == null
        ? text
        : fitLabel(text, maxWidth, fontSize, elideStart: elideStart);
    // A shortened label keeps its full text as the element's tooltip.
    final title = shown == text ? '' : '<title>${_escape(text)}</title>';
    buffer.writeln(
      '  <text class="$cssClass" x="${_n(x)}" y="${_n(y)}" '
      'font-family="sans-serif" font-size="${_n(fontSize)}" fill="$fill" '
      'text-anchor="$anchor" dominant-baseline="$baseline">'
      '${_escape(shown)}$title</text>',
    );
  }
}

/// The SVG elements that draw [shape] in a cell's local box, one per piece,
/// filled with [body] and outlined with [stroke] as the canvas painters fill
/// and outline them.
List<String> symbolShapeSvgElements(
  List<SymbolPrimitive> shape, {
  required String body,
  required String stroke,
}) {
  return <String>[
    for (final piece in shape)
      _svgElement(
        piece,
        'fill="${piece.style == SymbolPrimitiveStyle.filledOutline ? body : 'none'}" '
        'stroke="$stroke" stroke-width="${_n(symbolStrokeWidth)}"',
      ),
  ];
}

String _svgElement(SymbolPrimitive piece, String paint) => switch (piece) {
  SymbolPath(:final commands) => '<path d="${svgPathData(commands)}" $paint />',
  SymbolCircle(:final cx, :final cy, :final radius) =>
    '<circle cx="${_n(cx)}" cy="${_n(cy)}" r="${_n(radius)}" $paint />',
  SymbolRect(
    :final left,
    :final top,
    :final right,
    :final bottom,
    :final cornerRadius,
  ) =>
    '<rect x="${_n(left)}" y="${_n(top)}" '
        'width="${_n(right - left)}" height="${_n(bottom - top)}"'
        '${cornerRadius > 0 ? ' rx="${_n(cornerRadius)}"' : ''} $paint />',
};

/// [commands] as SVG path data. An arc is clockwise (sweep flag 1) and the
/// smaller of the two (large-arc flag 0), as `Path.arcToPoint` draws it by
/// default.
String svgPathData(List<SymbolPathCommand> commands) => commands
    .map(
      (command) => switch (command) {
        SymbolMoveTo(:final x, :final y) => 'M ${_n(x)} ${_n(y)}',
        SymbolLineTo(:final x, :final y) => 'L ${_n(x)} ${_n(y)}',
        SymbolArcTo(:final x, :final y, :final radius) =>
          'A ${_n(radius)} ${_n(radius)} 0 0 1 ${_n(x)} ${_n(y)}',
        SymbolQuadTo(:final cx, :final cy, :final x, :final y) =>
          'Q ${_n(cx)} ${_n(cy)} ${_n(x)} ${_n(y)}',
        SymbolClose() => 'Z',
      },
    )
    .join(' ');

/// A width for [text] at [fontSize], for placing a label whose rendered
/// width the export cannot measure: the average advance of a sans-serif
/// face, about 0.6 of the font size a character.
double estimateTextWidth(String text, double fontSize) =>
    text.length * fontSize * 0.6;

/// [text] shortened to about [maxWidth] at [fontSize] ([estimateTextWidth]),
/// as the canvas shortens its labels: an ellipsis replaces the start when
/// [elideStart] (a flat netlist's cell names share a long dotted prefix, and
/// the end tells them apart), otherwise the end. Unchanged when it fits.
String fitLabel(
  String text,
  double maxWidth,
  double fontSize, {
  bool elideStart = false,
}) {
  if (estimateTextWidth(text, fontSize) <= maxWidth) return text;
  final keep = math.max(0, (maxWidth / (fontSize * 0.6)).floor() - 1);
  return elideStart
      ? '\u2026${text.substring(text.length - keep)}'
      : '${text.substring(0, keep)}\u2026';
}

String _stripProlog(String document) => document
    .replaceFirst(RegExp(r'^\s*<\?xml[^>]*\?>\s*'), '')
    .replaceFirst(RegExp(r'^\s*<!DOCTYPE[^>]*>\s*', caseSensitive: false), '');

String _n(double value) => value.toStringAsFixed(2);

@visibleForTesting
String svgEscape(String value) => _escape(value);

String _escape(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}
