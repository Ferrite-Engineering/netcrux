// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:netcrux/core/theme/netcrux_colors.dart';

/// Builders for the NetCrux Material 3 themes.
///
/// Both light and dark themes are derived from a single brand seed
/// ([NetcruxColors.brandSeed], a muted amber). Dark is the default —
/// engineers stare at schematics for hours, and dark chrome is the
/// engineering-tool convention.
///
/// Each brightness also has a high-contrast variant, wired into
/// [MaterialApp.highContrastTheme] / [MaterialApp.highContrastDarkTheme] so
/// that when the OS reports the "increase contrast" accessibility setting the
/// chrome hardens: fully-opaque, maximum-visibility outline colors replace the
/// seed-derived low-contrast borders. Mirrors WaveCrux's `WavecruxTheme`.
abstract final class NetcruxTheme {
  /// Light Material 3 theme.
  static ThemeData light() => _build(Brightness.light);

  /// Dark Material 3 theme — the NetCrux default.
  static ThemeData dark() => _build(Brightness.dark);

  /// High-contrast light theme — used when the platform reports the
  /// high-contrast accessibility setting is active.
  static ThemeData highContrastLight() =>
      _build(Brightness.light, highContrast: true);

  /// High-contrast dark theme — used when the platform reports the
  /// high-contrast accessibility setting is active.
  static ThemeData highContrastDark() =>
      _build(Brightness.dark, highContrast: true);

  static ThemeData _build(Brightness brightness, {bool highContrast = false}) {
    final isDark = brightness == Brightness.dark;
    var colorScheme = ColorScheme.fromSeed(
      seedColor: NetcruxColors.brandSeed,
      brightness: brightness,
    );
    if (highContrast) {
      // Fully-opaque, high-visibility borders. White-on-dark / black-on-light
      // for the primary outline; a strong grey for the subtler variant.
      colorScheme = colorScheme.copyWith(
        outline: isDark ? const Color(0xFFFFFFFF) : const Color(0xFF000000),
        outlineVariant: isDark
            ? const Color(0xFFCCCCCC)
            : const Color(0xFF333333),
      );
    }
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: isDark
          ? NetcruxColors.darkCanvasBackground
          : NetcruxColors.lightCanvasBackground,
      visualDensity: VisualDensity.adaptivePlatformDensity,
    );
  }
}
