// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_issue_reporter/crux_issue_reporter.dart';
import 'package:crux_stats_strip/crux_stats_strip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/features/diagnostics/providers/diagnostics_providers.dart';
import 'package:netcrux/features/diagnostics/widgets/app_diagnostics_dialog.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

const _session = CruxIssueSessionContext(
  fields: [
    CruxIssueField(label: 'Open tabs', value: '3'),
    CruxIssueField(label: 'Yosys', value: 'available'),
    CruxIssueField(label: 'Modules', value: '42'),
  ],
);

/// Mounts the dialog, runs [body], then unmounts it.
///
/// The unmount is not optional and cannot be an `addTearDown`: while the
/// dialog is up it holds a [cruxMemoryPollRequestProvider] tag, which keeps a
/// two-second RSS timer alive, and the test binding asserts no pending timers
/// at the end of the *test body* — before tear-downs run. Leaving the tree
/// mounted fails every test in the group with `!timersPending`.
void dialogTest(
  String description,
  Future<void> Function(WidgetTester tester, ProviderContainer container)
  body, {
  CruxIssueSessionContext session = _session,
  Locale locale = const Locale('en'),
  bool diagnosticsEnabled = true,
}) {
  testWidgets(description, (tester) async {
    final container = ProviderContainer(
      overrides: [
        cruxIssueSessionContextProvider.overrideWithValue(session),
        diagnosticsEnabledProvider.overrideWithValue(diagnosticsEnabled),
        // Never the real process RSS in a widget test.
        cruxResidentBytesReaderProvider.overrideWithValue(
          () => 128 * 1024 * 1024,
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: L10N.localizationsDelegates,
          supportedLocales: L10N.supportedLocales,
          home: const Scaffold(body: AppDiagnosticsDialog()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await body(tester, container);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}

void main() {
  group('AppDiagnosticsDialog', () {
    dialogTest('renders every section', (tester, _) async {
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('appDiagnosticsSectionMemory')), findsOne);
      expect(find.byKey(const Key('appDiagnosticsSectionPerTab')), findsOne);
      expect(
        find.byKey(const Key('appDiagnosticsSectionFrameStats')),
        findsOne,
      );
      expect(find.byKey(const Key('appDiagnosticsSectionSession')), findsOne);
    });

    dialogTest('renders the session snapshot', (tester, _) async {
      expect(find.textContaining('Open tabs'), findsOneWidget);
      expect(find.textContaining('available'), findsOneWidget);
    });

    dialogTest(
      'degrades to a placeholder with nothing to report',
      (tester, _) async {
        // A bare container has no tab manager, so the contributor legitimately
        // returns nothing — the dialog must still open rather than throw on
        // the `reduce` over an empty field list.
        expect(tester.takeException(), isNull);
        expect(find.textContaining('no session state'), findsOneWidget);
      },
      session: CruxIssueSessionContext.empty,
    );

    dialogTest('shows the no-tabs placeholder rather than an empty table', (
      tester,
      _,
    ) async {
      // No workspace plumbing in a bare container, so there are no tabs to
      // enumerate. A zero-row DataTable would render as a bare header.
      final l10n = await L10N.delegate.load(const Locale('en'));
      expect(find.text(l10n.diagnosticsNoTabs), findsOneWidget);
      expect(find.byKey(const Key('appDiagnosticsPerTabTable')), findsNothing);
    });

    dialogTest('holds a memory-poll request while open — otherwise the '
        'Memory section reads a permanent dash whenever the statistics '
        'strip is collapsed', (tester, container) async {
      expect(
        container.read(cruxMemoryPollRequestProvider),
        contains(kAppDiagnosticsMemoryTag),
      );
      expect(container.read(cruxStatsStripExpandedProvider), isFalse);
      expect(container.read(cruxMemoryPollingActiveProvider), isTrue);
    });

    testWidgets('releases the memory-poll request on dispose', (tester) async {
      final container = ProviderContainer(
        overrides: [
          cruxIssueSessionContextProvider.overrideWithValue(_session),
          diagnosticsEnabledProvider.overrideWithValue(true),
          cruxResidentBytesReaderProvider.overrideWithValue(() => 1024),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Scaffold(body: AppDiagnosticsDialog()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      expect(
        container.read(cruxMemoryPollRequestProvider),
        isEmpty,
        reason:
            'a dialog that kept its tag would leave the RSS timer running '
            'for the rest of the session',
      );
      expect(container.read(cruxMemoryPollingActiveProvider), isFalse);
    });

    dialogTest(
      'dismisses itself when the gate is off',
      (tester, _) async {
        expect(tester.takeException(), isNull);
        expect(
          find.byKey(const Key('appDiagnosticsSectionMemory')),
          findsNothing,
        );
      },
      diagnosticsEnabled: false,
    );

    group('reportFor', () {
      test('aligns the values into a column', () {
        final report = AppDiagnosticsDialog.reportFor(_session);
        // 'Open tabs' is the widest label at 9 characters, so every value
        // starts at the same column.
        final valueColumns = <int>[
          for (final line in report.split('\n'))
            if (line.contains('  '))
              line.indexOf(RegExp(r'\S'), line.indexOf('  ')),
        ];
        expect(valueColumns.toSet(), hasLength(1));
      });

      test('carries no filesystem paths — the privacy contract', () {
        // The contributor's own test asserts this over the real session; this
        // one guards the renderer from reintroducing a path of its own.
        expect(AppDiagnosticsDialog.reportFor(_session), isNot(contains('/')));
      });

      test('reports an empty session rather than throwing on the reduce', () {
        expect(
          AppDiagnosticsDialog.reportFor(CruxIssueSessionContext.empty),
          contains('no session state'),
        );
      });
    });

    group('locale sweep', () {
      for (final locale in const [
        Locale('en'),
        Locale('zh', 'CN'),
        Locale('zh'),
        Locale('ja'),
        Locale('ko'),
      ]) {
        dialogTest(
          'renders in $locale without exceptions',
          (tester, _) async => expect(tester.takeException(), isNull),
          locale: locale,
        );
      }
    });
  });
}
