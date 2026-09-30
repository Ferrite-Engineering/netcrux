// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// Which face of a custom cell symbol a [PortAnchor] sits on. The
/// renderer uses this to decide which direction a pin stub points
/// when wiring the anchor to the surrounding net edges.
enum PortAnchorSide {
  /// Top edge.
  top,

  /// Right edge.
  right,

  /// Bottom edge.
  bottom,

  /// Left edge.
  left,
}

/// Position of a single named port on a [CustomCellSymbol]'s
/// declared canvas. Coordinates are normalized 0.0–1.0 so the symbol
/// scales-to-fit at any rendered size without the anchors drifting.
///
/// `(0, 0)` is the top-left of the symbol's declared canvas, `(1, 1)`
/// is the bottom-right. The renderer multiplies by the actual cell
/// bounds to land the anchor in pixel space.
///
/// The [side] field disambiguates the connector direction so a pin
/// anchored at `(0.5, 1.0)` on the bottom edge points downward, not
/// sideways. The [labelOffset] is the pixel offset (relative to the
/// rendered anchor center) where the port name should appear; the
/// renderer applies this in addition to its standard label layout
/// rules.
@immutable
class PortAnchor {
  /// Creates a port anchor.
  const PortAnchor({
    required this.x,
    required this.y,
    required this.side,
    this.labelOffsetDx = 0,
    this.labelOffsetDy = 0,
  });

  /// Round-trips a [PortAnchor] from its JSON shape. Missing or
  /// malformed numeric fields fall back to `0.0`; missing or
  /// unrecognized side falls back to [PortAnchorSide.left].
  factory PortAnchor.fromJson(Map<String, Object?> json) {
    return PortAnchor(
      x: (json['x'] as num?)?.toDouble() ?? 0,
      y: (json['y'] as num?)?.toDouble() ?? 0,
      side: PortAnchorSide.values.firstWhere(
        (s) => s.name == json['side'],
        orElse: () => PortAnchorSide.left,
      ),
      labelOffsetDx: (json['labelOffsetDx'] as num?)?.toDouble() ?? 0,
      labelOffsetDy: (json['labelOffsetDy'] as num?)?.toDouble() ?? 0,
    );
  }

  /// Horizontal position, normalized 0.0–1.0 within the symbol's
  /// declared canvas.
  final double x;

  /// Vertical position, normalized 0.0–1.0 within the symbol's
  /// declared canvas.
  final double y;

  /// Which edge of the symbol the connector approaches the anchor
  /// from. Drives the renderer's pin-stub direction.
  final PortAnchorSide side;

  /// Horizontal offset (in pixels) applied to the rendered port label
  /// relative to the anchor center. Authors use this to nudge labels
  /// out of busy regions of the artwork.
  final double labelOffsetDx;

  /// Vertical offset (in pixels) applied to the rendered port label.
  final double labelOffsetDy;

  /// Returns a copy with the given fields overridden.
  PortAnchor copyWith({
    double? x,
    double? y,
    PortAnchorSide? side,
    double? labelOffsetDx,
    double? labelOffsetDy,
  }) {
    return PortAnchor(
      x: x ?? this.x,
      y: y ?? this.y,
      side: side ?? this.side,
      labelOffsetDx: labelOffsetDx ?? this.labelOffsetDx,
      labelOffsetDy: labelOffsetDy ?? this.labelOffsetDy,
    );
  }

  /// Serializes this anchor into its JSON shape.
  Map<String, Object?> toJson() => <String, Object?>{
    'x': x,
    'y': y,
    'side': side.name,
    if (labelOffsetDx != 0) 'labelOffsetDx': labelOffsetDx,
    if (labelOffsetDy != 0) 'labelOffsetDy': labelOffsetDy,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PortAnchor &&
          other.x == x &&
          other.y == y &&
          other.side == side &&
          other.labelOffsetDx == labelOffsetDx &&
          other.labelOffsetDy == labelOffsetDy);

  @override
  int get hashCode => Object.hash(x, y, side, labelOffsetDx, labelOffsetDy);

  @override
  String toString() =>
      'PortAnchor(($x, $y) on ${side.name}, labelOffset=($labelOffsetDx,'
      ' $labelOffsetDy))';
}
