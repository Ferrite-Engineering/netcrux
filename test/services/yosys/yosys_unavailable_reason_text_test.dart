// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_yosys/crux_yosys.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/yosys/yosys_unavailable_reason_text.dart';

Future<L10N> _l10nFor(WidgetTester tester, Locale locale) async {
  late L10N l10n;
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: L10N.localizationsDelegates,
      supportedLocales: L10N.supportedLocales,
      home: Builder(
        builder: (context) {
          l10n = L10N.of(context);
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return l10n;
}

void main() {
  const modelled = <String>[
    YosysUnavailableReason.notOnPath,
    YosysUnavailableReason.execFailed,
    YosysUnavailableReason.bannerUnparsed,
    YosysUnavailableReason.probeTimedOut,
  ];

  testWidgets('every modelled reason maps to a distinct localized message', (
    tester,
  ) async {
    final l10n = await _l10nFor(tester, const Locale('en'));
    final messages = <String>{};
    for (final reason in modelled) {
      final text = yosysUnavailableReasonText(l10n, reason);
      expect(text, isNotNull, reason: reason);
      expect(text, isNotEmpty, reason: reason);
      messages.add(text!);
    }
    // Collapsing reasons into one message sends the user to the wrong
    // fix — a stalled network mount is not a missing install.
    expect(messages, hasLength(modelled.length));
  });

  testWidgets('probeTimedOut is surfaced rather than falling through', (
    tester,
  ) async {
    final l10n = await _l10nFor(tester, const Locale('en'));
    expect(
      yosysUnavailableReasonText(l10n, YosysUnavailableReason.probeTimedOut),
      isNotNull,
    );
  });

  testWidgets('an unrecognized or absent reason returns null', (tester) async {
    // The reason is a string constant, not an enum, so a newer
    // `crux_yosys` can report a code this build does not model. The
    // caller falls back to its generic message rather than rendering a
    // raw wire code.
    final l10n = await _l10nFor(tester, const Locale('en'));
    expect(yosysUnavailableReasonText(l10n, null), isNull);
    expect(yosysUnavailableReasonText(l10n, 'sandbox_denied_v2'), isNull);
    expect(yosysUnavailableReasonText(l10n, ''), isNull);
  });

  group('locale sweep', () {
    for (final locale in L10N.supportedLocales) {
      testWidgets('resolves in ${locale.toLanguageTag()}', (tester) async {
        final l10n = await _l10nFor(tester, locale);
        for (final reason in modelled) {
          expect(
            yosysUnavailableReasonText(l10n, reason),
            isNotEmpty,
            reason: '$reason in $locale',
          );
        }
      });
    }
  });
}
