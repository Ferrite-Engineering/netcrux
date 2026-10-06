// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_theme/crux_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/activity/activity_analysis_result.dart';
import 'package:netcrux/domain/models/activity/activity_color_scheme.dart';
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

ActivityAnalysisResult _resultWithClock() {
  return ActivityAnalysisResult.from(
    source: null,
    timeRange: WaveformTimeRange.fullSimulationSentinel,
    perNetActivity: const <String, NetActivity>{
      'top.clk': NetActivity(
        netPath: 'top.clk',
        transitionCount: 900,
        dutyCyclePercent: 50,
        activityScore: 1,
        isClock: true,
      ),
      'top.a': NetActivity(
        netPath: 'top.a',
        transitionCount: 3,
        dutyCyclePercent: 25,
        activityScore: 1,
      ),
      'top.b': NetActivity(
        netPath: 'top.b',
        transitionCount: 1,
        dutyCyclePercent: 5,
        activityScore: 0,
      ),
    },
    analysisDuration: const Duration(milliseconds: 1),
  );
}

/// The fill color of the activity bar on the first row naming [netPath].
Color _barColorOf(WidgetTester tester, String netPath) {
  final row = find
      .ancestor(
        of: find.textContaining(netPath).first,
        matching: find.byType(Row),
      )
      .first;
  final fill = find.descendant(
    of: find.descendant(of: row, matching: find.byType(FractionallySizedBox)),
    matching: find.byType(Container),
  );
  return tester.widget<Container>(fill.first).color!;
}

/// The gradient the legend draws.
List<Color> _legendStops(WidgetTester tester) {
  final bar = tester
      .widgetList<Container>(find.byType(Container))
      .map((c) => c.decoration)
      .whereType<BoxDecoration>()
      .map((d) => d.gradient)
      .whereType<LinearGradient>()
      .single;
  return bar.colors;
}

Future<ProviderContainer> _pumpWith(
  WidgetTester tester,
  ActivityAnalysisResult result,
) async {
  await tester.pumpWidget(
    const ProviderScope(
      child: MaterialApp(
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
  container.read(activityHeatmapStateProvider.notifier).setResult(result);
  await tester.pumpAndSettle();
  return container;
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

    testWidgets('rows and legend paint the colors the schematic paints', (
      tester,
    ) async {
      final container = await _pumpWith(tester, _resultWithClock());
      for (final scheme in ActivityColorScheme.values) {
        for (final preset in <String>[cruxDarkPresetId, cruxLightPresetId]) {
          final theme = builtinPresets()[preset]!;
          container.read(cruxColorThemeProvider.notifier).activate(theme);
          container
              .read(activityHeatmapStateProvider.notifier)
              .setColorScheme(scheme);
          await tester.pumpAndSettle();
          final b = theme.brightness;
          final where = '${scheme.name} on $preset';
          expect(
            _barColorOf(tester, 'top.clk'),
            ActivityColorScheme.clockColor,
            reason: where,
          );
          expect(
            _barColorOf(tester, 'top.a'),
            scheme.colorForScore(1, b),
            reason: where,
          );
          expect(
            _barColorOf(tester, 'top.b'),
            scheme.colorForScore(0, b),
            reason: where,
          );
          expect(_legendStops(tester), scheme.stops(b), reason: where);
        }
      }
    });

    testWidgets('a clock gets a legend entry and a row tag; no clock, '
        'no entry', (tester) async {
      await _pumpWith(tester, _resultWithClock());
      final l10n = L10N.of(tester.element(find.byType(ActivityHeatmapPane)));
      // The legend entry, plus the tag on the clock's row in each list:
      // three nets fit in both the hot and the cold top-N.
      expect(find.text(l10n.activityHeatmapLegendClock), findsNWidgets(3));
      expect(find.byTooltip(l10n.activityHeatmapLegendClockTooltip), findsOne);
      expect(find.text(l10n.activityHeatmapLegendLeast), findsOne);
      expect(find.text(l10n.activityHeatmapLegendMost), findsOne);

      await _pumpWith(tester, _seedResult());
      expect(find.text(l10n.activityHeatmapLegendClock), findsNothing);
      expect(find.text(l10n.activityHeatmapLegendLeast), findsOne);
    });

    testWidgets('the legend fits a narrow dock in every locale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(260, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (final locale in <Locale>[..._locales, const Locale('zh')]) {
        await tester.pumpWidget(
          ProviderScope(
            key: ValueKey<Locale>(locale),
            child: MaterialApp(
              locale: locale,
              localizationsDelegates: L10N.localizationsDelegates,
              supportedLocales: L10N.supportedLocales,
              home: const Scaffold(body: ActivityHeatmapPane()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        ProviderScope.containerOf(
              tester.element(find.byType(ActivityHeatmapPane)),
            )
            .read(activityHeatmapStateProvider.notifier)
            .setResult(_resultWithClock());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$locale');
      }
    });
  });
}
