// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Colour-distance measures for tests that assert a colour can be told apart
// from another: WCAG 2.1 contrast for "readable against", CIELAB distance for
// "a different colour".

import 'dart:math' as math;
import 'dart:ui';

import 'package:crux_theme/crux_theme.dart';
import 'package:flutter/material.dart' show ThemeExtension;
import 'package:netcrux/core/theme/netcrux_theme.dart';

/// WCAG 2.1 relative luminance (SC 1.4.3 definitions).
double relativeLuminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

/// WCAG 2.1 contrast ratio between [a] and [b], from 1 to 21.
double contrastRatio(Color a, Color b) {
  final la = relativeLuminance(a);
  final lb = relativeLuminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// CIE76 colour difference in CIELAB (D65). About 2.3 is the smallest
/// difference a viewer notices side by side; colours a viewer is asked to
/// name apart on a busy canvas want several times that.
double deltaE(Color a, Color b) {
  final la = _lab(a);
  final lb = _lab(b);
  return math.sqrt(
    math.pow(la.$1 - lb.$1, 2) +
        math.pow(la.$2 - lb.$2, 2) +
        math.pow(la.$3 - lb.$3, 2),
  );
}

(double, double, double) _lab(Color c) {
  double lin(double v) =>
      v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  final r = lin(c.r);
  final g = lin(c.g);
  final b = lin(c.b);
  final x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047;
  final y = 0.2126 * r + 0.7152 * g + 0.0722 * b;
  final z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883;
  double f(double t) =>
      t > 0.008856 ? math.pow(t, 1 / 3).toDouble() : 7.787 * t + 16 / 116;
  return (116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z)));
}

/// The colours the schematic canvas paints with under one built-in preset.
typedef CanvasColors = ({
  String presetId,
  Brightness brightness,
  Color background,
  Color defaultWire,
});

/// The canvas background and the default wire colour of every built-in
/// preset, built the way the app builds its theme: the NetCrux Material theme
/// of the preset's brightness with the preset's chrome tokens applied. The
/// schematic painter fills with `colorScheme.surface` and strokes an
/// uncoloured wire with `colorScheme.onSurfaceVariant`.
List<CanvasColors> canvasColorsOfEveryPreset() => <CanvasColors>[
  for (final preset in builtinPresets().values) _canvasColors(preset),
];

CanvasColors _canvasColors(CruxColorTheme preset) {
  final ext = CruxThemeExtension(theme: preset);
  final base = preset.brightness == Brightness.light
      ? NetcruxTheme.light()
      : NetcruxTheme.dark();
  final theme = applyChromeTokens(
    base.copyWith(extensions: <ThemeExtension<dynamic>>[ext]),
    ext,
  );
  return (
    presetId: preset.id,
    brightness: preset.brightness,
    background: theme.colorScheme.surface,
    defaultWire: theme.colorScheme.onSurfaceVariant,
  );
}
