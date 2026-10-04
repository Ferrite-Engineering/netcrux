// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The CDC and reset-domain panes answer "Show Crossings for This Signal":
// a signal filter narrows the rows, and a reveal request scrolls a row
// that is far off screen into view, flashes it, and is acknowledged.

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/cdc/cdc_analysis_result.dart';
import 'package:netcrux/domain/models/cdc/cdc_crossing.dart';
import 'package:netcrux/domain/models/cdc/cdc_crossing_kind.dart';
import 'package:netcrux/domain/models/cdc/cdc_severity.dart';
import 'package:netcrux/domain/models/cdc/cdc_synchronizer_status.dart';
import 'package:netcrux/domain/models/reset_domain/reset_crossing.dart';
import 'package:netcrux/domain/models/reset_domain/reset_crossing_kind.dart';
import 'package:netcrux/domain/models/reset_domain/reset_domain_analysis_result.dart';
import 'package:netcrux/domain/models/reset_domain/reset_polarity.dart';
import 'package:netcrux/domain/models/reset_domain/reset_severity.dart';
import 'package:netcrux/domain/models/reset_domain/reset_synchronizer_status.dart';
import 'package:netcrux/features/cdc/providers/cdc_analysis_state_provider.dart';
import 'package:netcrux/features/cdc/widgets/cdc_analysis_pane.dart';
import 'package:netcrux/features/reset_domain/providers/reset_domain_analysis_state_provider.dart';
import 'package:netcrux/features/reset_domain/widgets/reset_domain_analysis_pane.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

const int _rows = 200;

/// [_rows] crossings named `sig_000` …, each on its own domain pair so the
/// list interleaves group headers with rows like a real result.
CdcAnalysisResult _cdcResult() => CdcAnalysisResult(
  detectedDomains: const [],
  detectedCrossings: <CdcCrossing>[
    for (var i = 0; i < _rows; i++)
      CdcCrossing(
        id: 'c$i',
        sourceDomainId: 'src${i ~/ 10}',
        destinationDomainId: 'dst',
        signalId: ElementId(kind: ElementKind.signal, path: _name(i)),
        signalName: _name(i),
        crossingKind: CdcCrossingKind.singleBit,
        synchronizerStatus: CdcSynchronizerStatus.properTwoFlopSync,
        severity: CdcSeverity.info,
        confidence: CdcConfidence.high,
      ),
  ],
  analysisDiagnostics: const <String>[],
  analysisDuration: Duration.zero,
);

ResetDomainAnalysisResult _resetResult() => ResetDomainAnalysisResult(
  detectedDomains: const [],
  detectedCrossings: <ResetCrossing>[
    for (var i = 0; i < _rows; i++)
      ResetCrossing(
        id: 'r$i',
        sourceDomainId: 'src${i ~/ 10}',
        destinationDomainId: 'dst',
        signalId: ElementId(kind: ElementKind.signal, path: _name(i)),
        signalName: _name(i),
        crossingKind: ResetCrossingKind.resetDeassertCrossing,
        synchronizerStatus: ResetSynchronizerStatus.missingSynchronizer,
        severity: ResetSeverity.info,
        confidence: ResetConfidence.high,
        sourcePolarity: ResetPolarity.activeHigh,
      ),
  ],
  analysisDiagnostics: const <String>[],
  analysisDuration: Duration.zero,
);

String _name(int i) => 'sig_${i.toString().padLeft(3, '0')}';

Future<ProviderContainer> _pump(
  WidgetTester tester,
  Widget pane, {
  Locale locale = const Locale('en'),
}) async {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: const <LocalizationsDelegate<Object>>[
          L10N.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: L10N.supportedLocales,
        home: Scaffold(body: pane),
      ),
    ),
  );
  return container;
}

/// Whether the row showing [text] lies inside the list's viewport.
bool _onScreen(WidgetTester tester, String text) {
  final finder = find.text(text);
  if (finder.evaluate().isEmpty) return false;
  final list = tester.getRect(find.byType(ListView));
  final row = tester.getRect(finder);
  return row.top >= list.top && row.bottom <= list.bottom;
}

void main() {
  group('CDC pane', () {
    testWidgets('a reveal scrolls a far row into view and is acknowledged', (
      tester,
    ) async {
      final container = await _pump(tester, const CdcAnalysisPane());
      container.read(cdcAnalysisStateProvider.notifier).setResult(_cdcResult());
      await tester.pumpAndSettle();
      expect(_onScreen(tester, 'sig_180'), isFalse);

      container.read(cdcAnalysisStateProvider.notifier).showCrossingsForSignal(
        <String>['c180'],
        label: 'sig_180',
      );
      await tester.pumpAndSettle();

      expect(_onScreen(tester, 'sig_180'), isTrue);
      expect(container.read(cdcAnalysisStateProvider).revealCrossingId, isNull);
      expect(
        container.read(cdcAnalysisStateProvider).selectedCrossingId,
        'c180',
      );
    });

    testWidgets('the revealed row flashes, then settles to the selected tint', (
      tester,
    ) async {
      final container = await _pump(tester, const CdcAnalysisPane());
      container.read(cdcAnalysisStateProvider.notifier)
        ..setResult(_cdcResult())
        ..showCrossingsForSignal(<String>['c3'], label: 'sig_003');
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final flashed = _rowColour(tester, 'sig_003');
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      final settled = _rowColour(tester, 'sig_003');
      expect(flashed.a, greaterThan(settled.a));
      expect(settled.a, greaterThan(0));
    });

    testWidgets('repeating the reveal on a selected row scrolls again', (
      tester,
    ) async {
      final container = await _pump(tester, const CdcAnalysisPane());
      final notifier = container.read(cdcAnalysisStateProvider.notifier)
        ..setResult(_cdcResult())
        ..showCrossingsForSignal(<String>['c150'], label: 'sig_150');
      await tester.pumpAndSettle();
      expect(_onScreen(tester, 'sig_150'), isTrue);

      // The user scrolls away; the row stays selected.
      await tester.drag(find.byType(ListView), const Offset(0, 4000));
      await tester.pumpAndSettle();
      expect(_onScreen(tester, 'sig_150'), isFalse);

      notifier.showCrossingsForSignal(<String>['c150'], label: 'sig_150');
      await tester.pumpAndSettle();
      expect(_onScreen(tester, 'sig_150'), isTrue);
    });

    testWidgets('a signal filter lists only that signal\'s crossings', (
      tester,
    ) async {
      final container = await _pump(tester, const CdcAnalysisPane());
      container.read(cdcAnalysisStateProvider.notifier)
        ..setResult(_cdcResult())
        ..showCrossingsForSignal(<String>['c0', 'c1'], label: 'pair');
      await tester.pumpAndSettle();
      expect(find.text('sig_000'), findsOneWidget);
      expect(find.text('sig_001'), findsOneWidget);
      expect(find.text('sig_002'), findsNothing);

      container.read(cdcAnalysisStateProvider.notifier).clearSignalFilter();
      await tester.pumpAndSettle();
      expect(find.text('sig_002'), findsOneWidget);
    });
  });

  group('Reset pane', () {
    testWidgets('a reveal scrolls a far row into view and is acknowledged', (
      tester,
    ) async {
      final container = await _pump(tester, const ResetDomainAnalysisPane());
      container
          .read(resetDomainAnalysisStateProvider.notifier)
          .setResult(_resetResult());
      await tester.pumpAndSettle();
      expect(_onScreen(tester, 'sig_190'), isFalse);

      container
          .read(resetDomainAnalysisStateProvider.notifier)
          .showCrossingsForSignal(<String>['r190'], label: 'sig_190');
      await tester.pumpAndSettle();

      expect(_onScreen(tester, 'sig_190'), isTrue);
      expect(
        container.read(resetDomainAnalysisStateProvider).revealCrossingId,
        isNull,
      );
    });

    testWidgets('a signal filter lists only that signal\'s crossings', (
      tester,
    ) async {
      final container = await _pump(tester, const ResetDomainAnalysisPane());
      container.read(resetDomainAnalysisStateProvider.notifier)
        ..setResult(_resetResult())
        ..showCrossingsForSignal(<String>['r4', 'r5'], label: 'pair');
      await tester.pumpAndSettle();
      expect(find.text('sig_004'), findsOneWidget);
      expect(find.text('sig_005'), findsOneWidget);
      expect(find.text('sig_000'), findsNothing);
    });
  });

  group('locale sweep', () {
    for (final locale in L10N.supportedLocales) {
      testWidgets('a revealed row renders in $locale', (tester) async {
        final container = await _pump(
          tester,
          const CdcAnalysisPane(),
          locale: locale,
        );
        container.read(cdcAnalysisStateProvider.notifier)
          ..setResult(_cdcResult())
          ..showCrossingsForSignal(<String>['c120'], label: 'sig_120');
        await tester.pumpAndSettle();
        expect(_onScreen(tester, 'sig_120'), isTrue);
        expect(tester.takeException(), isNull);
      });
    }
  });
}

/// The background tint of the crossing row showing [text].
Color _rowColour(WidgetTester tester, String text) {
  final container = tester.widget<AnimatedContainer>(
    find.ancestor(
      of: find.text(text),
      matching: find.byType(AnimatedContainer),
    ),
  );
  final decoration = container.decoration as BoxDecoration?;
  return decoration?.color ?? const Color(0x00000000);
}
