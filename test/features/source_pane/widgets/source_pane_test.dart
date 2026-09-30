// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/interfaces/source_pane_service.dart';
import 'package:netcrux/domain/models/source_file_content.dart';
import 'package:netcrux/domain/models/source_load_exception.dart';
import 'package:netcrux/domain/models/source_location.dart';
import 'package:netcrux/domain/models/source_token.dart';
import 'package:netcrux/features/source_pane/providers/source_pane_state_provider.dart';
import 'package:netcrux/features/source_pane/widgets/source_pane.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/source_pane/source_pane_service_provider.dart';

class _FakeService implements SourcePaneService {
  _FakeService(this._content);
  final SourceFileContent _content;

  @override
  Future<SourceFileContent> loadSource(String filePath) async => _content;

  @override
  Iterable<ElementId> elementsAtSourceLocation(
    String filePath,
    int line, {
    int? column,
  }) => const <ElementId>[];

  @override
  Iterable<SourceLocation> sourceLocationsForElement(ElementId elementId) =>
      const <SourceLocation>[];

  @override
  Stream<void> get indexInvalidated => const Stream<void>.empty();
}

Widget _wrap(Widget child, {Locale locale = const Locale('en')}) {
  return ProviderScope(
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        L10N.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en'),
        Locale('zh', 'CN'),
        Locale('zh'),
        Locale('ja'),
        Locale('ko'),
      ],
      home: Scaffold(body: SizedBox(width: 500, height: 400, child: child)),
    ),
  );
}

Widget _wrapWithOverrides({
  required Widget child,
  required SourceFileContent? initialContent,
  Locale locale = const Locale('en'),
}) {
  final service = _FakeService(
    initialContent ?? SourceFileContent.empty,
  );
  return ProviderScope(
    overrides: [
      sourcePaneServiceProvider.overrideWithValue(service),
      if (initialContent != null)
        sourcePaneStateProvider.overrideWith(
          () => _SeededNotifier(initialContent),
        ),
    ],
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        L10N.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en'),
        Locale('zh', 'CN'),
        Locale('zh'),
        Locale('ja'),
        Locale('ko'),
      ],
      home: Scaffold(body: SizedBox(width: 500, height: 400, child: child)),
    ),
  );
}

class _SeededNotifier extends SourcePaneStateNotifier {
  _SeededNotifier(this._seed);
  final SourceFileContent _seed;

  @override
  SourcePaneState build() => SourcePaneState(currentContent: _seed);
}

void main() {
  group('SourcePane', () {
    testWidgets('renders empty state with hint when no content loaded', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const SourcePane()));
      await tester.pumpAndSettle();

      final l10n = await L10N.delegate.load(const Locale('en'));
      // Title + hint render as one CruxPanelEmptyState message.
      expect(find.textContaining(l10n.sourcePaneEmptyTitle), findsOneWidget);
      expect(find.textContaining(l10n.sourcePaneEmptyHint), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders source content with line numbers', (tester) async {
      const content = SourceFileContent(
        filePath: '/proj/a.v',
        lines: <String>[
          'module hello;',
          '  reg foo;',
          'endmodule',
        ],
        tokens: <SourceToken>[],
      );
      await tester.pumpWidget(
        _wrapWithOverrides(
          child: const SourcePane(),
          initialContent: content,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('error state shows the loader failure message', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sourcePaneStateProvider.overrideWith(_ErrorStateNotifier.new),
          ],
          child: const MaterialApp(
            localizationsDelegates: [
              L10N.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: [Locale('en')],
            home: Scaffold(body: SourcePane()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final l10n = await L10N.delegate.load(const Locale('en'));
      expect(find.text(l10n.sourcePaneErrorNotFound), findsOneWidget);
      expect(find.text('/proj/missing.v'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    for (final locale in const [
      Locale('en'),
      Locale('zh', 'CN'),
      Locale('zh'),
      Locale('ja'),
      Locale('ko'),
    ]) {
      testWidgets('empty state renders in $locale', (tester) async {
        await tester.pumpWidget(_wrap(const SourcePane(), locale: locale));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });
}

class _ErrorStateNotifier extends SourcePaneStateNotifier {
  @override
  SourcePaneState build() => const SourcePaneState(
    error: SourceLoadException(
      filePath: '/proj/missing.v',
      reason: SourceLoadFailure.notFound,
    ),
  );
}
