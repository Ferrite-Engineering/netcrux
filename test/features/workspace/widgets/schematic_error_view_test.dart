// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/features/project/providers/loaded_netlist_provider.dart';
import 'package:netcrux/features/workspace/widgets/schematic_error_view.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

const _locales = <Locale>[
  Locale('en'),
  Locale('zh', 'CN'),
  Locale('zh'),
  Locale('ja'),
  Locale('ko'),
];

Future<void> _pump(
  WidgetTester tester,
  Object error, {
  required Locale locale,
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
      home: Scaffold(body: SchematicErrorView(error: error)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('SchematicErrorView localized envelope', () {
    for (final locale in _locales) {
      final tag = locale.countryCode == null
          ? locale.languageCode
          : '${locale.languageCode}_${locale.countryCode}';

      testWidgets('[$tag] renders the localized envelope title + never leaks '
          'the exception class name', (tester) async {
        final l10n = await L10N.delegate.load(locale);
        await _pump(
          tester,
          const LoadedNetlistException(
            'Yosys is not available: not on PATH',
            kind: LoadedNetlistErrorKind.yosysUnavailable,
          ),
          locale: locale,
        );
        expect(find.text(l10n.elaborationErrorTitle), findsOneWidget);
        expect(find.textContaining('LoadedNetlistException'), findsNothing);
        expect(tester.takeException(), isNull);
      });

      testWidgets('[$tag] yosysUnavailable → localized guidance', (
        tester,
      ) async {
        final l10n = await L10N.delegate.load(locale);
        await _pump(
          tester,
          const LoadedNetlistException(
            'Yosys is not available',
            kind: LoadedNetlistErrorKind.yosysUnavailable,
          ),
          locale: locale,
        );
        expect(
          find.text(l10n.elaborationErrorYosysUnavailable),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('[$tag] timeout → localized message with the budget', (
        tester,
      ) async {
        final l10n = await L10N.delegate.load(locale);
        await _pump(
          tester,
          const LoadedNetlistException(
            'timed out',
            kind: LoadedNetlistErrorKind.timeout,
            timeoutSeconds: 42,
          ),
          locale: locale,
        );
        expect(
          find.text(l10n.elaborationErrorTimeout(42)),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('[$tag] nonZeroExit → localized message with the code', (
        tester,
      ) async {
        final l10n = await L10N.delegate.load(locale);
        await _pump(
          tester,
          const LoadedNetlistException(
            'Yosys exited with code 3',
            kind: LoadedNetlistErrorKind.nonZeroExit,
            exitCode: 3,
            detail: 'ERROR: syntax error near line 12',
          ),
          locale: locale,
        );
        expect(
          find.text(l10n.elaborationErrorNonZeroExit(3)),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('[$tag] unknown error → generic envelope, no class leak', (
        tester,
      ) async {
        final l10n = await L10N.delegate.load(locale);
        // A non-LoadedNetlistException falls through to the generic body.
        await _pump(tester, Exception('kaboom'), locale: locale);
        expect(find.text(l10n.elaborationErrorGeneric), findsOneWidget);
        // The raw text lives in a collapsed Details expander, so the class
        // name is never visible in the envelope.
        expect(find.textContaining('Exception'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('nonZeroExit stderr detail is hidden until expanded', (
      tester,
    ) async {
      const stderr = 'ERROR: syntax error near line 12';
      final l10n = await L10N.delegate.load(const Locale('en'));
      await _pump(
        tester,
        const LoadedNetlistException(
          'Yosys exited with code 3',
          kind: LoadedNetlistErrorKind.nonZeroExit,
          exitCode: 3,
          detail: stderr,
        ),
        locale: const Locale('en'),
      );
      // Collapsed: the details label shows, the stderr does not.
      expect(find.text(l10n.elaborationErrorDetailsLabel), findsOneWidget);
      expect(find.text(stderr), findsNothing);
      // Expand → the raw stderr becomes visible for copy/paste.
      await tester.tap(find.text(l10n.elaborationErrorDetailsLabel));
      await tester.pumpAndSettle();
      expect(find.text(stderr), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
