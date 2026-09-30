// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:ui';

/// Built-in color schemes the Switching Activity Heatmap supports.
///
/// Each scheme maps a normalized [NetActivity.activityScore] in
/// `[0.0, 1.0]` to a [Color] via [colorForScore]. The interpolation
/// is deterministic — same score + same scheme always yields the
/// same color — so widget tests can assert RGB values without
/// goldens.
enum ActivityColorScheme {
  /// Cold → warm → hot. Blue at 0.0, yellow at 0.5, red at 1.0.
  /// The classic thermal-imaging palette familiar to engineers.
  heatmapRedBlue,

  /// Matplotlib viridis-inspired sequential map. Dark purple at 0.0,
  /// green at 0.5, bright yellow at 1.0. Perceptually uniform — the
  /// preferred scheme when the consumer cares about relative
  /// magnitude rather than the cold/hot metaphor.
  heatmapViridis,

  /// Light gray at 0.0, near-black at 1.0. Accessibility-first
  /// fallback (sufficient contrast for color-vision deficiencies)
  /// and the only scheme that prints / photocopies cleanly.
  heatmapGrayscale;

  /// Stable JSON tag.
  String toJsonString() => name;

  /// Parses a tag back to a value. Unknown maps to [heatmapRedBlue].
  static ActivityColorScheme fromJsonString(String raw) {
    for (final s in ActivityColorScheme.values) {
      if (s.name == raw) return s;
    }
    return ActivityColorScheme.heatmapRedBlue;
  }

  /// Returns the [Color] this scheme assigns to [normalizedScore],
  /// clamped to `[0.0, 1.0]`. Interpolation is linear between named
  /// control points per scheme.
  Color colorForScore(double normalizedScore) {
    final t = normalizedScore.clamp(0.0, 1.0);
    switch (this) {
      case ActivityColorScheme.heatmapRedBlue:
        return _interpolateRedBlue(t);
      case ActivityColorScheme.heatmapViridis:
        return _interpolateViridis(t);
      case ActivityColorScheme.heatmapGrayscale:
        return _interpolateGrayscale(t);
    }
  }

  Color _interpolateRedBlue(double t) {
    // 0.0 → blue (#2D58D8), 0.5 → yellow (#F2C94C), 1.0 → red (#E74C3C).
    if (t <= 0.5) {
      return _lerp(
        const Color(0xFF2D58D8),
        const Color(0xFFF2C94C),
        t * 2,
      );
    }
    return _lerp(
      const Color(0xFFF2C94C),
      const Color(0xFFE74C3C),
      (t - 0.5) * 2,
    );
  }

  Color _interpolateViridis(double t) {
    // 0.0 → dark purple (#440154), 0.5 → green (#1FA187),
    // 1.0 → bright yellow (#FDE725). Three-stop linear approximation
    // of matplotlib viridis — perceptually uniform enough for our
    // visual purposes without bundling a 256-entry LUT.
    if (t <= 0.5) {
      return _lerp(
        const Color(0xFF440154),
        const Color(0xFF1FA187),
        t * 2,
      );
    }
    return _lerp(
      const Color(0xFF1FA187),
      const Color(0xFFFDE725),
      (t - 0.5) * 2,
    );
  }

  Color _interpolateGrayscale(double t) {
    // 0.0 → light gray (#E0E0E0), 1.0 → near-black (#1C1C1C).
    return _lerp(const Color(0xFFE0E0E0), const Color(0xFF1C1C1C), t);
  }

  Color _lerp(Color a, Color b, double t) {
    int blend(int x, int y) => (x + (y - x) * t).round();
    return Color.fromARGB(
      255,
      blend((a.toARGB32() >> 16) & 0xFF, (b.toARGB32() >> 16) & 0xFF),
      blend((a.toARGB32() >> 8) & 0xFF, (b.toARGB32() >> 8) & 0xFF),
      blend(a.toARGB32() & 0xFF, b.toARGB32() & 0xFF),
    );
  }
}
