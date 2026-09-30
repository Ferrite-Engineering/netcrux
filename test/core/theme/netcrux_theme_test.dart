// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/theme/netcrux_colors.dart';
import 'package:netcrux/core/theme/netcrux_theme.dart';

void main() {
  group('NetcruxTheme', () {
    test('dark theme is Material 3 with dark brightness', () {
      final theme = NetcruxTheme.dark();
      expect(theme.useMaterial3, isTrue);
      expect(theme.brightness, Brightness.dark);
      expect(theme.scaffoldBackgroundColor, NetcruxColors.darkCanvasBackground);
    });

    test('light theme is Material 3 with light brightness', () {
      final theme = NetcruxTheme.light();
      expect(theme.useMaterial3, isTrue);
      expect(theme.brightness, Brightness.light);
      expect(
        theme.scaffoldBackgroundColor,
        NetcruxColors.lightCanvasBackground,
      );
    });

    test('high-contrast dark hardens the outline and stays dark', () {
      final base = NetcruxTheme.dark();
      final hc = NetcruxTheme.highContrastDark();
      expect(hc.brightness, Brightness.dark);
      expect(hc.useMaterial3, isTrue);
      // Hardened outline is fully-opaque white and differs from the
      // seed-derived low-contrast border.
      expect(hc.colorScheme.outline, const Color(0xFFFFFFFF));
      expect(hc.colorScheme.outline, isNot(base.colorScheme.outline));
    });

    test('high-contrast light hardens the outline and stays light', () {
      final base = NetcruxTheme.light();
      final hc = NetcruxTheme.highContrastLight();
      expect(hc.brightness, Brightness.light);
      expect(hc.useMaterial3, isTrue);
      // Hardened outline is fully-opaque black and differs from the
      // seed-derived low-contrast border.
      expect(hc.colorScheme.outline, const Color(0xFF000000));
      expect(hc.colorScheme.outline, isNot(base.colorScheme.outline));
    });

    test('both themes derive from the brand seed color', () {
      // Both themes are built from `ColorScheme.fromSeed(seedColor: brandSeed)`,
      // so the resulting primary colors should be deterministic and
      // non-default. We assert the primary is *not* Flutter's M2/M3 default
      // (Color(0xFF6750A4) is the default M3 primary when no seed is given).
      const flutterDefaultM3Primary = Color(0xFF6750A4);
      expect(
        NetcruxTheme.dark().colorScheme.primary,
        isNot(flutterDefaultM3Primary),
      );
      expect(
        NetcruxTheme.light().colorScheme.primary,
        isNot(flutterDefaultM3Primary),
      );
    });
  });

  group('NetcruxColors', () {
    test('brandSeed is the documented muted amber', () {
      expect(NetcruxColors.brandSeed, const Color(0xFFD4A017));
    });
  });
}
