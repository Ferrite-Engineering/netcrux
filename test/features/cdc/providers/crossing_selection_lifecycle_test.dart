// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The crossing-selection lifecycle shared by the CDC and reset-domain
// states: whether a result is current, row-click toggling, the
// "Show Crossings for This Signal" focus (signal filter, severity chips,
// reveal request), and the clears (panel close, invalidation, Escape's
// shared clear).

import 'dart:async';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/interfaces/clock_domain_analysis_service.dart';
import 'package:netcrux/domain/models/analysis/analysis_panel_kind.dart';
import 'package:netcrux/domain/models/analysis/crossing_signal_filter.dart';
import 'package:netcrux/domain/models/cdc/cdc_analysis_options.dart';
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
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/features/cdc/providers/cdc_analysis_state_provider.dart';
import 'package:netcrux/features/reset_domain/providers/reset_domain_analysis_state_provider.dart';
import 'package:netcrux/features/viewer/providers/analysis_dock_provider.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/features/viewer/services/clear_schematic_paint.dart';
import 'package:netcrux/services/cdc/clock_domain_analysis_service_provider.dart';

CdcCrossing _cdc(String id, String signal, CdcSeverity severity) => CdcCrossing(
  id: id,
  sourceDomainId: 'dom-A',
  destinationDomainId: 'dom-B',
  signalId: ElementId(kind: ElementKind.signal, path: signal),
  signalName: signal,
  crossingKind: CdcCrossingKind.singleBit,
  synchronizerStatus: CdcSynchronizerStatus.properTwoFlopSync,
  severity: severity,
  confidence: CdcConfidence.high,
);

/// Two crossings on `x` (info and critical) and one on `y`.
CdcAnalysisResult _cdcResult() => CdcAnalysisResult(
  detectedDomains: const [],
  detectedCrossings: <CdcCrossing>[
    _cdc('c1', 'x', CdcSeverity.info),
    _cdc('c2', 'x', CdcSeverity.critical),
    _cdc('c3', 'y', CdcSeverity.warning),
  ],
  analysisDiagnostics: const <String>[],
  analysisDuration: Duration.zero,
);

ResetCrossing _rst(String id, String signal, ResetSeverity severity) =>
    ResetCrossing(
      id: id,
      sourceDomainId: 'dom-A',
      destinationDomainId: 'dom-B',
      signalId: ElementId(kind: ElementKind.signal, path: signal),
      signalName: signal,
      crossingKind: ResetCrossingKind.resetDeassertCrossing,
      synchronizerStatus: ResetSynchronizerStatus.missingSynchronizer,
      severity: severity,
      confidence: ResetConfidence.high,
      sourcePolarity: ResetPolarity.activeHigh,
    );

ResetDomainAnalysisResult _resetResult() => ResetDomainAnalysisResult(
  detectedDomains: const [],
  detectedCrossings: <ResetCrossing>[
    _rst('r1', 'x', ResetSeverity.info),
    _rst('r2', 'x', ResetSeverity.critical),
    _rst('r3', 'y', ResetSeverity.warning),
  ],
  analysisDiagnostics: const <String>[],
  analysisDuration: Duration.zero,
);

/// A container whose CDC and reset notifiers stay alive (an open pane).
ProviderContainer _container({List<Override> overrides = const []}) {
  final container = ProviderContainer(
    overrides: <Override>[
      analysisDockProvider.overrideWith(_BareDock.new),
      ...overrides,
    ],
  );
  addTearDown(container.dispose);
  final cdc = container.listen(cdcAnalysisStateProvider, (_, _) {});
  final reset = container.listen(resetDomainAnalysisStateProvider, (_, _) {});
  addTearDown(cdc.close);
  addTearDown(reset.close);
  return container;
}

/// The dock's open list without the right-dock reveal, which reads the
/// persisted panel layout this unit test has no store for.
class _BareDock extends AnalysisDockNotifier {
  @override
  void open(AnalysisPanelKind kind) {
    if (!state.contains(kind)) state = [...state, kind];
  }
}

void main() {
  group('CDC crossing selection', () {
    test('a result is current once installed, not before', () {
      final c = _container();
      expect(c.read(cdcAnalysisStateProvider).hasCurrentResult, isFalse);
      c.read(cdcAnalysisStateProvider.notifier).setResult(_cdcResult());
      expect(c.read(cdcAnalysisStateProvider).hasCurrentResult, isTrue);
    });

    test('an empty result is still a current one', () {
      final c = _container();
      c
          .read(cdcAnalysisStateProvider.notifier)
          .setResult(CdcAnalysisResult.empty);
      expect(c.read(cdcAnalysisStateProvider).hasCurrentResult, isTrue);
    });

    test(
      'a re-elaboration makes the result stale and drops the focus',
      () async {
        final service = _InvalidatingCdcService();
        addTearDown(service.dispose);
        final c = _container(
          overrides: <Override>[
            clockDomainAnalysisServiceProvider.overrideWithValue(service),
          ],
        );
        c.read(cdcAnalysisStateProvider.notifier)
          ..setResult(_cdcResult())
          ..showCrossingsForSignal(<String>['c1', 'c2'], label: 'x');
        service.invalidate();
        await Future<void>.delayed(Duration.zero);
        final state = c.read(cdcAnalysisStateProvider);
        expect(state.hasCurrentResult, isFalse);
        expect(state.selectedCrossingId, isNull);
        expect(state.signalFilter, isNull);
        expect(state.revealCrossingId, isNull);
      },
    );

    test('clicking the selected row deselects it', () {
      final c = _container();
      final notifier = c.read(cdcAnalysisStateProvider.notifier)
        ..setResult(_cdcResult())
        ..toggleCrossing('c3');
      expect(notifier.state.selectedCrossingId, 'c3');
      notifier.toggleCrossing('c3');
      expect(notifier.state.selectedCrossingId, isNull);
      notifier.toggleCrossing('c1');
      expect(notifier.state.selectedCrossingId, 'c1');
    });

    test('several crossings filter the pane to that signal', () {
      final c = _container();
      c.read(cdcAnalysisStateProvider.notifier)
        ..setResult(_cdcResult())
        ..showCrossingsForSignal(<String>['c1', 'c2'], label: 'x');
      final state = c.read(cdcAnalysisStateProvider);
      expect(
        state.signalFilter,
        const CrossingSignalFilter(label: 'x', crossingIds: {'c1', 'c2'}),
      );
      expect(state.visibleCrossings.map((x) => x.id), <String>['c1', 'c2']);
      expect(state.selectedCrossingId, 'c1');
      expect(state.revealCrossingId, 'c1');
    });

    test('a single crossing is focused without a filter', () {
      final c = _container();
      c.read(cdcAnalysisStateProvider.notifier)
        ..setResult(_cdcResult())
        ..showCrossingsForSignal(<String>['c1', 'c2'], label: 'x')
        ..showCrossingsForSignal(<String>['c3'], label: 'y');
      final state = c.read(cdcAnalysisStateProvider);
      expect(state.signalFilter, isNull);
      expect(state.selectedCrossingId, 'c3');
      expect(state.visibleCrossings, hasLength(3));
    });

    test('repeating the command on the selected crossing raises a reveal', () {
      final c = _container();
      final notifier = c.read(cdcAnalysisStateProvider.notifier)
        ..setResult(_cdcResult())
        ..showCrossingsForSignal(<String>['c3'], label: 'y')
        ..acknowledgeReveal('c3');
      expect(notifier.state.revealCrossingId, isNull);
      notifier.showCrossingsForSignal(<String>['c3'], label: 'y');
      expect(notifier.state.selectedCrossingId, 'c3');
      expect(notifier.state.revealCrossingId, 'c3');
    });

    test('a focused crossing among the matches stays focused', () {
      final c = _container();
      c.read(cdcAnalysisStateProvider.notifier)
        ..setResult(_cdcResult())
        ..selectCrossing('c2')
        ..showCrossingsForSignal(<String>['c1', 'c2'], label: 'x');
      expect(c.read(cdcAnalysisStateProvider).selectedCrossingId, 'c2');
    });

    test('severity chips hiding a match are switched back on', () {
      final c = _container();
      c.read(cdcAnalysisStateProvider.notifier)
        ..setResult(_cdcResult())
        ..setSeverityFilter(<CdcSeverity>{CdcSeverity.warning})
        ..showCrossingsForSignal(<String>['c1', 'c2'], label: 'x');
      expect(c.read(cdcAnalysisStateProvider).severityFilter, <CdcSeverity>{
        CdcSeverity.warning,
        CdcSeverity.info,
        CdcSeverity.critical,
      });
    });

    test('clearSignalFilter shows every crossing again', () {
      final c = _container();
      c.read(cdcAnalysisStateProvider.notifier)
        ..setResult(_cdcResult())
        ..showCrossingsForSignal(<String>['c1', 'c2'], label: 'x')
        ..clearSignalFilter();
      final state = c.read(cdcAnalysisStateProvider);
      expect(state.signalFilter, isNull);
      expect(state.visibleCrossings, hasLength(3));
      // The focus survives dropping the filter.
      expect(state.selectedCrossingId, 'c1');
    });

    test('a new result without the filtered ids drops the filter', () {
      final c = _container();
      final notifier = c.read(cdcAnalysisStateProvider.notifier)
        ..setResult(_cdcResult())
        ..showCrossingsForSignal(<String>['c1', 'c2'], label: 'x')
        ..setResult(_cdcResult());
      expect(notifier.state.signalFilter, isNotNull);
      notifier.setResult(CdcAnalysisResult.empty);
      expect(notifier.state.signalFilter, isNull);
      expect(notifier.state.revealCrossingId, isNull);
    });

    test('closing the CDC panel clears its selection and filter', () {
      final c = _container();
      c.read(analysisDockProvider.notifier).open(AnalysisPanelKind.cdc);
      c.read(cdcAnalysisStateProvider.notifier)
        ..setResult(_cdcResult())
        ..showCrossingsForSignal(<String>['c1', 'c2'], label: 'x');
      c.read(analysisDockProvider.notifier).close(AnalysisPanelKind.cdc);
      final state = c.read(cdcAnalysisStateProvider);
      expect(state.selectedCrossingId, isNull);
      expect(state.signalFilter, isNull);
      // The result itself survives: reopening the panel lists it again.
      expect(state.result.detectedCrossings, hasLength(3));
    });

    test('closing another panel leaves the CDC selection alone', () {
      final c = _container();
      c.read(analysisDockProvider.notifier)
        ..open(AnalysisPanelKind.cdc)
        ..open(AnalysisPanelKind.fsm);
      c.read(cdcAnalysisStateProvider.notifier)
        ..setResult(_cdcResult())
        ..selectCrossing('c1');
      c.read(analysisDockProvider.notifier).close(AnalysisPanelKind.fsm);
      expect(c.read(cdcAnalysisStateProvider).selectedCrossingId, 'c1');
    });
  });

  group('Reset crossing selection', () {
    test('a result is current once installed', () {
      final c = _container();
      expect(
        c.read(resetDomainAnalysisStateProvider).hasCurrentResult,
        isFalse,
      );
      c
          .read(resetDomainAnalysisStateProvider.notifier)
          .setResult(_resetResult());
      expect(c.read(resetDomainAnalysisStateProvider).hasCurrentResult, isTrue);
    });

    test('clicking the selected row deselects it', () {
      final c = _container();
      final notifier = c.read(resetDomainAnalysisStateProvider.notifier)
        ..setResult(_resetResult())
        ..toggleCrossing('r1');
      expect(notifier.state.selectedCrossingId, 'r1');
      notifier.toggleCrossing('r1');
      expect(notifier.state.selectedCrossingId, isNull);
    });

    test('several crossings filter the pane and raise a reveal', () {
      final c = _container();
      c.read(resetDomainAnalysisStateProvider.notifier)
        ..setResult(_resetResult())
        ..showCrossingsForSignal(<String>['r1', 'r2'], label: 'x');
      final state = c.read(resetDomainAnalysisStateProvider);
      expect(state.signalFilter?.crossingIds, <String>{'r1', 'r2'});
      expect(state.visibleCrossings.map((x) => x.id), <String>['r1', 'r2']);
      expect(state.revealCrossingId, 'r1');
    });

    test('closing the reset panel clears its selection and filter', () {
      final c = _container();
      c.read(analysisDockProvider.notifier).open(AnalysisPanelKind.resetDomain);
      c.read(resetDomainAnalysisStateProvider.notifier)
        ..setResult(_resetResult())
        ..showCrossingsForSignal(<String>['r1', 'r2'], label: 'x');
      c
          .read(analysisDockProvider.notifier)
          .close(AnalysisPanelKind.resetDomain);
      final state = c.read(resetDomainAnalysisStateProvider);
      expect(state.selectedCrossingId, isNull);
      expect(state.signalFilter, isNull);
    });
  });

  group('clearSchematicPaint (Escape)', () {
    test('clears the selection and both crossing focuses in one call', () {
      final c = _container();
      c.read(cdcAnalysisStateProvider.notifier)
        ..setResult(_cdcResult())
        ..selectCrossing('c1');
      c.read(resetDomainAnalysisStateProvider.notifier)
        ..setResult(_resetResult())
        ..selectCrossing('r2');
      c
          .read(selectedElementProvider.notifier)
          .select(const SelectedElement.cell(cellId: 'u1'));

      clearSchematicPaint(c.read);

      expect(c.read(cdcAnalysisStateProvider).selectedCrossingId, isNull);
      expect(
        c.read(resetDomainAnalysisStateProvider).selectedCrossingId,
        isNull,
      );
      expect(c.read(selectedElementProvider).isNotEmpty, isFalse);
      // Results stay: Escape clears paint, not analyses.
      expect(c.read(cdcAnalysisStateProvider).hasCurrentResult, isTrue);
    });
  });
}

class _InvalidatingCdcService implements ClockDomainAnalysisService {
  final StreamController<void> _controller = StreamController<void>.broadcast();

  void invalidate() => _controller.add(null);

  void dispose() => unawaited(_controller.close());

  @override
  Stream<void> get analysisInvalidated => _controller.stream;

  @override
  Future<CdcAnalysisResult> analyze({CdcAnalysisOptions? options}) async =>
      CdcAnalysisResult.empty;

  @override
  Future<List<CdcCrossing>> crossingsForSignal(String signalPath) async =>
      const <CdcCrossing>[];

  @override
  Future<List<CdcCrossing>> crossingsForDomain(String domainId) async =>
      const <CdcCrossing>[];
}
