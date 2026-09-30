// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';

import 'package:crux_settings/crux_settings.dart';
import 'package:crux_theme/crux_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/app_settings.dart';
import 'package:netcrux/features/settings/providers/app_settings_provider.dart';
import 'package:netcrux/features/settings/widgets/color_theme_section.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/settings/netcrux_settings_codec.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pumps the section with the pack directory injected so `path_provider`
/// and the desktop file picker stay out of the widget tree.
Future<void> _pump(
  WidgetTester tester, {
  required PackDirectoryResolver resolver,
  Locale locale = const Locale('en'),
}) async {
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        settingsServiceProvider.overrideWithValue(
          SettingsService<AppSettings>(
            const NetcruxSettingsCodec(),
            prefsOverride: prefs,
          ),
        ),
      ],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: ColorThemeSection(
              packDirectoryResolver: resolver,
              pickPackDocument: () async => null,
              savePackDocument: (_) async => null,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  late Directory packDir;

  setUp(() {
    packDir = Directory.systemTemp.createTempSync('nc_theme_packs_');
  });
  tearDown(() {
    if (packDir.existsSync()) packDir.deleteSync(recursive: true);
  });

  testWidgets('renders a placeholder until the pack directory resolves', (
    tester,
  ) async {
    final gate = Completer<Directory>();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: L10N.localizationsDelegates,
          supportedLocales: L10N.supportedLocales,
          home: Scaffold(
            body: ColorThemeSection(packDirectoryResolver: () => gate.future),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(PresetPicker), findsNothing);
    expect(find.byType(SizedBox), findsWidgets);

    gate.complete(packDir);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(PresetPicker), findsOneWidget);
  });

  testWidgets('renders the preset, token, and pack subsections', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pump(tester, resolver: () async => packDir);

    const strings = ThemeAppearanceStringsEn();
    expect(find.text(strings.presetSectionHeading), findsOneWidget);
    expect(find.text(strings.tokenOverridesSectionHeading), findsOneWidget);
    expect(find.text(strings.themePackBrowserSectionHeading), findsOneWidget);

    expect(find.byType(PresetPicker), findsOneWidget);
    expect(find.byType(ThemePackBrowser), findsOneWidget);
    expect(
      find.byType(TokenCategorySection),
      findsNWidgets(ThemeRegistry.instance.registeredCategories.length),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failing resolver falls back to the system temp directory', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pump(
      tester,
      resolver: () async => throw const FileSystemException('no app support'),
    );

    // The section still renders — the fallback keeps Settings usable when
    // the platform support directory is unavailable.
    expect(find.byType(ThemePackBrowser), findsOneWidget);
    final browser = tester.widget<ThemePackBrowser>(
      find.byType(ThemePackBrowser),
    );
    final store = browser.store;
    expect(store, isA<DirectoryThemePackStore>());
    expect(
      (store as DirectoryThemePackStore).directory.path,
      Directory.systemTemp.path,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('an injected store is used verbatim and renders without IO', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // The store seam is what makes the browser renderable without a
    // filesystem — and therefore on web. Injecting an in-memory store
    // also means no resolver runs, so the section paints on the first
    // frame instead of after a pending directory future.
    final store = InMemoryThemePackStore();
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsServiceProvider.overrideWithValue(
            SettingsService<AppSettings>(
              const NetcruxSettingsCodec(),
              prefsOverride: prefs,
            ),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: L10N.localizationsDelegates,
          supportedLocales: L10N.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(child: ColorThemeSection(store: store)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final browser = tester.widget<ThemePackBrowser>(
      find.byType(ThemePackBrowser),
    );
    expect(identical(browser.store, store), isTrue);
    expect(find.byType(PresetPicker), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('locale sweep', () {
    for (final locale in L10N.supportedLocales) {
      testWidgets('pumps cleanly in ${locale.toLanguageTag()}', (tester) async {
        await tester.binding.setSurfaceSize(const Size(900, 2000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await _pump(tester, resolver: () async => packDir, locale: locale);
        expect(find.byType(PresetPicker), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'locale $locale');
      });
    }
  });
}
