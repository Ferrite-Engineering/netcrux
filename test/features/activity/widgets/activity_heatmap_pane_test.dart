// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/activity/activity_analysis_result.dart';
import 'package:netcrux/domain/models/activity/net_activity.dart';
import 'package:netcrux/domain/models/activity/waveform_time_range.dart';
import 'package:netcrux/features/activity/providers/activity_heatmap_state_provider.dart';
import 'package:netcrux/features/activity/widgets/activity_heatmap_pane.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

const _locales = <Locale>[
  Locale('en'),
  Locale('zh', 'CN'),
  Locale('ja'),
  Locale('ko'),
];

ActivityAnalysisResult _seedResult() {
  return ActivityAnalysisResult.from(
    source: null,
    timeRange: WaveformTimeRange.fullSimulationSentinel,
    perNetActivity: const <String, NetActivity>{
      'top.a': NetActivity(
        netPath: 'top.a',
        transitionCount: 100,
        dutyCyclePercent: 25,
        activityScore: 0.95,
      ),
      'top.b': NetActivity(
        netPath: 'top.b',
        transitionCount: 10,
        dutyCyclePercent: 5,
        activityScore: 0.10,
      ),
    },
    analysisDuration: const Duration(milliseconds: 1),
  );
}

Future<void> _pump(WidgetTester tester, Widget body, Locale locale) {
  return tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: Scaffold(body: body),
      ),
    ),
  );
}

void main() {
  group('ActivityHeatmapPane', () {
    for (final locale in _locales) {
      testWidgets(
        'renders empty state without exceptions (${locale.toLanguageTag()})',
        (tester) async {
          await _pump(tester, const ActivityHeatmapPane(), locale);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(
            find.byIcon(Icons.local_fire_department_outlined),
            findsOneWidget,
          );
        },
      );
    }

    testWidgets('seeded result renders both hot + cold sections', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activityHeatmapStateProvider.overrideWith(
              ActivityHeatmapNotifier.new,
            ),
          ],
          child: const MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Scaffold(body: ActivityHeatmapPane()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ActivityHeatmapPane)),
      );
      container
          .read(activityHeatmapStateProvider.notifier)
          .setResult(_seedResult());
      await tester.pumpAndSettle();
      // Both net paths should appear (top.a in hot, top.b in cold).
      expect(find.textContaining('top.a'), findsWidgets);
      expect(find.textContaining('top.b'), findsWidgets);
    });

    testWidgets('tapping a net row fires onSelectNet', (tester) async {
      NetActivity? captured;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Scaffold(
              body: ActivityHeatmapPane(onSelectNet: (n) => captured = n),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ActivityHeatmapPane)),
      );
      container
          .read(activityHeatmapStateProvider.notifier)
          .setResult(_seedResult());
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('top.a').first);
      await tester.pumpAndSettle();
      expect(captured, isNotNull);
      expect(captured!.netPath, 'top.a');
    });
  });
}
