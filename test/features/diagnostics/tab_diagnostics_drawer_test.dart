// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/features/diagnostics/widgets/tab_diagnostics_drawer.dart';
import 'package:netcrux/features/project/providers/elaboration_diagnostics_provider.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

void main() {
  group('TabDiagnosticsDrawer', () {
    Widget app(Locale locale) {
      return ProviderScope(
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: const [
            L10N.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: L10N.supportedLocales,
          home: const Scaffold(body: TabDiagnosticsDrawer()),
        ),
      );
    }

    for (final locale in const <Locale>[
      Locale('en'),
      Locale('zh', 'CN'),
      Locale('ja'),
      Locale('ko'),
    ]) {
      testWidgets('renders empty state without exceptions ($locale)', (
        tester,
      ) async {
        await tester.pumpWidget(app(locale));
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('renders parsed diagnostics from the stderr provider', (
      tester,
    ) async {
      late ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          child: Builder(
            builder: (context) {
              container = ProviderScope.containerOf(context);
              return const MaterialApp(
                localizationsDelegates: [
                  L10N.delegate,
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                supportedLocales: L10N.supportedLocales,
                home: Scaffold(body: TabDiagnosticsDrawer()),
              );
            },
          ),
        ),
      );
      container
          .read(elaborationStderrProvider.notifier)
          .set('Warning: top.v:42: signal foo unused');
      await tester.pumpAndSettle();
      expect(find.textContaining('foo'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
