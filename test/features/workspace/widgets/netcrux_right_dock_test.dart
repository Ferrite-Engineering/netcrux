// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/interfaces/x_trace_service.dart';
import 'package:netcrux/domain/models/analysis/analysis_panel_kind.dart';
import 'package:netcrux/features/inspector/widgets/inspector_panel.dart';
import 'package:netcrux/features/remote/providers/cross_probe_visible_provider.dart';
import 'package:netcrux/features/viewer/providers/analysis_dock_provider.dart';
import 'package:netcrux/features/viewer/providers/panel_layout_provider.dart';
import 'package:netcrux/features/viewer/providers/right_dock_provider.dart';
import 'package:netcrux/features/viewer/providers/trace_overlay_notifier.dart';
import 'package:netcrux/features/viewer/providers/x_trace_panel_visible_provider.dart';
import 'package:netcrux/features/viewer/providers/x_trace_result_notifier.dart';
import 'package:netcrux/features/viewer/services/x_trace_controller.dart';
import 'package:netcrux/features/viewer/widgets/x_trace_result_panel.dart';
import 'package:netcrux/features/workspace/widgets/netcrux_docks.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

XTraceResult _chain() => const XTraceResult(
  rootNetId: 7,
  chain: <XTraceStep>[
    XTraceStep(depth: 0, netId: 7, edgeId: 'e7', cellId: 'buf1'),
    XTraceStep(depth: 1, netId: 1, edgeId: 'e1', boundaryPortId: 'port:d_in'),
  ],
  termination: XTraceTermination.reachedBoundary,
);

void main() {
  Widget harness(ProviderContainer container, {Locale? locale}) {
    return UncontrolledProviderScope(
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
        home: const Scaffold(body: NetcruxRightDock()),
      ),
    );
  }

  ProviderContainer makeContainer({List<Override> overrides = const []}) {
    final container = ProviderContainer(overrides: overrides);
    addTearDown(container.dispose);
    return container;
  }

  Widget marker(BuildContext context, AnalysisPanelKind kind) =>
      Text('panel:${kind.name}');

  group('NetcruxRightDock', () {
    testWidgets('shows the pinned Inspector tab while nothing is docked', (
      tester,
    ) async {
      final container = makeContainer(
        overrides: [analysisPanelBuilderProvider.overrideWithValue(marker)],
      );
      await tester.pumpWidget(harness(container));
      await tester.pumpAndSettle();
      expect(find.byType(InspectorPanel), findsOneWidget);
      expect(find.textContaining('panel:'), findsNothing);
      // Single pinned entry → titled-header presentation, no tab affordance.
      expect(
        find.byKey(const ValueKey('cruxDockTab-inspector')),
        findsNothing,
      );
    });

    testWidgets('an opened analysis becomes a closable tab beside Inspector, '
        'and its × closes the dock', (tester) async {
      final container = makeContainer(
        overrides: [analysisPanelBuilderProvider.overrideWithValue(marker)],
      );
      await tester.pumpWidget(harness(container));
      await tester.pumpAndSettle();

      container.read(analysisDockProvider.notifier).open(AnalysisPanelKind.cdc);
      await tester.pumpAndSettle();
      expect(find.text('panel:cdc'), findsOneWidget);
      // Inspector is still one click away as a tab — the whole point.
      expect(
        find.byKey(const ValueKey('cruxDockTab-inspector')),
        findsOneWidget,
      );

      // Opening a different kind ADDS a second analysis tab — multi-open —
      // and brings it frontmost.
      container
          .read(analysisDockProvider.notifier)
          .open(AnalysisPanelKind.diff);
      await tester.pumpAndSettle();
      expect(find.text('panel:diff'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('cruxDockTab-analysis:cdc')),
        findsOneWidget,
        reason: 'CDC stays open beside the diff — what the strip is for',
      );

      // × closes THAT analysis only; CDC (the most recently opened
      // remaining analysis) comes frontmost.
      await tester.tap(
        find.byKey(const ValueKey('cruxDockClose-analysis:diff')),
      );
      await tester.pumpAndSettle();
      expect(
        container.read(analysisDockProvider),
        [AnalysisPanelKind.cdc],
      );
      expect(find.text('panel:cdc'), findsOneWidget);

      // Closing the last one falls back to the Inspector, region open.
      await tester.tap(
        find.byKey(const ValueKey('cruxDockClose-analysis:cdc')),
      );
      await tester.pumpAndSettle();
      expect(container.read(analysisDockProvider), isEmpty);
      expect(find.byType(InspectorPanel), findsOneWidget);
    });

    testWidgets('the Source kind docks as its own closable tab', (
      tester,
    ) async {
      final container = makeContainer(
        overrides: [analysisPanelBuilderProvider.overrideWithValue(marker)],
      );
      await tester.pumpWidget(harness(container));
      container
          .read(analysisDockProvider.notifier)
          .open(AnalysisPanelKind.source);
      await tester.pumpAndSettle();
      expect(find.text('panel:source'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('cruxDockTab-analysis:source')),
        findsOneWidget,
      );
      expect(find.text('Source'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('cruxDockClose-analysis:source')),
      );
      await tester.pumpAndSettle();
      expect(container.read(analysisDockProvider), isEmpty);
      expect(find.byType(InspectorPanel), findsOneWidget);
    });

    testWidgets('tapping the Inspector tab keeps the analysis listed', (
      tester,
    ) async {
      final container = makeContainer(
        overrides: [analysisPanelBuilderProvider.overrideWithValue(marker)],
      );
      await tester.pumpWidget(harness(container));
      await tester.pumpAndSettle();
      container.read(analysisDockProvider.notifier).open(AnalysisPanelKind.cdc);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('cruxDockTab-inspector')));
      await tester.pumpAndSettle();
      expect(find.byType(InspectorPanel), findsOneWidget);
      // The analysis did NOT close — it is one click away, which the old
      // one-slot AnalysisDockHost could never offer.
      expect(
        find.byKey(const ValueKey('cruxDockTab-analysis:cdc')),
        findsOneWidget,
      );
    });

    testWidgets('open-core (no Pro builder) never lists an analysis tab', (
      tester,
    ) async {
      final container = makeContainer();
      await tester.pumpWidget(harness(container));
      container.read(analysisDockProvider.notifier).open(AnalysisPanelKind.fsm);
      await tester.pumpAndSettle();
      expect(find.byType(InspectorPanel), findsOneWidget);
      expect(find.textContaining('panel:'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('cross-probe rides as a closable tab', (tester) async {
      final container = makeContainer();
      await tester.pumpWidget(harness(container));
      container.read(crossProbeVisibleProvider.notifier).set(visible: true);
      container
          .read(rightDockTabProvider.notifier)
          .reveal(kRightDockTabCrossProbe);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('cruxDockTab-crossProbe')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('cruxDockClose-crossProbe')));
      await tester.pumpAndSettle();
      expect(container.read(crossProbeVisibleProvider), isFalse);
      expect(find.byType(InspectorPanel), findsOneWidget);
    });

    testWidgets('the X-Trace tab is keyed on visibility, NOT on a result', (
      tester,
    ) async {
      final container = makeContainer();
      await tester.pumpWidget(harness(container));

      // A result with the panel hidden lists no tab: the walk's output is not
      // what puts the panel on screen.
      container.read(xTraceResultProvider.notifier).set(_chain());
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('cruxDockTab-xTrace')), findsNothing);

      // Visibility with NO result does — the panel must be able to be open and
      // empty, which is the state `xTracePanelEmpty` is written for.
      container.read(xTraceResultProvider.notifier).clear();
      container.read(xTracePanelVisibleProvider.notifier).set(visible: true);
      container.read(rightDockTabProvider.notifier).reveal(kRightDockTabXTrace);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('cruxDockTab-xTrace')), findsOneWidget);
      expect(find.byType(XTraceResultPanel), findsOneWidget);
      expect(
        find.text('No active X-trace. Select a net and run "Show X-Trace".'),
        findsOneWidget,
      );
    });

    testWidgets('× closes the panel but KEEPS the result, so reopening '
        'restores the chain', (tester) async {
      final container = makeContainer();
      await tester.pumpWidget(harness(container));
      container.read(xTraceResultProvider.notifier).set(_chain());
      container.read(xTracePanelVisibleProvider.notifier).set(visible: true);
      container.read(rightDockTabProvider.notifier).reveal(kRightDockTabXTrace);
      await tester.pumpAndSettle();
      expect(find.text('Step 0'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('cruxDockClose-xTrace')));
      await tester.pumpAndSettle();
      expect(container.read(xTracePanelVisibleProvider), isFalse);
      // The distinction the ARB strings encode and the easiest thing to get
      // wrong: closing is not clearing.
      expect(container.read(xTraceResultProvider).isEmpty, isFalse);

      container.read(xTracePanelVisibleProvider.notifier).set(visible: true);
      container.read(rightDockTabProvider.notifier).reveal(kRightDockTabXTrace);
      await tester.pumpAndSettle();
      expect(find.text('Step 0'), findsOneWidget);
    });

    testWidgets('the strip Clear empties the result and the overlay, and '
        'leaves the panel mounted on its empty state', (tester) async {
      final container = makeContainer();
      await tester.pumpWidget(harness(container));
      container.read(xTraceResultProvider.notifier).set(_chain());
      container.read(traceOverlayProvider.notifier).set(overlayFor(_chain()));
      container.read(xTracePanelVisibleProvider.notifier).set(visible: true);
      container.read(rightDockTabProvider.notifier).reveal(kRightDockTabXTrace);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Clear'));
      await tester.pumpAndSettle();

      expect(container.read(xTraceResultProvider).isEmpty, isTrue);
      expect(container.read(traceOverlayProvider).isEmpty, isTrue);
      // Clear empties the RESULT, not the panel.
      expect(container.read(xTracePanelVisibleProvider), isTrue);
      expect(find.byType(XTraceResultPanel), findsOneWidget);
      expect(
        find.text('No active X-trace. Select a net and run "Show X-Trace".'),
        findsOneWidget,
      );
    });

    testWidgets('the strip Clear is disabled while there is nothing to clear', (
      tester,
    ) async {
      final container = makeContainer();
      await tester.pumpWidget(harness(container));
      container.read(xTracePanelVisibleProvider.notifier).set(visible: true);
      container.read(rightDockTabProvider.notifier).reveal(kRightDockTabXTrace);
      await tester.pumpAndSettle();

      final button = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.clear),
      );
      expect(button.onPressed, isNull);
    });
  });

  group('AnalysisDockNotifier (reveal semantics)', () {
    test('open reveals the tab and the region; toggle/close keep contract', () {
      final container = makeContainer();
      final notifier = container.read(analysisDockProvider.notifier);
      expect(container.read(analysisDockProvider), isEmpty);

      notifier.open(AnalysisPanelKind.cdc);
      expect(container.read(analysisDockProvider), [AnalysisPanelKind.cdc]);
      expect(
        container.read(effectiveRightDockTabProvider),
        analysisDockTabId(AnalysisPanelKind.cdc),
      );
      expect(
        container.read(panelLayoutProvider).inspectorVisible,
        isTrue,
        reason: 'open() reveals the region through the ordinary flag',
      );

      // Toggle of an open kind closes IT; toggle of another kind adds it.
      notifier.toggle(AnalysisPanelKind.cdc);
      expect(container.read(analysisDockProvider), isEmpty);
      expect(
        container.read(effectiveRightDockTabProvider),
        kRightDockTabInspector,
        reason: 'a stale analysis id falls back to Inspector',
      );
      notifier
        ..toggle(AnalysisPanelKind.activity)
        ..toggle(AnalysisPanelKind.resetDomain);
      expect(container.read(analysisDockProvider), [
        AnalysisPanelKind.activity,
        AnalysisPanelKind.resetDomain,
      ]);
      // Closing a non-frontmost kind leaves the other open; the effective
      // tab falls back to the most recently opened remaining analysis.
      notifier.close(AnalysisPanelKind.resetDomain);
      expect(container.read(analysisDockProvider), [
        AnalysisPanelKind.activity,
      ]);
      expect(
        container.read(effectiveRightDockTabProvider),
        analysisDockTabId(AnalysisPanelKind.activity),
      );

      notifier.closeAll();
      expect(container.read(analysisDockProvider), isEmpty);
      // Idempotent close.
      notifier.closeAll();
      expect(container.read(analysisDockProvider), isEmpty);
    });
  });

  group('crossProbeShowingProvider', () {
    test('lights only when the CXP tab is frontmost in an open region', () {
      final container = makeContainer();
      expect(container.read(crossProbeShowingProvider), isFalse);

      container.read(crossProbeVisibleProvider.notifier).set(visible: true);
      container
          .read(rightDockTabProvider.notifier)
          .reveal(kRightDockTabCrossProbe);
      expect(container.read(crossProbeShowingProvider), isTrue);

      // Behind the Inspector tab → not showing.
      container
          .read(rightDockTabProvider.notifier)
          .select(
            kRightDockTabInspector,
          );
      expect(container.read(crossProbeShowingProvider), isFalse);
    });

    // The assertions above are structural — they use stub panel bodies and
    // key-based finders, so they never touch a localized string. The dock
    // itself is not structural: netcrux_docks.dart renders 28 localized
    // strings as tab labels and tooltips, in a strip whose width is fixed by
    // the layout. Additive sweep so a CJK label that overflows or throws is
    // caught here.
    for (final locale in L10N.supportedLocales) {
      testWidgets('renders without exceptions in ${locale.toLanguageTag()}', (
        tester,
      ) async {
        final container = makeContainer(
          overrides: [analysisPanelBuilderProvider.overrideWithValue(marker)],
        );
        await tester.pumpWidget(harness(container, locale: locale));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(InspectorPanel), findsOneWidget);
      });
    }

    // Every analysis kind's tab carries a label in every locale: one tab per
    // kind, all open at once, the strip at its tightest.
    for (final locale in L10N.supportedLocales) {
      testWidgets('labels every analysis tab in ${locale.toLanguageTag()}', (
        tester,
      ) async {
        final container = makeContainer(
          overrides: [analysisPanelBuilderProvider.overrideWithValue(marker)],
        );
        await tester.pumpWidget(harness(container, locale: locale));
        AnalysisPanelKind.values.forEach(
          container.read(analysisDockProvider.notifier).open,
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        final l10n = await L10N.delegate.load(locale);
        expect(find.text(l10n.dockTabSource), findsOneWidget);
        expect(l10n.dockTabSource, isNotEmpty);
      });
    }
  });
}
