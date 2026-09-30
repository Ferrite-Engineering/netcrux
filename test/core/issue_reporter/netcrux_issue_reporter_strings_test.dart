// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/issue_reporter/netcrux_issue_reporter_strings.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

/// `crux_issue_reporter` carries no ARB files, so the five-locale parity of
/// the reporter's UI copy is NetCrux's responsibility. This sweep proves every
/// getter on the adapter resolves to a non-empty ARB entry in every shipped
/// locale.
void main() {
  Future<void> withStrings(
    WidgetTester tester,
    String locale,
    void Function(NetcruxIssueReporterStrings strings) body,
  ) async {
    final parts = locale.split('_');
    await tester.pumpWidget(
      MaterialApp(
        locale: parts.length == 2 ? Locale(parts[0], parts[1]) : Locale(locale),
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: Builder(
          builder: (context) {
            body(NetcruxIssueReporterStrings(L10N.of(context)));
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }

  group('NetcruxIssueReporterStrings', () {
    for (final locale in ['en', 'zh_CN', 'zh', 'ja', 'ko']) {
      testWidgets('every string resolves in $locale', (tester) async {
        await withStrings(tester, locale, (s) {
          expect(s.dialogTitle, isNotEmpty);
          expect(s.titleFieldLabel, isNotEmpty);
          expect(s.titleFieldHint, isNotEmpty);
          expect(s.privacyNotice, isNotEmpty);
          expect(s.previewHeader, isNotEmpty);
          expect(s.categoryAppEnv, isNotEmpty);
          expect(s.categoryAppEnvDescription, isNotEmpty);
          expect(s.categorySession, isNotEmpty);
          expect(s.categorySessionDescription, isNotEmpty);
          expect(s.categoryLog, isNotEmpty);
          expect(s.categoryLogDescription, isNotEmpty);
          expect(s.categoryScreenshot, isNotEmpty);
          expect(s.categoryScreenshotDescription, isNotEmpty);
          expect(s.lockedCategorySemantics, isNotEmpty);
          expect(s.submitButton, isNotEmpty);
          expect(s.cancelButton, isNotEmpty);
          expect(s.openedToast, isNotEmpty);
          expect(s.openedToastPrefilled, isNotEmpty);
          expect(s.screenshotSaved('/tmp/shot.png'), isNotEmpty);
          expect(s.emptyLogPlaceholder, isNotEmpty);
          expect(s.emptySessionLogPlaceholder, isNotEmpty);
        });
        expect(tester.takeException(), isNull);
      });

      testWidgets('the screenshot path is interpolated in $locale', (
        tester,
      ) async {
        await withStrings(tester, locale, (s) {
          expect(s.screenshotSaved('/tmp/shot.png'), contains('/tmp/shot.png'));
        });
      });
    }
  });
}
