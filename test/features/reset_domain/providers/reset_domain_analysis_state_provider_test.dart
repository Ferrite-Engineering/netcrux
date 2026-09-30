// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
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
import 'package:netcrux/features/reset_domain/providers/reset_domain_analysis_state_provider.dart';

ResetDomainAnalysisResult _seededResult() {
  const sig = ElementId(kind: ElementKind.signal, path: 'top.x');
  const rstA = ElementId(kind: ElementKind.signal, path: 'top.rst_a');
  const rstB = ElementId(kind: ElementKind.signal, path: 'top.rst_b');
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
        resetSignalName: 'rst_b',
        polarity: ResetPolarity.activeLow,
        synchronicity: ResetSynchronicity.asyncAssertSyncDeassert,
        sourceKind: ResetSourceKind.primaryInput,
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
        synchronizerStatus:
            ResetSynchronizerStatus.properAsyncAssertSyncDeassert,
        severity: ResetSeverity.info,
        confidence: ResetConfidence.high,
        sourcePolarity: ResetPolarity.activeHigh,
      ),
    ],
    analysisDiagnostics: <String>[],
    analysisDuration: Duration.zero,
  );
}

void main() {
  group('ResetDomainAnalysisState', () {
    test('empty has no result, no selection, full severity filter', () {
      const empty = ResetDomainAnalysisState.empty;
      expect(empty.result, ResetDomainAnalysisResult.empty);
      expect(empty.selectedCrossingId, isNull);
      expect(empty.selectedDomainId, isNull);
      expect(empty.severityFilter, <ResetSeverity>{
        ResetSeverity.critical,
        ResetSeverity.warning,
        ResetSeverity.info,
      });
    });

    test('copyWith.clearSelectedCrossingId wipes the selection', () {
      const initial = ResetDomainAnalysisState(
        selectedCrossingId: 'cross-1',
      );
      final next = initial.copyWith(clearSelectedCrossingId: true);
      expect(next.selectedCrossingId, isNull);
    });

    test('equality compares result + selection + filter set', () {
      const a = ResetDomainAnalysisState(
        selectedCrossingId: 'cross-1',
        severityFilter: <ResetSeverity>{ResetSeverity.critical},
      );
      const b = ResetDomainAnalysisState(
        selectedCrossingId: 'cross-1',
        severityFilter: <ResetSeverity>{ResetSeverity.critical},
      );
      const c = ResetDomainAnalysisState(
        selectedCrossingId: 'other',
        severityFilter: <ResetSeverity>{ResetSeverity.critical},
      );
      expect(a == b, isTrue);
      expect(a == c, isFalse);
    });
  });

  group('ResetDomainAnalysisNotifier', () {
    test('initial state is ResetDomainAnalysisState.empty', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(
        container.read(resetDomainAnalysisStateProvider),
        ResetDomainAnalysisState.empty,
      );
    });

    test('setResult installs the result', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(resetDomainAnalysisStateProvider.notifier)
        ..setResult(_seededResult());
      expect(notifier.state.result.detectedCrossings, hasLength(1));
    });

    test('setResult preserves selection when ids still exist', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(resetDomainAnalysisStateProvider.notifier)
        ..setResult(_seededResult())
        ..selectCrossing('cross-1')
        ..selectDomain('dom-A')
        ..setResult(_seededResult());
      expect(notifier.state.selectedCrossingId, 'cross-1');
      expect(notifier.state.selectedDomainId, 'dom-A');
    });

    test('setResult drops selection when ids are absent', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(resetDomainAnalysisStateProvider.notifier)
        ..setResult(_seededResult())
        ..selectCrossing('cross-1')
        ..selectDomain('dom-A')
        ..setResult(ResetDomainAnalysisResult.empty);
      expect(notifier.state.selectedCrossingId, isNull);
      expect(notifier.state.selectedDomainId, isNull);
    });

    test('selectCrossing silently ignores unknown id', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(resetDomainAnalysisStateProvider.notifier)
        ..setResult(_seededResult())
        ..selectCrossing('not-there');
      expect(notifier.state.selectedCrossingId, isNull);
    });

    test('selectCrossing(null) clears the selection', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(resetDomainAnalysisStateProvider.notifier)
        ..setResult(_seededResult())
        ..selectCrossing('cross-1')
        ..selectCrossing(null);
      expect(notifier.state.selectedCrossingId, isNull);
    });

    test('selectDomain silently ignores unknown id', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(resetDomainAnalysisStateProvider.notifier)
        ..setResult(_seededResult())
        ..selectDomain('not-there');
      expect(notifier.state.selectedDomainId, isNull);
    });

    test('toggleSeverity flips a severity in / out of the filter', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(resetDomainAnalysisStateProvider.notifier)
        ..toggleSeverity(ResetSeverity.info);
      expect(notifier.state.severityFilter, <ResetSeverity>{
        ResetSeverity.critical,
        ResetSeverity.warning,
      });
      notifier.toggleSeverity(ResetSeverity.info);
      expect(notifier.state.severityFilter, contains(ResetSeverity.info));
    });

    test('setSeverityFilter replaces the entire set', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(resetDomainAnalysisStateProvider.notifier)
        ..setSeverityFilter(<ResetSeverity>{ResetSeverity.critical});
      expect(
        notifier.state.severityFilter,
        <ResetSeverity>{ResetSeverity.critical},
      );
    });

    test('clearSelection wipes crossing + domain selections', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(resetDomainAnalysisStateProvider.notifier)
        ..setResult(_seededResult())
        ..selectCrossing('cross-1')
        ..selectDomain('dom-A')
        ..clearSelection();
      expect(notifier.state.selectedCrossingId, isNull);
      expect(notifier.state.selectedDomainId, isNull);
    });

    test('reset() returns the notifier to '
        'ResetDomainAnalysisState.empty', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(resetDomainAnalysisStateProvider.notifier)
        ..setResult(_seededResult())
        ..selectCrossing('cross-1')
        ..setSeverityFilter(<ResetSeverity>{ResetSeverity.critical})
        ..reset();
      expect(notifier.state, ResetDomainAnalysisState.empty);
    });
  });

  group('Derived providers', () {
    test('perTabResetDomainAnalysisResultProvider exposes the result', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(resetDomainAnalysisStateProvider.notifier)
          .setResult(_seededResult());
      final r = container.read(perTabResetDomainAnalysisResultProvider);
      expect(r.detectedCrossings, hasLength(1));
    });

    test('selectedResetCrossingProvider returns the focused crossing', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(resetDomainAnalysisStateProvider.notifier)
        ..setResult(_seededResult())
        ..selectCrossing('cross-1');
      expect(
        container.read(selectedResetCrossingProvider)?.id,
        'cross-1',
      );
    });

    test('selectedResetDomainProvider returns the focused domain', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(resetDomainAnalysisStateProvider.notifier)
        ..setResult(_seededResult())
        ..selectDomain('dom-A');
      expect(container.read(selectedResetDomainProvider)?.id, 'dom-A');
    });

    test('resetSeverityFilterProvider returns the active filter set', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(resetDomainAnalysisStateProvider.notifier)
          .setSeverityFilter(<ResetSeverity>{ResetSeverity.critical});
      expect(
        container.read(resetSeverityFilterProvider),
        <ResetSeverity>{ResetSeverity.critical},
      );
    });
  });
}
