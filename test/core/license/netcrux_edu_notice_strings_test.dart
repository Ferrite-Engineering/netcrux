// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/license/netcrux_edu_notice_strings.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

import '../../helpers/license_status_fixtures.dart';

void main() {
  group('NetCruxEduNoticeStrings', () {
    late L10N en;
    setUpAll(() async => en = await L10N.delegate.load(const Locale('en')));

    test('English label and export mark', () {
      final strings = NetCruxEduNoticeStrings(en);
      expect(strings.statusLabel, 'Non-commercial use');
      expect(
        strings.exportMark('NetCrux'),
        'Made with NetCrux Educational · Non-commercial use only',
      );
    });

    test('the tooltip names the holder and the expiry when known', () {
      final strings = NetCruxEduNoticeStrings(en);
      expect(
        strings.statusTooltip(email: 'a@b.edu', validUntil: '2027-09-30'),
        'Educational license for a@b.edu. For non-commercial teaching, '
        'learning and research only. Valid until 2027-09-30.',
      );
      expect(
        strings.statusTooltip(),
        'Educational license. For non-commercial teaching, learning and '
        'research only.',
      );
      expect(
        strings.statusTooltip(email: 'a@b.edu'),
        isNot(contains('Valid until')),
      );
    });

    for (final locale in L10N.supportedLocales) {
      test('${locale.toLanguageTag()} carries the product name and the '
          'address unchanged, and no em dash', () async {
        final strings = NetCruxEduNoticeStrings(
          await L10N.delegate.load(locale),
        );
        final mark = strings.exportMark('NetCrux');
        final tooltip = strings.statusTooltip(
          email: 'a@b.edu',
          validUntil: '2027-09-30',
        );
        expect(mark, contains('NetCrux'));
        expect(tooltip, contains('a@b.edu'));
        expect(tooltip, contains('2027-09-30'));
        for (final s in [strings.statusLabel, mark, tooltip]) {
          expect(s, isNot(contains('—')));
        }
      });
    }
  });

  group('netcruxEduExportMark', () {
    late L10N en;
    setUpAll(() async => en = await L10N.delegate.load(const Locale('en')));

    test('an educational licence marks the export with NetCrux', () {
      expect(
        netcruxEduExportMark(activeLicenseStatus(LicenseTier.edu), en),
        'Made with NetCrux Educational · Non-commercial use only',
      );
    });

    test('open core, Pro and Enterprise leave the export unmarked', () {
      expect(netcruxEduExportMark(CruxLicenseStatus.openCore, en), isNull);
      expect(
        netcruxEduExportMark(activeLicenseStatus(LicenseTier.pro), en),
        isNull,
      );
      expect(
        netcruxEduExportMark(activeLicenseStatus(LicenseTier.enterprise), en),
        isNull,
      );
    });

    test('an expired educational licence is open core and unmarked', () {
      const expired = CruxLicenseStatus(
        activation: CruxLicenseActivation.expired,
      );
      expect(netcruxEduExportMark(expired, en), isNull);
    });
  });
}
