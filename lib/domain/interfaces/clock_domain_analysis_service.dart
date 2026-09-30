// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:netcrux/domain/models/cdc/cdc_analysis_options.dart';
import 'package:netcrux/domain/models/cdc/cdc_analysis_result.dart';
import 'package:netcrux/domain/models/cdc/cdc_crossing.dart';

/// Extension-point service powering the CDC visualization.
///
/// Walks the elaborated netlist to find clock domains and the signals
/// that cross between them, classifies each crossing's
/// synchronizer-status and severity, and emits a structured
/// [CdcAnalysisResult].
///
/// **Open-core ships [NoopClockDomainAnalysisService]** as the
/// registered default: `analyze` returns the empty result, per-signal
/// / per-domain queries return empty lists, and
/// `analysisInvalidated` never emits. The Pro overlay registers a
/// concrete `ProClockDomainAnalysisService` via `proOverrides` that
/// consumes the same elaborated netlist `loadedNetlistProvider`
/// produces and runs the full clock-domain + crossing detection
/// engine.
abstract interface class ClockDomainAnalysisService {
  /// Walks the netlist and returns the full CDC analysis result.
  ///
  /// Pass [CdcAnalysisOptions] to tune the analysis (scope filter,
  /// custom synchronizer patterns, severity floor); omit or pass
  /// [CdcAnalysisOptions.defaults] for the default behavior.
  ///
  /// Large designs (1k+ registers across 5 domains) should complete in
  /// under 2 s on a development workstation. Open-core's no-op
  /// resolves immediately.
  Future<CdcAnalysisResult> analyze({CdcAnalysisOptions? options});

  /// Focused query: every crossing the analyzer has detected whose
  /// `signalId` matches the given canonical signal identifier. Used
  /// by the schematic context menu's "Show CDC Crossings for This
  /// Signal" entry to scope the panel to a single net's crossings.
  ///
  /// Returns an empty list when no crossings involve the signal or
  /// when no analysis has been run yet.
  Future<List<CdcCrossing>> crossingsForSignal(String signalPath);

  /// Focused query: every crossing whose `sourceDomainId` or
  /// `destinationDomainId` matches the given domain id. Used by the
  /// panel's domain filter dropdown.
  Future<List<CdcCrossing>> crossingsForDomain(String domainId);

  /// Stream that emits when the underlying inputs to the most recent
  /// analysis change — typically because the loaded netlist was
  /// re-elaborated. The per-tab `perTabCdcAnalysisResultProvider`
  /// listens to this stream and re-runs analysis so the panel content
  /// stays in sync with the live design.
  ///
  /// Open-core's no-op default never emits.
  Stream<void> get analysisInvalidated;
}

/// Open-core default: returns an empty analysis result for every
/// request, returns empty lists for the per-signal / per-domain
/// queries, and never emits on [analysisInvalidated].
///
/// The open-core build registers this implementation and mounts nothing
/// over it: [CdcAnalysisPane] is mounted only by the Pro overlay. The
/// `showCdcAnalysisPane` / `runCdcAnalysis` /
/// `showCdcCrossingForSelectedSignal` actions stay discoverable in the menu
/// bar / palette, and an open-core build refuses them with a "requires
/// NetCrux Pro" notice; `clearCdcAnalysisSelection` is never gated and runs
/// the no-op opener.
class NoopClockDomainAnalysisService implements ClockDomainAnalysisService {
  /// Creates the no-op service.
  const NoopClockDomainAnalysisService();

  @override
  Future<CdcAnalysisResult> analyze({CdcAnalysisOptions? options}) async {
    return CdcAnalysisResult.empty;
  }

  @override
  Future<List<CdcCrossing>> crossingsForSignal(String signalPath) async {
    return const <CdcCrossing>[];
  }

  @override
  Future<List<CdcCrossing>> crossingsForDomain(String domainId) async {
    return const <CdcCrossing>[];
  }

  @override
  Stream<void> get analysisInvalidated => const Stream<void>.empty();
}
