// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/interfaces/clock_domain_analysis_service.dart';
import 'package:netcrux/domain/models/cdc/cdc_analysis_options.dart';
import 'package:netcrux/domain/models/cdc/cdc_analysis_result.dart';
import 'package:netcrux/domain/models/cdc/cdc_crossing.dart';
import 'package:netcrux/domain/models/cdc/cdc_crossing_kind.dart';
import 'package:netcrux/domain/models/cdc/cdc_severity.dart';
import 'package:netcrux/domain/models/cdc/cdc_synchronizer_status.dart';
import 'package:netcrux/domain/models/cdc/clock_domain.dart';
import 'package:netcrux/domain/models/cdc/clock_domain_source_kind.dart';
import 'package:netcrux/features/cdc/providers/cdc_analysis_state_provider.dart';
import 'package:netcrux/services/cdc/clock_domain_analysis_service_provider.dart';

CdcAnalysisResult _seededResult() {
  const sig = ElementId(kind: ElementKind.signal, path: 'top.x');
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
        sourceKind: ClockDomainSourceKind.primaryInput,
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
        crossingKind: CdcCrossingKind.singleBit,
        synchronizerStatus: CdcSynchronizerStatus.properTwoFlopSync,
        severity: CdcSeverity.info,
        confidence: CdcConfidence.high,
      ),
    ],
    analysisDiagnostics: <String>[],
    analysisDuration: Duration.zero,
  );
}

void main() {
  group('CdcAnalysisState', () {
    test('empty has no result, no selection, full severity filter', () {
      const empty = CdcAnalysisState.empty;
      expect(empty.result, CdcAnalysisResult.empty);
      expect(empty.selectedCrossingId, isNull);
      expect(empty.selectedDomainId, isNull);
      expect(empty.severityFilter, <CdcSeverity>{
        CdcSeverity.critical,
        CdcSeverity.warning,
        CdcSeverity.info,
      });
    });

    test('copyWith.clearSelectedCrossingId wipes the selection', () {
      const initial = CdcAnalysisState(selectedCrossingId: 'cross-1');
      final next = initial.copyWith(clearSelectedCrossingId: true);
      expect(next.selectedCrossingId, isNull);
    });

    test('equality compares result + selection + filter set', () {
      const a = CdcAnalysisState(
        selectedCrossingId: 'cross-1',
        severityFilter: <CdcSeverity>{CdcSeverity.critical},
      );
      const b = CdcAnalysisState(
        selectedCrossingId: 'cross-1',
        severityFilter: <CdcSeverity>{CdcSeverity.critical},
      );
      const c = CdcAnalysisState(
        selectedCrossingId: 'other',
        severityFilter: <CdcSeverity>{CdcSeverity.critical},
      );
      expect(a == b, isTrue);
      expect(a == c, isFalse);
    });
  });

  group('CdcAnalysisNotifier', () {
    test('initial state is CdcAnalysisState.empty', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(
        container.read(cdcAnalysisStateProvider),
        CdcAnalysisState.empty,
      );
    });

    test('setResult installs the result', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(cdcAnalysisStateProvider.notifier)
        ..setResult(_seededResult());
      expect(notifier.state.result.detectedCrossings, hasLength(1));
    });

    test('setResult preserves selection when ids still exist', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(cdcAnalysisStateProvider.notifier)
        ..setResult(_seededResult())
        ..selectCrossing('cross-1')
        ..selectDomain('dom-A')
        // Re-install the same result (identity check on ids).
        ..setResult(_seededResult());
      expect(notifier.state.selectedCrossingId, 'cross-1');
      expect(notifier.state.selectedDomainId, 'dom-A');
    });

    test('setResult drops selection when ids are absent', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(cdcAnalysisStateProvider.notifier)
        ..setResult(_seededResult())
        ..selectCrossing('cross-1')
        ..selectDomain('dom-A')
        ..setResult(CdcAnalysisResult.empty);
      expect(notifier.state.selectedCrossingId, isNull);
      expect(notifier.state.selectedDomainId, isNull);
    });

    test('selectCrossing silently ignores unknown id', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(cdcAnalysisStateProvider.notifier)
        ..setResult(_seededResult())
        ..selectCrossing('not-there');
      expect(notifier.state.selectedCrossingId, isNull);
    });

    test('selectCrossing(null) clears the selection', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(cdcAnalysisStateProvider.notifier)
        ..setResult(_seededResult())
        ..selectCrossing('cross-1')
        ..selectCrossing(null);
      expect(notifier.state.selectedCrossingId, isNull);
    });

    test('selectDomain silently ignores unknown id', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(cdcAnalysisStateProvider.notifier)
        ..setResult(_seededResult())
        ..selectDomain('not-there');
      expect(notifier.state.selectedDomainId, isNull);
    });

    test('toggleSeverity flips a severity in / out of the filter', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(cdcAnalysisStateProvider.notifier)
        // Initially all three severities are in the filter.
        ..toggleSeverity(CdcSeverity.info);
      expect(notifier.state.severityFilter, <CdcSeverity>{
        CdcSeverity.critical,
        CdcSeverity.warning,
      });
      notifier.toggleSeverity(CdcSeverity.info);
      expect(notifier.state.severityFilter, contains(CdcSeverity.info));
    });

    test('setSeverityFilter replaces the entire set', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(cdcAnalysisStateProvider.notifier)
        ..setSeverityFilter(<CdcSeverity>{CdcSeverity.critical});
      expect(
        notifier.state.severityFilter,
        <CdcSeverity>{CdcSeverity.critical},
      );
    });

    test('clearSelection wipes crossing + domain selections', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(cdcAnalysisStateProvider.notifier)
        ..setResult(_seededResult())
        ..selectCrossing('cross-1')
        ..selectDomain('dom-A')
        ..clearSelection();
      expect(notifier.state.selectedCrossingId, isNull);
      expect(notifier.state.selectedDomainId, isNull);
    });

    test('reset() returns the notifier to CdcAnalysisState.empty', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(cdcAnalysisStateProvider.notifier)
        ..setResult(_seededResult())
        ..selectCrossing('cross-1')
        ..setSeverityFilter(<CdcSeverity>{CdcSeverity.critical})
        ..reset();
      expect(notifier.state, CdcAnalysisState.empty);
    });
  });

  group('Derived providers', () {
    test('perTabCdcAnalysisResultProvider exposes the current result', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(cdcAnalysisStateProvider.notifier)
          .setResult(_seededResult());
      final r = container.read(perTabCdcAnalysisResultProvider);
      expect(r.detectedCrossings, hasLength(1));
    });

    test('selectedCdcCrossingProvider mirrors the selection', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(cdcAnalysisStateProvider.notifier)
        ..setResult(_seededResult())
        ..selectCrossing('cross-1');
      expect(container.read(selectedCdcCrossingProvider)?.id, 'cross-1');
    });

    test('selectedClockDomainProvider mirrors the selection', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(cdcAnalysisStateProvider.notifier)
        ..setResult(_seededResult())
        ..selectDomain('dom-B');
      expect(container.read(selectedClockDomainProvider)?.id, 'dom-B');
    });

    test('cdcSeverityFilterProvider mirrors the filter', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(cdcAnalysisStateProvider.notifier).setSeverityFilter(
        <CdcSeverity>{CdcSeverity.warning},
      );
      expect(
        container.read(cdcSeverityFilterProvider),
        <CdcSeverity>{CdcSeverity.warning},
      );
    });
  });

  group('CdcAnalysisNotifier refresh on re-elaboration', () {
    test(
      'analysisInvalidated drops the stale result and selection but keeps '
      'the severity filter',
      () async {
        final fake = _FakeCdcService();
        addTearDown(fake.dispose);
        final container = ProviderContainer(
          overrides: <Override>[
            clockDomainAnalysisServiceProvider.overrideWithValue(fake),
          ],
        );
        addTearDown(container.dispose);
        // Keep the notifier alive so its invalidation subscription is live
        // (an open pane).
        final sub = container.listen(
          cdcAnalysisStateProvider,
          (_, _) {},
          fireImmediately: true,
        );
        addTearDown(sub.close);

        final notifier = container.read(cdcAnalysisStateProvider.notifier)
          ..setResult(_seededResult())
          ..selectCrossing('cross-1')
          ..selectDomain('dom-B')
          ..setSeverityFilter(<CdcSeverity>{CdcSeverity.warning});
        expect(notifier.state.result.detectedCrossings, isNotEmpty);

        // Simulate a re-elaboration.
        fake.emitInvalidation();
        await Future<void>.delayed(Duration.zero);

        final state = container.read(cdcAnalysisStateProvider);
        expect(state.result, CdcAnalysisResult.empty);
        expect(state.selectedCrossingId, isNull);
        expect(state.selectedDomainId, isNull);
        // User's severity-filter choice survives the refresh.
        expect(state.severityFilter, <CdcSeverity>{CdcSeverity.warning});
      },
    );
  });
}

/// Fake analysis service exposing a controllable invalidation stream so a
/// test can simulate a re-elaboration without a real netlist.
class _FakeCdcService implements ClockDomainAnalysisService {
  final StreamController<void> _controller = StreamController<void>.broadcast();

  void emitInvalidation() => _controller.add(null);

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
