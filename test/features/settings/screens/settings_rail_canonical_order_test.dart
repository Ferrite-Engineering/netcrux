// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Guards the Settings rail's category order against
// `CruxSettingsCategoryId.canonicalOrder` (crux_settings_ui), the rail order
// every product in the suite follows so that the four Settings dialogs read
// the same. `canonicalOrder`'s own doc comment says "Order is asserted by
// each product's settings conformance test"; this is NetCrux's. Without it
// the order is correct only because `SettingsScreen._categories()` lists
// the ids in that order, and an edit that swapped two categories or
// inserted one in the wrong slot would pass every other test.
//
// Reads the actual ids `SettingsScreen` hands to `CruxSettingsMasterDetail`
// — the real widget tree, not a copy of the source list — via the public
// `categories` field on the mounted `CruxSettingsMasterDetail`. NetCrux
// implements only a subset of the canonical ids (general, appearance,
// privacy, productDefaults, editors, cxp, shortcuts); ids it does not
// implement are simply absent, which is why this asserts a subsequence
// rather than exact equality.

import 'package:crux_settings/crux_settings.dart';
import 'package:crux_settings_ui/crux_settings_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/app_settings.dart';
import 'package:netcrux/features/settings/providers/app_settings_provider.dart';
import 'package:netcrux/features/settings/screens/settings_screen.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/settings/netcrux_settings_codec.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  // Swept over every shipped locale: the ids are identity, not display text,
  // so the rail order must not change with the language — a category whose
  // placement depended on a localized string would pass in English alone.
  for (final locale in L10N.supportedLocales) {
    testWidgets(
      'SettingsScreen category ids are a subsequence of '
      'CruxSettingsCategoryId.canonicalOrder in ${locale.toLanguageTag()}',
      (tester) => _expectCanonicalRailOrder(tester, locale),
    );
  }
}

Future<void> _expectCanonicalRailOrder(
  WidgetTester tester,
  Locale locale,
) async {
  await tester.binding.setSurfaceSize(const Size(1000, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));

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

  final masterDetail = tester.widget<CruxSettingsMasterDetail>(
    find.byType(CruxSettingsMasterDetail),
  );
  final ids = masterDetail.categories.map((c) => c.id).toList();

  // Fails loudly rather than vacuously: a change that made the screen
  // render zero categories (a broken provider override, a widget-tree
  // change that stopped mounting CruxSettingsMasterDetail) must not
  // pass this guard by having nothing left to check.
  expect(
    ids,
    isNotEmpty,
    reason:
        'SettingsScreen rendered no categories — either the widget '
        'tree changed shape or CruxSettingsMasterDetail was not found',
  );

  var cursor = -1;
  for (final id in ids) {
    final index = CruxSettingsCategoryId.canonicalOrder.indexOf(id);
    expect(
      index,
      greaterThanOrEqualTo(0),
      reason: '"$id" is not in CruxSettingsCategoryId.canonicalOrder',
    );
    expect(
      index,
      greaterThan(cursor),
      reason:
          '"$id" (canonical index $index) renders out of order — the '
          'previous category sits at canonical index $cursor. The rail '
          "must render ids in canonicalOrder's relative order.",
    );
    cursor = index;
  }
}
