// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_settings/crux_settings.dart';
import 'package:crux_theme/crux_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/app_settings.dart';
import 'package:netcrux/features/settings/providers/app_settings_provider.dart';
import 'package:netcrux/netcrux_color_theme_bootstrap.dart';
import 'package:netcrux/services/settings/netcrux_settings_codec.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Builds a container whose persisted settings already carry
/// [activeThemeName], as an upgrading user's would.
Future<ProviderContainer> containerWithTheme(String? activeThemeName) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final service = SettingsService<AppSettings>(
    const NetcruxSettingsCodec(),
    prefsOverride: prefs,
  );
  if (activeThemeName != null) {
    await service.save(
      const AppSettings.defaults().copyWith(
        core: const CoreSettings.defaults().copyWith(
          activeThemeName: activeThemeName,
        ),
      ),
    );
  }
  final container = ProviderContainer(
    overrides: [
      settingsServiceProvider.overrideWithValue(service),
      netcruxCruxColorThemeOverride,
    ],
  );
  await container.read(appSettingsProvider.future);
  return container;
}

void main() {
  test('the seed preset resolves — the notifier constructs', () {
    // Guards the non-null assertion in the constructor: a preset id that
    // no longer exists in `builtinPresets()` throws at construction, which
    // would take the whole app down before the first frame.
    expect(builtinPresets()[cruxDarkPresetId], isNotNull);
    expect(NetcruxCruxColorThemeNotifier.new, returnsNormally);
  });

  test('a current preset id resolves to that preset', () async {
    final container = await containerWithTheme(cruxLightPresetId);
    addTearDown(container.dispose);
    expect(container.read(cruxColorThemeProvider).id, cruxLightPresetId);
  });

  group('legacy preset ids persisted before the presets were de-branded', () {
    // An existing beta user has `wavecrux-light` on disk. A raw
    // `builtinPresets()[name]` lookup misses and silently drops them back
    // to the dark seed; routing through `builtinPresetById` applies the
    // alias map so their chosen theme survives the upgrade.
    for (final (legacy, migrated) in const [
      ('wavecrux-dark', cruxDarkPresetId),
      ('wavecrux-light', cruxLightPresetId),
    ]) {
      test('$legacy migrates to $migrated', () async {
        final container = await containerWithTheme(legacy);
        addTearDown(container.dispose);
        expect(container.read(cruxColorThemeProvider).id, migrated);
      });
    }
  });

  test('an unrecognized preset id falls back to the seed', () async {
    final container = await containerWithTheme('no-such-preset');
    addTearDown(container.dispose);
    expect(container.read(cruxColorThemeProvider).id, cruxDarkPresetId);
  });

  test(
    'the empty-token high-contrast-dark preset activates without error',
    () async {
      // `high-contrast-dark`'s only tokens were WaveCrux canvas tokens,
      // which moved to a product-registered overlay, leaving the preset
      // empty for NetCrux. Selecting it must still be harmless: the theme
      // resolves, nothing throws, and the user simply sees NetCrux's
      // default chrome rather than a high-contrast one.
      final container = await containerWithTheme('high-contrast-dark');
      addTearDown(container.dispose);
      final theme = container.read(cruxColorThemeProvider);
      expect(theme.id, 'high-contrast-dark');
      expect(theme.tokens, isEmpty);
    },
  );
}
