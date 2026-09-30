// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_settings/crux_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/app_settings.dart';
import 'package:netcrux/features/settings/providers/app_settings_provider.dart';
import 'package:netcrux/features/settings/screens/settings_screen.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/settings/netcrux_settings_codec.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Settings → General → "Automatically check for updates".
///
/// The toggle is the user-visible half of `autoUpdateCheckEnabledProvider`;
/// what matters is that it reflects the persisted value on open and that
/// flipping it writes through to `SharedPreferences` (so the *next* launch's
/// gated check honours it before defaults would say "on").
void main() {
  const switchKey = Key('settingsAutoCheckUpdatesSwitch');

  late SettingsService<AppSettings> service;
  late SharedPreferences prefs;

  Future<Widget> wrap({Locale locale = const Locale('en')}) async =>
      ProviderScope(
        overrides: [settingsServiceProvider.overrideWithValue(service)],
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: L10N.localizationsDelegates,
          supportedLocales: L10N.supportedLocales,
          home: const SettingsScreen(),
        ),
      );

  Future<void> openGeneral(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(await wrap());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
    service = SettingsService<AppSettings>(
      const NetcruxSettingsCodec(),
      prefsOverride: prefs,
    );
  });

  testWidgets('is on by default', (tester) async {
    await openGeneral(tester);

    final toggle = tester.widget<SwitchListTile>(find.byKey(switchKey));
    expect(toggle.value, isTrue);
  });

  testWidgets('reflects a persisted "off"', (tester) async {
    await service.save(
      const AppSettings.defaults().copyWith(autoCheckForUpdates: false),
    );
    await openGeneral(tester);

    final toggle = tester.widget<SwitchListTile>(find.byKey(switchKey));
    expect(toggle.value, isFalse);
  });

  testWidgets('flipping it writes through to storage', (tester) async {
    await openGeneral(tester);

    await tester.tap(find.byKey(switchKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      tester.widget<SwitchListTile>(find.byKey(switchKey)).value,
      isFalse,
    );
    expect((await service.load()).autoCheckForUpdates, isFalse);

    await tester.tap(find.byKey(switchKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect((await service.load()).autoCheckForUpdates, isTrue);
  });

  testWidgets('clears the 44 dp touch-target floor', (tester) async {
    await openGeneral(tester);
    expect(tester.getSize(find.byKey(switchKey)).height, greaterThan(44));
  });

  group('locale sweep', () {
    for (final locale in L10N.supportedLocales) {
      testWidgets('renders in ${locale.toLanguageTag()}', (tester) async {
        await tester.binding.setSurfaceSize(const Size(900, 700));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(await wrap(locale: locale));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.byKey(switchKey), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
