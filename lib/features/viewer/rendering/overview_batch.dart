// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:netcrux/domain/models/layout/edge_route.dart';

/// Axis-aligned rectangles, each with one colour, gathered into a single
/// triangle list for one `drawVertices` call.
///
/// At overview zoom tens of thousands of cells are on screen at once, and
/// each used to cost a `save`, a `translate`, a `drawRect` and a `restore`:
/// four calls across the engine boundary per cell, which is where a frame
/// spent its budget (the design-space cull had already removed the scan). A
/// batch writes the same rectangles into typed arrays, which is Dart
/// arithmetic, and hands them to the engine once. The rectangles do not
/// overlap, so drawing them in one pass composites exactly as drawing them
/// one at a time did.
class OverviewRectBatch {
  /// Creates a batch sized for about [capacity] rectangles; it grows as
  /// needed.
  OverviewRectBatch([int capacity = 1024])
    : _positions = Float32List(math.max(capacity, 1) * 12),
      _colors = Int32List(math.max(capacity, 1) * 6);

  Float32List _positions;
  Int32List _colors;
  int _count = 0;

  /// Rectangles added so far.
  int get length => _count;

  /// Whether nothing has been added.
  bool get isEmpty => _count == 0;

  /// Adds [rect] filled with [color], grown to [floor] on each side it falls
  /// short of, anchored at its top-left: the overview band's device-pixel
  /// floor, which keeps a cell a visible speck at the zoom a huge scope fits
  /// at.
  void add(Rect rect, Color color, {double floor = 0}) {
    addLTRB(
      rect.left,
      rect.top,
      rect.left + math.max(rect.width, floor),
      rect.top + math.max(rect.height, floor),
      color,
    );
  }

  /// Adds the rectangle with edges [left], [top], [right], [bottom], filled
  /// with [color].
  void addLTRB(
    double left,
    double top,
    double right,
    double bottom,
    Color color,
  ) {
    if ((_count + 1) * 12 > _positions.length) _grow();
    final p = _count * 12;
    final c = _count * 6;
    // Two triangles: top-left, top-right, bottom-right; then top-left,
    // bottom-right, bottom-left.
    _positions
      ..[p] = left
      ..[p + 1] = top
      ..[p + 2] = right
      ..[p + 3] = top
      ..[p + 4] = right
      ..[p + 5] = bottom
      ..[p + 6] = left
      ..[p + 7] = top
      ..[p + 8] = right
      ..[p + 9] = bottom
      ..[p + 10] = left
      ..[p + 11] = bottom;
    final argb = color.toARGB32();
    for (var i = 0; i < 6; i++) {
      _colors[c + i] = argb;
    }
    _count++;
  }

  void _grow() {
    final positions = Float32List(_positions.length * 2)
      ..setRange(0, _positions.length, _positions);
    final colors = Int32List(_colors.length * 2)
      ..setRange(0, _colors.length, _colors);
    _positions = positions;
    _colors = colors;
  }

  /// The rectangle added [index]th, as it will be drawn.
  Rect rectAt(int index) {
    final p = index * 12;
    return Rect.fromLTRB(
      _positions[p],
      _positions[p + 1],
      _positions[p + 4],
      _positions[p + 5],
    );
  }

  /// The colour the rectangle added [index]th is drawn in.
  Color colorAt(int index) => Color(_colors[index * 6]);

  /// Draws every rectangle on [canvas] in one call, with the colours as
  /// given (the paint contributes nothing: [BlendMode.dst] keeps the vertex
  /// colours, and compositing onto the canvas is the usual source-over).
  /// Does nothing when the batch is empty.
  void paint(Canvas canvas) {
    if (_count == 0) return;
    final vertices = Vertices.raw(
      VertexMode.triangles,
      Float32List.sublistView(_positions, 0, _count * 12),
      colors: Int32List.sublistView(_colors, 0, _count * 6),
    );
    canvas.drawVertices(vertices, BlendMode.dst, Paint());
    vertices.dispose();
  }
}

/// Straight line segments gathered for one `drawRawPoints` call in
/// [PointMode.lines], all stroked with the same paint.
///
/// A wire is an orthogonal polyline; at overview zoom it is a line a pixel
/// wide, so stroking each of its segments on its own, with the paint's round
/// cap, draws what stroking the polyline as one path did, without a `Path`
/// built and a `drawPath` issued per wire.
class OverviewLineBatch {
  /// Creates a batch sized for about [capacity] segments; it grows as
  /// needed.
  OverviewLineBatch([int capacity = 1024])
    : _points = Float32List(math.max(capacity, 1) * 4);

  Float32List _points;
  int _segments = 0;

  /// Segments added so far.
  int get length => _segments;

  /// Whether nothing has been added.
  bool get isEmpty => _segments == 0;

  /// Adds every segment of [points], a polyline of at least two points.
  void addPolyline(List<LayoutPoint> points) {
    for (var i = 0; i + 1 < points.length; i++) {
      addSegment(points[i].x, points[i].y, points[i + 1].x, points[i + 1].y);
    }
  }

  /// Adds the segment from ([x0], [y0]) to ([x1], [y1]).
  void addSegment(double x0, double y0, double x1, double y1) {
    if ((_segments + 1) * 4 > _points.length) {
      // Copy the whole old buffer. Inside a cascade on the new list,
      // `_points` still names the old one, so its full length is the range.
      final grown = Float32List(_points.length * 2)
        ..setRange(0, _points.length, _points);
      _points = grown;
    }
    final p = _segments * 4;
    _points
      ..[p] = x0
      ..[p + 1] = y0
      ..[p + 2] = x1
      ..[p + 3] = y1;
    _segments++;
  }

  /// Strokes every segment on [canvas] with [paint] in one call. Does
  /// nothing when the batch is empty.
  void paint(Canvas canvas, Paint paint) {
    if (_segments == 0) return;
    canvas.drawRawPoints(
      PointMode.lines,
      Float32List.sublistView(_points, 0, _segments * 4),
      paint,
    );
  }
}
