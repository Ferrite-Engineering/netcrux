// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/shared/widgets/netcrux_feature_tier_badge.dart';

void main() {
  Future<void> pumpBadge(
    WidgetTester tester,
    LicenseTier tier, {
    Locale locale = const Locale('en'),
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: const [
          L10N.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: L10N.supportedLocales,
        home: Scaffold(body: NetCruxFeatureTierBadge(requiredTier: tier)),
      ),
    );
  }

  group('NetCruxFeatureTierBadge', () {
    testWidgets('openCore renders nothing (SizedBox.shrink)', (tester) async {
      await pumpBadge(tester, LicenseTier.openCore);
      expect(find.text('PRO'), findsNothing);
      expect(find.text('ENT'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('edu renders nothing (FeatureTierBadge collapses for EDU)', (
      tester,
    ) async {
      await pumpBadge(tester, LicenseTier.edu);
      expect(find.text('EDU'), findsNothing);
      expect(find.text('PRO'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('pro renders the localized PRO chip in English', (
      tester,
    ) async {
      await pumpBadge(tester, LicenseTier.pro);
      expect(find.text('PRO'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('enterprise renders the localized ENT chip in English', (
      tester,
    ) async {
      await pumpBadge(tester, LicenseTier.enterprise);
      expect(find.text('ENT'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    for (final locale in const [
      Locale('en'),
      Locale('zh', 'CN'),
      Locale('zh'),
      Locale('ja'),
      Locale('ko'),
    ]) {
      testWidgets('locale sweep ${locale.toLanguageTag()} pumps cleanly', (
        tester,
      ) async {
        await pumpBadge(tester, LicenseTier.pro, locale: locale);
        expect(find.text('PRO'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
