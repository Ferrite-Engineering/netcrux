// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// Axis-aligned bounding box in layout coordinates.
///
/// ELK's coordinate system is the same as Flutter's painting coordinate
/// system: origin top-left, x increases right, y increases down. The
/// box's [width] and [height] are non-negative by construction.
@immutable
class BoundingBox {
  /// Creates a box.
  const BoundingBox({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  /// Parses a JSON shape `{ "x": …, "y": …, "width": …, "height": … }`.
  /// Missing keys default to `0`.
  factory BoundingBox.fromJson(Map<String, Object?> json) {
    return BoundingBox(
      x: _asDouble(json['x']),
      y: _asDouble(json['y']),
      width: _asDouble(json['width']),
      height: _asDouble(json['height']),
    );
  }

  /// Left edge.
  final double x;

  /// Top edge.
  final double y;

  /// Box width.
  final double width;

  /// Box height.
  final double height;

  /// Right edge (`x + width`).
  double get right => x + width;

  /// Bottom edge (`y + height`).
  double get bottom => y + height;

  /// The smallest box that contains every box in [boxes], or `null` when
  /// [boxes] is empty. Used to frame a set of cells (e.g. a cone-of-
  /// influence sub-graph) so the viewport can fit-to-cone.
  static BoundingBox? encompass(Iterable<BoundingBox> boxes) {
    var seen = false;
    var minX = 0.0;
    var minY = 0.0;
    var maxX = 0.0;
    var maxY = 0.0;
    for (final box in boxes) {
      if (!seen) {
        seen = true;
        minX = box.x;
        minY = box.y;
        maxX = box.right;
        maxY = box.bottom;
        continue;
      }
      if (box.x < minX) minX = box.x;
      if (box.y < minY) minY = box.y;
      if (box.right > maxX) maxX = box.right;
      if (box.bottom > maxY) maxY = box.bottom;
    }
    if (!seen) return null;
    return BoundingBox(
      x: minX,
      y: minY,
      width: maxX - minX,
      height: maxY - minY,
    );
  }

  /// Returns a copy with the given fields replaced.
  BoundingBox copyWith({double? x, double? y, double? width, double? height}) {
    return BoundingBox(
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
    );
  }

  /// Serializes to the JSON shape consumed by [BoundingBox.fromJson].
  Map<String, Object?> toJson() => <String, Object?>{
    'x': x,
    'y': y,
    'width': width,
    'height': height,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BoundingBox &&
          other.x == x &&
          other.y == y &&
          other.width == width &&
          other.height == height);

  @override
  int get hashCode => Object.hash(x, y, width, height);

  @override
  String toString() =>
      'BoundingBox(x: $x, y: $y, width: $width, height: $height)';
}

double _asDouble(Object? value) {
  if (value == null) return 0;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0;
  return 0;
}
