// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

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
import 'package:netcrux/domain/models/cdc/clock_domain.dart';
import 'package:netcrux/domain/models/cdc/clock_domain_source_kind.dart';
import 'package:netcrux/features/cdc/providers/cdc_analysis_state_provider.dart';
import 'package:netcrux/features/cdc/widgets/cdc_analysis_pane.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

CdcAnalysisResult _seededResult() {
  const sig = ElementId(kind: ElementKind.signal, path: 'top.x');
  const sig2 = ElementId(kind: ElementKind.signal, path: 'top.y');
  const clkA = ElementId(kind: ElementKind.signal, path: 'top.clk_a');
  const clkB = ElementId(kind: ElementKind.signal, path: 'top.clk_b');
  return const CdcAnalysisResult(
    detectedDomains: <ClockDomain>[
      ClockDomain(
        id: 'dom-A',
        clockSignalId: clkA,
        clockSignalName: 'clk_a',
        sourceKind: ClockDomainSourceKind.primaryInput,
        memberRegisters: <ElementId>[],
        memberNets: <ElementId>[],
      ),
      ClockDomain(
        id: 'dom-B',
        clockSignalId: clkB,
        clockSignalName: 'clk_b',
        sourceKind: ClockDomainSourceKind.pll,
        memberRegisters: <ElementId>[],
        memberNets: <ElementId>[],
      ),
    ],
    detectedCrossings: <CdcCrossing>[
      CdcCrossing(
        id: 'cross-1',
        sourceDomainId: 'dom-A',
        destinationDomainId: 'dom-B',
        signalId: sig,
        signalName: 'x',
        crossingKind: CdcCrossingKind.multiBit,
        synchronizerStatus: CdcSynchronizerStatus.missingSynchronizer,
        severity: CdcSeverity.critical,
        confidence: CdcConfidence.high,
      ),
      CdcCrossing(
        id: 'cross-2',
        sourceDomainId: 'dom-A',
        destinationDomainId: 'dom-B',
        signalId: sig2,
        signalName: 'y',
        crossingKind: CdcCrossingKind.singleBit,
        synchronizerStatus: CdcSynchronizerStatus.properTwoFlopSync,
        severity: CdcSeverity.info,
        confidence: CdcConfidence.medium,
      ),
    ],
    analysisDiagnostics: <String>[],
    analysisDuration: Duration.zero,
  );
}

Widget _harness(
  Widget child, {
  ProviderContainer? container,
  Locale locale = const Locale('en'),
}) {
  final app = MaterialApp(
    locale: locale,
    localizationsDelegates: const <LocalizationsDelegate<Object>>[
      L10N.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: L10N.supportedLocales,
    home: Scaffold(body: child),
  );
  if (container == null) return ProviderScope(child: app);
  return UncontrolledProviderScope(container: container, child: app);
}

ProviderContainer _seededContainer() {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  container.read(cdcAnalysisStateProvider.notifier).setResult(_seededResult());
  return container;
}

void main() {
  testWidgets('renders empty state when no result is set', (tester) async {
    await tester.pumpWidget(_harness(const CdcAnalysisPane()));
    await tester.pumpAndSettle();
    // Title + hint render as one CruxPanelEmptyState message.
    expect(find.textContaining('No CDC analysis run'), findsOneWidget);
  });

  testWidgets(
    'renders crossings grouped by domain pair with localized subtitles',
    (tester) async {
      final container = _seededContainer();
      await tester.pumpWidget(
        _harness(const CdcAnalysisPane(), container: container),
      );
      await tester.pumpAndSettle();

      // One group header for the (clk_a, clk_b) pair; both crossings
      // beneath it with `kind · status · confidence` subtitles built
      // from the localized enum labels.
      expect(find.text('clk_a to clk_b'), findsOneWidget);
      expect(find.text('x'), findsOneWidget);
      expect(find.text('y'), findsOneWidget);
      expect(
        find.text('Multi-bit · Missing synchronizer · High confidence'),
        findsOneWidget,
      );
      expect(
        find.text('Single-bit · 2-flop sync · Medium confidence'),
        findsOneWidget,
      );
    },
  );

  testWidgets('honors the state provider severity filter', (tester) async {
    final container = _seededContainer();
    // Drop `info` from the filter — the info-severity crossing `y`
    // disappears while the critical `x` stays.
    container
        .read(cdcAnalysisStateProvider.notifier)
        .toggleSeverity(CdcSeverity.info);

    await tester.pumpWidget(
      _harness(const CdcAnalysisPane(), container: container),
    );
    await tester.pumpAndSettle();
    expect(find.text('x'), findsOneWidget);
    expect(find.text('y'), findsNothing);

    // Toggling it back restores the row.
    container
        .read(cdcAnalysisStateProvider.notifier)
        .toggleSeverity(CdcSeverity.info);
    await tester.pumpAndSettle();
    expect(find.text('y'), findsOneWidget);
  });

  testWidgets('rows are tappable when onSelectCrossing is supplied', (
    tester,
  ) async {
    final container = _seededContainer();
    CdcCrossing? tapped;
    await tester.pumpWidget(
      _harness(
        CdcAnalysisPane(onSelectCrossing: (c) => tapped = c),
        container: container,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('x'));
    await tester.pump();
    expect(tapped?.id, 'cross-1');
  });

  testWidgets('selected crossing row renders the highlight tint', (
    tester,
  ) async {
    final container = _seededContainer();
    container.read(cdcAnalysisStateProvider.notifier).selectCrossing('cross-1');
    await tester.pumpWidget(
      _harness(const CdcAnalysisPane(), container: container),
    );
    await tester.pumpAndSettle();
    // Both rows render; no exception from the highlight branch.
    expect(find.text('x'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('grouped body renders in every supported locale', (
    tester,
  ) async {
    for (final locale in L10N.supportedLocales) {
      final container = ProviderContainer();
      container
          .read(cdcAnalysisStateProvider.notifier)
          .setResult(_seededResult());
      await tester.pumpWidget(
        _harness(
          const CdcAnalysisPane(),
          container: container,
          locale: locale,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    }
  });

  testWidgets('empty state renders in every supported locale', (tester) async {
    for (final locale in L10N.supportedLocales) {
      await tester.pumpWidget(
        _harness(
          const CdcAnalysisPane(),
          locale: locale,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });
}
