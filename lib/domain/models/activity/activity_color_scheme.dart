// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:ui';

import 'package:netcrux/domain/models/activity/net_activity.dart';

/// Built-in color schemes the Switching Activity Heatmap supports.
///
/// Each scheme maps a normalized [NetActivity.activityScore] in
/// `[0.0, 1.0]` to a [Color] via [colorForScore]. The interpolation
/// is deterministic (same score, scheme and brightness always yield the
/// same color), so tests can assert RGB values without goldens.
///
/// **Every color is drawn as a wire on the schematic canvas,** over the
/// canvas background and beside uncolored wires. So each scheme has one
/// ramp per canvas [Brightness], and every color on a ramp, the coldest
/// included, stays at least 3:1 (WCAG 2.1 SC 1.4.11, graphical objects)
/// against the background of every built-in theme of that brightness. The
/// coldest color is also kept at least 2:1 in luminance, and a clear hue
/// step, away from the theme's uncolored wire, so a quiet net never reads
/// as an uncolored one.
///
/// Clock nets are not on any ramp: they paint in [clockColor], see
/// [colorForNet].
enum ActivityColorScheme {
  /// Cold to hot: blue, cyan, yellow, red. The thermal-imaging palette
  /// familiar to engineers. On a light canvas the warm stops darken to
  /// teal, amber and brick red so they stay readable on white.
  heatmapRedBlue,

  /// Viridis-inspired sequential map: violet, green, yellow (olive on a
  /// light canvas). The preferred scheme when the consumer cares about
  /// relative magnitude rather than the cold/hot metaphor. The violet
  /// cold end is lighter than matplotlib's near-black so it does not
  /// vanish into a dark canvas.
  heatmapViridis,

  /// Mid gray to the canvas' highest-contrast end: white on a dark canvas,
  /// black on a light one. The accessibility-first fallback (no hue
  /// needed to read it) and the only scheme that prints cleanly.
  heatmapGrayscale;

  /// The one color every clock net paints, in every scheme and on every
  /// theme. A magenta no scheme ramp comes near, readable on dark and
  /// light canvases alike (at least 3:1 on every built-in theme).
  ///
  /// Clocks are drawn apart because a clock is nearly always the busiest
  /// net by far: scaled with the rest, it takes the hot end and pushes
  /// every data net into the cold end.
  static const Color clockColor = Color(0xFFE040FB);

  /// Opacity of a wire the activity coloring has no color for (a net the
  /// waveform does not carry, such as a wire synthesis created) while the
  /// coloring is shown. Such a wire keeps its uncolored hue but recedes, so
  /// no colored wire, a gray of [heatmapGrayscale] included, can be taken
  /// for it.
  static const double uncoloredWireOpacity = 0.25;

  /// The color a wire with no activity color paints while the coloring is
  /// shown: the theme's uncolored [wireColor] at [uncoloredWireOpacity].
  static Color uncoloredWire(Color wireColor) =>
      wireColor.withValues(alpha: uncoloredWireOpacity);

  /// Stable JSON tag.
  String toJsonString() => name;

  /// Parses a tag back to a value. Unknown maps to [heatmapRedBlue].
  static ActivityColorScheme fromJsonString(String raw) {
    for (final s in ActivityColorScheme.values) {
      if (s.name == raw) return s;
    }
    return ActivityColorScheme.heatmapRedBlue;
  }

  /// The ramp's control points for a canvas of [brightness], cold first.
  /// Evenly spaced over `[0.0, 1.0]`; [colorForScore] interpolates
  /// linearly between neighbours. A legend draws the same list as a
  /// gradient.
  List<Color> stops(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    switch (this) {
      case ActivityColorScheme.heatmapRedBlue:
        return dark ? _redBlueDark : _redBlueLight;
      case ActivityColorScheme.heatmapViridis:
        return dark ? _viridisDark : _viridisLight;
      case ActivityColorScheme.heatmapGrayscale:
        return dark ? _grayscaleDark : _grayscaleLight;
    }
  }

  /// Returns the [Color] this scheme assigns to [normalizedScore],
  /// clamped to `[0.0, 1.0]`, on a canvas of [brightness].
  Color colorForScore(double normalizedScore, Brightness brightness) {
    final t = normalizedScore.clamp(0.0, 1.0);
    final points = stops(brightness);
    final segments = points.length - 1;
    final scaled = t * segments;
    final i = scaled.floor().clamp(0, segments - 1);
    return _lerp(points[i], points[i + 1], scaled - i);
  }

  /// The color [net]'s wires paint: [clockColor] for a clock, otherwise
  /// its score on this scheme's ramp. The schematic and the heatmap list
  /// both color through this, so the two always agree.
  Color colorForNet(NetActivity net, Brightness brightness) =>
      net.isClock ? clockColor : colorForScore(net.activityScore, brightness);

  static Color _lerp(Color a, Color b, double t) {
    int blend(int x, int y) => (x + (y - x) * t).round();
    return Color.fromARGB(
      255,
      blend((a.toARGB32() >> 16) & 0xFF, (b.toARGB32() >> 16) & 0xFF),
      blend((a.toARGB32() >> 8) & 0xFF, (b.toARGB32() >> 8) & 0xFF),
      blend(a.toARGB32() & 0xFF, b.toARGB32() & 0xFF),
    );
  }
}

const List<Color> _redBlueDark = <Color>[
  Color(0xFF4C7BFF),
  Color(0xFF2EC4D6),
  Color(0xFFF2C94C),
  Color(0xFFE74C3C),
];

const List<Color> _redBlueLight = <Color>[
  Color(0xFF3D6BF0),
  Color(0xFF00838F),
  Color(0xFFB26A00),
  Color(0xFFC62828),
];

const List<Color> _viridisDark = <Color>[
  Color(0xFF8A6BE8),
  Color(0xFF1FA187),
  Color(0xFFFDE725),
];

const List<Color> _viridisLight = <Color>[
  Color(0xFF8A6BE8),
  Color(0xFF1E8A74),
  Color(0xFF5F7A00),
];

const List<Color> _grayscaleDark = <Color>[
  Color(0xFF7C7C7C),
  Color(0xFFFFFFFF),
];

const List<Color> _grayscaleLight = <Color>[
  Color(0xFF8A8A8A),
  Color(0xFF000000),
];
