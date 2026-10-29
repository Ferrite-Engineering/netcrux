// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/features/project/providers/loaded_netlist_provider.dart';
import 'package:netcrux/features/workspace/widgets/schematic_error_view.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/yosys/sv_frontend_gap.dart';

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
  VoidCallback? onShowMissingModulesAsBlackBoxes,
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
      home: Scaffold(
        body: SchematicErrorView(
          error: error,
          onShowMissingModulesAsBlackBoxes: onShowMissingModulesAsBlackBoxes,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const LoadedNetlistException _missingModule = LoadedNetlistException(
  'Elaboration failed: a module is not part of the design',
  kind: LoadedNetlistErrorKind.missingModule,
  exitCode: 1,
  missingModule: 'INV',
  detail:
      r"ERROR: Module `\INV' referenced in module `\top' in cell `\u1' is "
      'not part of the design.',
);

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

      testWidgets('[$tag] a built-in reader gap names the construct and the '
          'way past it, not the exit code', (tester) async {
        final l10n = await L10N.delegate.load(locale);
        for (final (gap, sentence) in <(SvFrontendGap, String)>[
          (
            SvFrontendGap.returnStatement,
            l10n.elaborationErrorSvFrontendReturn,
          ),
          (SvFrontendGap.packageImport, l10n.elaborationErrorSvFrontendImport),
          (SvFrontendGap.nonConstantCast, l10n.elaborationErrorSvFrontendCast),
        ]) {
          await _pump(
            tester,
            LoadedNetlistException(
              'Elaboration failed with exit code 1',
              kind: LoadedNetlistErrorKind.nonZeroExit,
              exitCode: 1,
              detail: 'x.sv:3: ERROR: syntax error, unexpected TOK_IMPORT',
              frontendGap: gap,
            ),
            locale: locale,
          );
          expect(
            find.text('$sentence ${l10n.elaborationErrorSvFrontendHint}'),
            findsOneWidget,
          );
          expect(find.text(l10n.elaborationErrorNonZeroExit(1)), findsNothing);
        }
        expect(tester.takeException(), isNull);
      });

      testWidgets('[$tag] missingModule → names the module, offers black '
          'boxes', (tester) async {
        final l10n = await L10N.delegate.load(locale);
        await _pump(
          tester,
          _missingModule,
          locale: locale,
          onShowMissingModulesAsBlackBoxes: () {},
        );
        expect(
          find.text(l10n.elaborationErrorMissingModule('INV')),
          findsOneWidget,
        );
        expect(find.text(l10n.elaborationErrorShowBlackBoxes), findsOneWidget);
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

    testWidgets('the black-box action calls back once per tap', (
      tester,
    ) async {
      var taps = 0;
      await _pump(
        tester,
        _missingModule,
        locale: const Locale('en'),
        onShowMissingModulesAsBlackBoxes: () => taps++,
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('showMissingModulesAsBlackBoxes')),
      );
      await tester.pump();
      expect(taps, 1);
      expect(find.text('Show missing modules as black boxes'), findsOneWidget);
    });

    testWidgets('a missing module the message does not name still reads', (
      tester,
    ) async {
      final l10n = await L10N.delegate.load(const Locale('en'));
      await _pump(
        tester,
        const LoadedNetlistException(
          'Elaboration failed: a module is not part of the design',
          kind: LoadedNetlistErrorKind.missingModule,
          exitCode: 1,
        ),
        locale: const Locale('en'),
        onShowMissingModulesAsBlackBoxes: () {},
      );
      expect(
        find.text(l10n.elaborationErrorMissingModuleUnnamed),
        findsOneWidget,
      );
    });

    testWidgets('no action without a callback, or for any other failure', (
      tester,
    ) async {
      final action = find.byKey(
        const ValueKey<String>('showMissingModulesAsBlackBoxes'),
      );
      await _pump(tester, _missingModule, locale: const Locale('en'));
      expect(action, findsNothing);
      await _pump(
        tester,
        const LoadedNetlistException(
          'Yosys exited with code 3',
          kind: LoadedNetlistErrorKind.nonZeroExit,
          exitCode: 3,
        ),
        locale: const Locale('en'),
        onShowMissingModulesAsBlackBoxes: () {},
      );
      expect(action, findsNothing);
    });

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
