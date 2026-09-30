// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:netcrux/domain/models/schematic/laid_out_graph.dart';

/// Produces an SVG document representing a [LaidOutGraph].
///
/// Pure function — no I/O, no Flutter. Used by the export controller
/// when the user picks "Save as SVG…". Mirrors the same primitives
/// the painter draws (cell rectangles with labels, wires as polylines,
/// boundary ports as filled rectangles) so a printed SVG looks like
/// the on-screen overview band.
class SvgExporter {
  /// Creates an exporter.
  const SvgExporter();

  /// Serializes [graph] into a self-contained SVG document.
  String toSvg(LaidOutGraph graph) {
    final bounds = graph.layout.bounds;
    final width = bounds.width;
    final height = bounds.height;
    final buffer = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln(
        '<svg xmlns="http://www.w3.org/2000/svg" '
        'width="${width.toStringAsFixed(2)}" '
        'height="${height.toStringAsFixed(2)}" '
        'viewBox="0 0 ${width.toStringAsFixed(2)} '
        '${height.toStringAsFixed(2)}">',
      )
      ..writeln('  <rect width="100%" height="100%" fill="#1A1A1A" />');

    // Cells.
    for (final cell in graph.graph.cells) {
      final pos = graph.layout.findNode(cell.id);
      if (pos == null) continue;
      buffer
        ..writeln(
          '  <rect x="${pos.bounds.x}" y="${pos.bounds.y}" '
          'width="${pos.bounds.width}" '
          'height="${pos.bounds.height}" '
          'fill="#2B2B2B" stroke="#E0E0E0" />',
        )
        ..writeln(
          '  <text x="${pos.bounds.x + pos.bounds.width / 2}" '
          'y="${pos.bounds.y + pos.bounds.height / 2}" '
          'font-family="monospace" font-size="11" fill="#E0E0E0" '
          'text-anchor="middle" dominant-baseline="middle">'
          '${_escape(cell.displayLabel)}</text>',
        );
    }

    // Boundary ports.
    for (final port in graph.graph.boundaryPorts) {
      final pos = graph.layout.findNode(port.id);
      if (pos == null) continue;
      buffer.writeln(
        '  <rect x="${pos.bounds.x}" y="${pos.bounds.y}" '
        'width="${pos.bounds.width}" '
        'height="${pos.bounds.height}" '
        'fill="#FFB627" />',
      );
    }

    // Edges.
    for (final edge in graph.layout.edges) {
      if (edge.points.length < 2) continue;
      final pts = edge.points
          .map((p) => '${p.x.toStringAsFixed(2)},${p.y.toStringAsFixed(2)}')
          .join(' ');
      buffer.writeln(
        '  <polyline points="$pts" fill="none" '
        'stroke="#9AA0A6" stroke-width="1.2" />',
      );
    }

    buffer.writeln('</svg>');
    return buffer.toString();
  }
}

@visibleForTesting
String svgEscape(String value) => _escape(value);

String _escape(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}
