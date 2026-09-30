// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The suite's upgrade-dialog copy contract, held for NetCrux in every locale
// it ships.
//
// The upgrade dialog is where a user who reached for a paid feature decides
// whether to buy it, and it used to read five different ways across four
// products. NetCrux's added a second sentence the others did not. The
// contract is one of the suite's UI conventions, documented on
// `CruxUpgradeDialogStrings` in crux_license; each of the four products
// carries this same test over its own adapter, so the English expectations
// below are literally the same sentence in all four.

import 'package:crux_license/crux_license.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/license/netcrux_upgrade_dialog_strings.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

const String _product = 'NetCrux';

/// Values no translation contains by accident, so `contains` proves the
/// argument was used rather than that a word happened to match.
const String _feature = 'Zephyr Probe';
const String _tier = 'Quux Tier';

Future<CruxUpgradeDialogStrings> _strings(Locale locale) async =>
    NetcruxUpgradeDialogStrings(await L10N.delegate.load(locale));

void main() {
  group('upgrade dialog copy contract', () {
    testWidgets('English is exactly the suite sentence', (tester) async {
      final s = await _strings(const Locale('en'));

      expect(s.title, 'Upgrade Required');
      expect(
        s.body(_feature, s.tierNamePro),
        '“Zephyr Probe” requires NetCrux Pro.',
      );
      expect(
        s.body(_feature, s.tierNameEnterprise),
        '“Zephyr Probe” requires NetCrux Enterprise.',
      );
      expect(s.dismissLabel, 'OK');
      expect(s.seePricingLabel, 'See pricing');
    });

    for (final locale in L10N.supportedLocales) {
      testWidgets('$locale: the body names the feature and the tier', (
        tester,
      ) async {
        final s = await _strings(locale);
        final body = s.body(_feature, _tier);

        expect(
          body,
          contains(_feature),
          reason: 'a denial that does not say what was refused',
        );
        expect(body, contains(_tier));
      });

      testWidgets('$locale: tier names are product-qualified prose', (
        tester,
      ) async {
        final s = await _strings(locale);

        expect(s.tierNamePro, '$_product Pro');
        expect(s.tierNameEnterprise, '$_product Enterprise');
      });

      testWidgets("$locale: dismiss is the platform's OK", (tester) async {
        final s = await _strings(locale);
        final material = await GlobalMaterialLocalizations.delegate.load(
          locale,
        );

        expect(s.dismissLabel, material.okButtonLabel);
      });

      if (locale.languageCode != 'en') {
        testWidgets('$locale: translated, not English', (tester) async {
          final s = await _strings(locale);
          final en = await _strings(const Locale('en'));

          expect(s.title, isNot(en.title));
          expect(s.body(_feature, _tier), isNot(en.body(_feature, _tier)));
          expect(s.seePricingLabel, isNot(en.seePricingLabel));
        });
      }
    }
  });
}
