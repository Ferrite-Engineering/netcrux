// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/theme/theme_switch_test.dart
//
// Verification driver for Open-Core Guide §8.1 (Preset switching repaints
// every surface). Switching the active theme preset must flip the live
// `MaterialApp.themeMode` so the whole chrome repaints light/dark. Drives the
// real `appSettingsProvider` → `cruxColorThemeProvider` bridge end-to-end.

import 'package:crux_theme/crux_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:netcrux/features/settings/providers/app_settings_provider.dart';

import '../helpers/app_driver.dart';

ThemeMode _liveThemeMode(WidgetTester tester) {
  final app = tester.widget<MaterialApp>(find.byType(MaterialApp).first);
  return app.themeMode ?? ThemeMode.system;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets(
    'switching presets flips MaterialApp brightness (Guide §8.1)',
    (tester) async {
      await bootNetcrux(tester);
      final root = rootContainer(tester);
      final settings = root.read(appSettingsProvider.notifier);

      // Default preset is dark.
      await settings.setActiveThemeName(cruxDarkPresetId);
      await pumpUntil(tester, () => _liveThemeMode(tester) == ThemeMode.dark);
      expect(_liveThemeMode(tester), ThemeMode.dark);

      // Switch to a light preset — the chrome flips to light immediately.
      await settings.setActiveThemeName(cruxLightPresetId);
      await pumpUntil(tester, () => _liveThemeMode(tester) == ThemeMode.light);
      expect(
        _liveThemeMode(tester),
        ThemeMode.light,
        reason: 'the crux-light preset drives MaterialApp.themeMode light',
      );

      // Switch back to dark — flips back.
      await settings.setActiveThemeName('solarized-dark');
      await pumpUntil(tester, () => _liveThemeMode(tester) == ThemeMode.dark);
      expect(_liveThemeMode(tester), ThemeMode.dark);

      expect(tester.takeException(), isNull);
    },
  );
}
