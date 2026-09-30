// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/updates/netcrux_update_strings.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

/// `crux_updates` carries no ARB files, so the five-locale parity of the
/// update copy is NetCrux's responsibility. This sweep proves every getter on
/// the adapter resolves to a non-empty ARB entry in every shipped locale, and
/// that the two interpolating messages actually place the version.
void main() {
  /// Resolves [L10N] for [locale] and hands the adapter to [body].
  Future<void> withStrings(
    WidgetTester tester,
    String locale,
    void Function(NetcruxUpdateStrings strings) body,
  ) async {
    final parts = locale.split('_');
    await tester.pumpWidget(
      MaterialApp(
        locale: parts.length == 2 ? Locale(parts[0], parts[1]) : Locale(locale),
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: Builder(
          builder: (context) {
            body(NetcruxUpdateStrings(L10N.of(context)));
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }

  group('NetcruxUpdateStrings', () {
    for (final locale in ['en', 'zh_CN', 'zh', 'ja', 'ko']) {
      testWidgets('every string resolves in $locale', (tester) async {
        await withStrings(tester, locale, (strings) {
          expect(strings.bannerMessage('1.2.0'), isNotEmpty);
          expect(strings.viewChangesAction, isNotEmpty);
          expect(strings.updateNowAction, isNotEmpty);
          expect(strings.dismissLabel, isNotEmpty);
          expect(strings.checkInProgress, isNotEmpty);
          expect(strings.checkUpToDate('1.2.0'), isNotEmpty);
          expect(strings.checkFailed, isNotEmpty);
        });
        expect(tester.takeException(), isNull);
      });

      testWidgets('the version is interpolated in $locale', (tester) async {
        await withStrings(tester, locale, (strings) {
          expect(strings.bannerMessage('4.5.6'), contains('4.5.6'));
          expect(strings.checkUpToDate('4.5.6'), contains('4.5.6'));
        });
      });
    }

    testWidgets('the banner message carries the product name', (tester) async {
      // `CruxUpdateStrings.bannerMessage` takes only the version — the product
      // name belongs to the product's own ARB entry, which is what keeps the
      // package free of any one product's branding.
      await withStrings(tester, 'en', (strings) {
        expect(strings.bannerMessage('1.2.0'), contains('NetCrux'));
      });
    });
  });
}
