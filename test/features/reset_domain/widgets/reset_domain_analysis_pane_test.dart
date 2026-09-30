// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/reset_domain/reset_crossing.dart';
import 'package:netcrux/domain/models/reset_domain/reset_crossing_kind.dart';
import 'package:netcrux/domain/models/reset_domain/reset_domain.dart';
import 'package:netcrux/domain/models/reset_domain/reset_domain_analysis_result.dart';
import 'package:netcrux/domain/models/reset_domain/reset_polarity.dart';
import 'package:netcrux/domain/models/reset_domain/reset_severity.dart';
import 'package:netcrux/domain/models/reset_domain/reset_source_kind.dart';
import 'package:netcrux/domain/models/reset_domain/reset_synchronicity.dart';
import 'package:netcrux/domain/models/reset_domain/reset_synchronizer_status.dart';
import 'package:netcrux/domain/models/reset_domain/unreset_register.dart';
import 'package:netcrux/features/reset_domain/providers/reset_domain_analysis_state_provider.dart';
import 'package:netcrux/features/reset_domain/widgets/reset_domain_analysis_pane.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

ResetDomainAnalysisResult _seededResult() {
  const sig = ElementId(kind: ElementKind.signal, path: 'top.x');
  const sig2 = ElementId(kind: ElementKind.signal, path: 'top.y');
  const rstA = ElementId(kind: ElementKind.signal, path: 'top.rst_a');
  const rstB = ElementId(kind: ElementKind.signal, path: 'top.rst_b_n');
  return const ResetDomainAnalysisResult(
    detectedDomains: <ResetDomain>[
      ResetDomain(
        id: 'dom-A',
        resetSignalId: rstA,
        resetSignalName: 'rst_a',
        polarity: ResetPolarity.activeHigh,
        synchronicity: ResetSynchronicity.asyncAssertSyncDeassert,
        sourceKind: ResetSourceKind.primaryInput,
        memberRegisters: <ElementId>[],
        memberNets: <ElementId>[],
      ),
      ResetDomain(
        id: 'dom-B',
        resetSignalId: rstB,
        resetSignalName: 'rst_b_n',
        polarity: ResetPolarity.activeLow,
        synchronicity: ResetSynchronicity.asyncAssertSyncDeassert,
        sourceKind: ResetSourceKind.powerOnReset,
        memberRegisters: <ElementId>[],
        memberNets: <ElementId>[],
      ),
    ],
    detectedCrossings: <ResetCrossing>[
      ResetCrossing(
        id: 'cross-1',
        sourceDomainId: 'dom-A',
        destinationDomainId: 'dom-B',
        signalId: sig,
        signalName: 'x',
        crossingKind: ResetCrossingKind.resetDeassertCrossing,
        synchronizerStatus: ResetSynchronizerStatus.missingSynchronizer,
        severity: ResetSeverity.critical,
        confidence: ResetConfidence.high,
        sourcePolarity: ResetPolarity.activeHigh,
      ),
      ResetCrossing(
        id: 'cross-2',
        sourceDomainId: 'dom-A',
        destinationDomainId: 'dom-B',
        signalId: sig2,
        signalName: 'y',
        crossingKind: ResetCrossingKind.dataCrossesResetBoundary,
        synchronizerStatus:
            ResetSynchronizerStatus.properAsyncAssertSyncDeassert,
        severity: ResetSeverity.info,
        confidence: ResetConfidence.medium,
        sourcePolarity: ResetPolarity.activeLow,
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

/// The seeded 2-domain result plus an unreset-register finding.
ResetDomainAnalysisResult _seededWithUnreset(
  List<UnresetRegister> unreset,
) {
  final base = _seededResult();
  return ResetDomainAnalysisResult(
    detectedDomains: base.detectedDomains,
    detectedCrossings: base.detectedCrossings,
    unresetRegisters: unreset,
    analysisDiagnostics: base.analysisDiagnostics,
    analysisDuration: base.analysisDuration,
  );
}

const _alarmR = UnresetRegister(
  registerId: ElementId(kind: ElementKind.signal, path: 'top.alarm_r'),
  registerName: 'alarm_r',
  width: 1,
);

ProviderContainer _seededContainer() {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  container
      .read(resetDomainAnalysisStateProvider.notifier)
      .setResult(_seededResult());
  return container;
}

void main() {
  testWidgets('renders empty state when no result is set', (tester) async {
    await tester.pumpWidget(_harness(const ResetDomainAnalysisPane()));
    await tester.pumpAndSettle();
    // Title + hint render as one CruxPanelEmptyState message.
    expect(find.textContaining('No reset domain analysis run'), findsOneWidget);
  });

  testWidgets(
    'renders crossings grouped by domain pair with localized subtitles',
    (tester) async {
      final container = _seededContainer();
      await tester.pumpWidget(
        _harness(const ResetDomainAnalysisPane(), container: container),
      );
      await tester.pumpAndSettle();

      // One group header for the (rst_a, rst_b_n) pair; both crossings
      // beneath it with `kind · status · polarity · confidence`
      // subtitles built from the localized enum labels.
      expect(find.text('rst_a to rst_b_n'), findsOneWidget);
      expect(find.text('x'), findsOneWidget);
      expect(find.text('y'), findsOneWidget);
      expect(
        find.text(
          'Reset deassert crossing · Missing synchronizer · Active high '
          '· High confidence',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Data crosses reset boundary · Async assert + sync deassert '
          '· Active low · Medium confidence',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('renders the unreset-registers section', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(resetDomainAnalysisStateProvider.notifier)
        .setResult(_seededWithUnreset(const <UnresetRegister>[_alarmR]));
    await tester.pumpWidget(
      _harness(const ResetDomainAnalysisPane(), container: container),
    );
    await tester.pumpAndSettle();

    expect(find.text('Unreset registers'), findsOneWidget);
    expect(find.text('alarm_r'), findsOneWidget);
    expect(find.text('register never reset — powers up X'), findsOneWidget);
  });

  testWidgets('unreset section hides when the warning filter is off', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(resetDomainAnalysisStateProvider.notifier)
        .setResult(_seededWithUnreset(const <UnresetRegister>[_alarmR]));
    // Unreset findings are warning-severity — dropping Warning hides them.
    container
        .read(resetDomainAnalysisStateProvider.notifier)
        .toggleSeverity(ResetSeverity.warning);
    await tester.pumpWidget(
      _harness(const ResetDomainAnalysisPane(), container: container),
    );
    await tester.pumpAndSettle();
    expect(find.text('Unreset registers'), findsNothing);
    expect(find.text('alarm_r'), findsNothing);
  });

  testWidgets('honors the state provider severity filter', (tester) async {
    final container = _seededContainer();
    // Drop `info` from the filter — the info-severity crossing `y`
    // disappears while the critical `x` stays.
    container
        .read(resetDomainAnalysisStateProvider.notifier)
        .toggleSeverity(ResetSeverity.info);

    await tester.pumpWidget(
      _harness(const ResetDomainAnalysisPane(), container: container),
    );
    await tester.pumpAndSettle();
    expect(find.text('x'), findsOneWidget);
    expect(find.text('y'), findsNothing);

    // Toggling it back restores the row.
    container
        .read(resetDomainAnalysisStateProvider.notifier)
        .toggleSeverity(ResetSeverity.info);
    await tester.pumpAndSettle();
    expect(find.text('y'), findsOneWidget);
  });

  testWidgets('rows are tappable when onSelectCrossing is supplied', (
    tester,
  ) async {
    final container = _seededContainer();
    ResetCrossing? tapped;
    await tester.pumpWidget(
      _harness(
        ResetDomainAnalysisPane(onSelectCrossing: (c) => tapped = c),
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
    container
        .read(resetDomainAnalysisStateProvider.notifier)
        .selectCrossing('cross-1');
    await tester.pumpWidget(
      _harness(const ResetDomainAnalysisPane(), container: container),
    );
    await tester.pumpAndSettle();
    expect(find.text('x'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('grouped body renders in every supported locale', (
    tester,
  ) async {
    for (final locale in L10N.supportedLocales) {
      final container = ProviderContainer();
      container
          .read(resetDomainAnalysisStateProvider.notifier)
          .setResult(_seededResult());
      await tester.pumpWidget(
        _harness(
          const ResetDomainAnalysisPane(),
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
          const ResetDomainAnalysisPane(),
          locale: locale,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });
}
