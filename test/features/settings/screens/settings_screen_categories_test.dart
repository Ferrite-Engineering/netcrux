// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_settings/crux_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/enums/yosys_path_mode.dart';
import 'package:netcrux/domain/models/app_settings.dart';
import 'package:netcrux/features/settings/providers/app_settings_provider.dart';
import 'package:netcrux/features/settings/screens/settings_screen.dart';
import 'package:netcrux/features/settings/widgets/color_theme_section.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/settings/netcrux_settings_codec.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Drives each Settings category's tiles through the real screen, so the
/// settings-write path (segmented buttons, switches, text fields →
/// `appSettingsProvider` → `SettingsService`) is exercised rather than
/// only the shell layout.
Future<ProviderContainer> _pump(
  WidgetTester tester, {
  Locale locale = const Locale('en'),
}) async {
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      settingsServiceProvider.overrideWithValue(
        SettingsService<AppSettings>(
          const NetcruxSettingsCodec(),
          prefsOverride: prefs,
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: const SettingsScreen(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return container;
}

/// Selects a rail category by its localized title. The wide layout renders
/// the rail and the detail pane side by side, so the title appears twice
/// once selected; tapping the first (rail) occurrence is what the user does.
Future<void> _openCategory(WidgetTester tester, String title) async {
  await tester.tap(find.text(title).first);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

AppSettings _settings(ProviderContainer c) =>
    c.read(appSettingsProvider).value ?? const AppSettings.defaults();

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  Future<L10N> l10nFor(Locale locale) => L10N.delegate.load(locale);

  testWidgets('General → auto-reload mode writes the setting', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = await _pump(tester);
    final l10n = await l10nFor(const Locale('en'));

    await _openCategory(tester, l10n.settingsGeneralSection);
    expect(find.text(l10n.settingsAutoReloadLabel), findsOneWidget);

    await tester.tap(find.text(l10n.settingsAutoReloadOff));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(_settings(container).core.autoReloadMode, AutoReloadMode.off);

    await tester.tap(find.text(l10n.settingsAutoReloadPrompt));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(_settings(container).core.autoReloadMode, AutoReloadMode.prompt);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Appearance shows only the color-preset picker (no theme-mode '
      'selector)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pump(tester);
    final l10n = await l10nFor(const Locale('en'));

    await _openCategory(tester, l10n.settingsAppearanceSection);
    // There is no System/Light/Dark selector — brightness follows the
    // active color preset (WaveCrux model).
    //
    // Literal English rather than an l10n getter: the four
    // `settingsThemeMode*` keys were deleted on 2026-08-17 with the rest of
    // the dead-key sweep, and this assertion was the only thing keeping
    // `settingsThemeModeLabel` alive — a key referenced solely by a test
    // asserting it never renders. The strings are what the removed selector
    // said, which is exactly what this guard needs to keep out.
    for (final removed in const ['Theme', 'System', 'Light', 'Dark']) {
      expect(find.text(removed), findsNothing, reason: '$removed resurfaced');
    }
    expect(find.byType(ColorThemeSection), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Engines → path mode reveals the custom-path field only in '
      'custom mode', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = await _pump(tester);
    final l10n = await l10nFor(const Locale('en'));

    await _openCategory(tester, l10n.settingsEnginesSection);
    expect(find.text(l10n.settingsYosysPathLabel), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.text(l10n.yosysPathModeCustom));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(_settings(container).yosysPathMode, YosysPathMode.custom);
    expect(find.byType(TextField), findsOneWidget);

    await tester.tap(find.text(l10n.yosysPathModeBundled));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(_settings(container).yosysPathMode, YosysPathMode.bundled);
    expect(find.byType(TextField), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // The custom path is probed by running it, so the probe waits for typing
  // to pause. None of these steps lets it fire: a probe that did would run a
  // subprocess, and one left pending would fail the harness, which rejects a
  // test that ends with a timer still scheduled.
  testWidgets('Engines → a custom path probe waits for typing to pause, and '
      'is cancelled when the path is cleared or the field goes away', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pump(tester);
    final l10n = await l10nFor(const Locale('en'));

    await _openCategory(tester, l10n.settingsEnginesSection);
    await tester.tap(find.text(l10n.yosysPathModeCustom));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.enterText(find.byType(TextField), '/no/such/yosys');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(l10n.yosysCustomPathProbing), findsOneWidget);

    await tester.enterText(find.byType(TextField), '');
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text(l10n.yosysCustomPathProbing), findsNothing);

    // Leaving custom mode inside the 400 ms window and ending the test there:
    // a probe the tile did not cancel as it went is still scheduled, and the
    // harness fails on it.
    await tester.enterText(find.byType(TextField), '/no/such/yosys');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text(l10n.yosysPathModeBundled));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(TextField), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('CXP Cross-Probe → server toggle writes the setting', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = await _pump(tester);
    final l10n = await l10nFor(const Locale('en'));

    await _openCategory(tester, l10n.settingsCxpSectionTitle);
    final before = _settings(container).cxpServerEnabled;

    await tester.tap(find.byType(Switch).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(_settings(container).cxpServerEnabled, !before);
    expect(tester.takeException(), isNull);
  });

  testWidgets('CXP Cross-Probe → port field commits (editor field moved to '
      'Editors)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = await _pump(tester);
    final l10n = await l10nFor(const Locale('en'));

    await _openCategory(tester, l10n.settingsCxpSectionTitle);
    final fields = find.byType(TextField);
    // The editor-command field lives in the dedicated Editors section, so
    // CXP holds only the port field.
    expect(fields, findsOneWidget);

    await tester.enterText(fields.first, '54999');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(_settings(container).cxpServerPort, 54999);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Editors → editor-command field commits', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = await _pump(tester);
    final l10n = await l10nFor(const Locale('en'));

    await _openCategory(tester, l10n.settingsEditorsSection);
    final fields = find.byType(TextField);
    expect(fields, findsOneWidget);

    await tester.enterText(fields.first, 'code -g {file}:{line}');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(_settings(container).cxpEditorCommand, 'code -g {file}:{line}');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Shortcuts category renders its section', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pump(tester);
    final l10n = await l10nFor(const Locale('en'));

    await _openCategory(tester, l10n.settingsShortcutsSection);
    await tester.pump(const Duration(milliseconds: 50));

    expect(tester.takeException(), isNull);
  });

  group('locale sweep over every category', () {
    for (final locale in L10N.supportedLocales) {
      testWidgets('every category opens in ${locale.toLanguageTag()}', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(1000, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await _pump(tester, locale: locale);
        final l10n = await l10nFor(locale);

        for (final title in <String>[
          l10n.settingsGeneralSection,
          l10n.settingsAppearanceSection,
          l10n.settingsEnginesSection,
          l10n.settingsEditorsSection,
          l10n.settingsCxpSectionTitle,
          l10n.settingsShortcutsSection,
        ]) {
          await _openCategory(tester, title);
          expect(
            tester.takeException(),
            isNull,
            reason: '$title must render in $locale',
          );
        }
      });
    }
  });
}
