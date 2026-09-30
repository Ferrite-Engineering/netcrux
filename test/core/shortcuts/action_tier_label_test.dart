// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/shortcuts/action_tier_label.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

void main() {
  group('tierLabelSuffix', () {
    testWidgets('open-core and edu produce no suffix (every locale)', (
      tester,
    ) async {
      for (final locale in L10N.supportedLocales) {
        final l10n = await L10N.delegate.load(locale);
        expect(
          tierLabelSuffix(LicenseTier.openCore, l10n),
          isEmpty,
          reason: 'open-core must not get a tier suffix in $locale',
        );
        expect(
          tierLabelSuffix(LicenseTier.edu, l10n),
          isEmpty,
          reason: 'edu must not get a tier suffix in $locale',
        );
      }
    });

    testWidgets('pro / enterprise produce parenthetical suffixes (every '
        'locale)', (tester) async {
      for (final locale in L10N.supportedLocales) {
        final l10n = await L10N.delegate.load(locale);
        final pro = tierLabelSuffix(LicenseTier.pro, l10n);
        final ent = tierLabelSuffix(LicenseTier.enterprise, l10n);

        // Leads with a space so it appends cleanly after the label, and
        // carries the abbreviated tier badge text.
        expect(pro, startsWith(' '), reason: 'pro suffix in $locale');
        expect(pro, contains(l10n.tierBadgePro));
        expect(ent, startsWith(' '), reason: 'ent suffix in $locale');
        expect(ent, contains(l10n.tierBadgeEnterprise));
        // Pro and Enterprise are distinguishable.
        expect(pro, isNot(equals(ent)), reason: 'distinct suffixes in $locale');
      }
    });
  });
}
