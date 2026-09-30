// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/features/diagnostics/providers/diagnostics_providers.dart';
import 'package:netcrux/features/diagnostics/widgets/pane_render_stats_popover.dart';
import 'package:netcrux/features/statistics/providers/layout_timing_provider.dart';
import 'package:netcrux/features/viewer/providers/pane_render_stats.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

const _painted = PaneRenderStats(
  frameNumber: 12,
  paintMicroseconds: 3400,
  visibleCells: 40,
  visibleEdges: 90,
  totalCells: 1200,
  totalEdges: 3000,
);

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  PaneRenderStats stats = _painted,
  bool diagnosticsEnabled = true,
  Locale locale = const Locale('en'),
}) async {
  final container = ProviderContainer(
    overrides: [
      diagnosticsEnabledProvider.overrideWithValue(diagnosticsEnabled),
    ],
  );
  addTearDown(container.dispose);
  container.read(paneRenderStatsProvider.notifier).record(stats);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: const Scaffold(
          // Right-aligned so the popover's off-screen clamp is exercised by
          // the same path a docked pane would take.
          body: Align(
            alignment: Alignment.topRight,
            child: PaneRenderStatsButton(),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  group('PaneRenderStatsButton', () {
    testWidgets('renders when diagnostics are on', (tester) async {
      await _pump(tester);
      expect(find.byKey(const Key('paneRenderStatsButton')), findsOneWidget);
    });

    testWidgets('hides itself when diagnostics are off', (tester) async {
      await _pump(tester, diagnosticsEnabled: false);
      expect(find.byKey(const Key('paneRenderStatsButton')), findsNothing);
    });

    testWidgets('opens the popover with this pane readings', (tester) async {
      final container = await _pump(tester);
      container
          .read(layoutTimingProvider.notifier)
          .completed(
            const Duration(milliseconds: 250),
          );

      await tester.tap(find.byKey(const Key('paneRenderStatsButton')));
      await tester.pumpAndSettle();

      final l10n = await L10N.delegate.load(const Locale('en'));
      expect(find.text(l10n.paneRenderStatsTitle), findsOneWidget);
      expect(find.text('3.4 ms'), findsOneWidget);
      expect(find.text('250.0 ms'), findsOneWidget);
      // Visible-over-total, not visible alone: the interesting number is how
      // much of the design the viewport is actually costing.
      expect(find.text('40 / 1200'), findsOneWidget);
      expect(find.text('90 / 3000'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
    });

    testWidgets('says so rather than showing zeros before the first paint', (
      tester,
    ) async {
      await _pump(tester, stats: PaneRenderStats.empty);

      await tester.tap(find.byKey(const Key('paneRenderStatsButton')));
      await tester.pumpAndSettle();

      final l10n = await L10N.delegate.load(const Locale('en'));
      expect(find.text(l10n.paneRenderStatsEmpty), findsOneWidget);
      expect(find.text(l10n.paneRenderStatsPaint), findsNothing);
    });

    testWidgets('shows a dash for layout time before any layout pass', (
      tester,
    ) async {
      await _pump(tester);

      await tester.tap(find.byKey(const Key('paneRenderStatsButton')));
      await tester.pumpAndSettle();

      expect(find.text('—'), findsOneWidget);
    });

    testWidgets('closes on the close button', (tester) async {
      await _pump(tester);
      await tester.tap(find.byKey(const Key('paneRenderStatsButton')));
      await tester.pumpAndSettle();

      final l10n = await L10N.delegate.load(const Locale('en'));
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.text(l10n.paneRenderStatsTitle), findsNothing);
    });

    for (final locale in const [
      Locale('en'),
      Locale('zh', 'CN'),
      Locale('zh'),
      Locale('ja'),
      Locale('ko'),
    ]) {
      testWidgets('renders in $locale without exceptions', (tester) async {
        await _pump(tester, locale: locale);
        await tester.tap(find.byKey(const Key('paneRenderStatsButton')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });
}
