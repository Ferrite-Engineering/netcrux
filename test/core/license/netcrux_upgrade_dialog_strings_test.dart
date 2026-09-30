// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/license/netcrux_upgrade_dialog_strings.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

void main() {
  group('NetcruxUpgradeDialogStrings', () {
    Future<NetcruxUpgradeDialogStrings> buildAdapter(
      WidgetTester tester,
      Locale locale,
    ) async {
      late L10N captured;
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
          home: Builder(
            builder: (context) {
              captured = L10N.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      return NetcruxUpgradeDialogStrings(captured);
    }

    testWidgets('English maps to the upgradeDialog ARB vocabulary', (
      tester,
    ) async {
      final strings = await buildAdapter(tester, const Locale('en'));
      final l10n = L10N.of(
        tester.element(find.byType(SizedBox)),
      );
      expect(strings.title, l10n.upgradeDialogTitle);
      expect(strings.tierNamePro, l10n.upgradeDialogTierNamePro);
      expect(strings.tierNameEnterprise, l10n.upgradeDialogTierNameEnterprise);
      expect(strings.dismissLabel, l10n.commonOk);
      expect(
        strings.body('Run CDC Analysis', strings.tierNamePro),
        l10n.upgradeDialogMessage('Run CDC Analysis', strings.tierNamePro),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('body interpolates the feature and tier names', (tester) async {
      final strings = await buildAdapter(tester, const Locale('en'));
      final rendered = strings.body('Cone of Influence', strings.tierNamePro);
      expect(rendered, contains('Cone of Influence'));
      expect(rendered, contains(strings.tierNamePro));
    });

    testWidgets('resolves in every shipped locale without error', (
      tester,
    ) async {
      for (final locale in const [
        Locale('en'),
        Locale('zh', 'CN'),
        Locale('ja'),
        Locale('ko'),
      ]) {
        final strings = await buildAdapter(tester, locale);
        expect(strings.title, isNotEmpty);
        expect(strings.dismissLabel, isNotEmpty);
        expect(strings.body('Feature', strings.tierNameEnterprise), isNotEmpty);
      }
      expect(tester.takeException(), isNull);
    });
  });
}
