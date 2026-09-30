// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:netcrux/domain/models/reset_domain/reset_crossing.dart';
import 'package:netcrux/domain/models/reset_domain/reset_domain_analysis_options.dart';
import 'package:netcrux/domain/models/reset_domain/reset_domain_analysis_result.dart';

/// Extension-point service powering the Reset Domain
/// visualization.
///
/// Walks the elaborated netlist to find reset domains and the signals
/// that cross between them, classifies each crossing's polarity,
/// synchronizer-status, and severity, and emits a structured
/// [ResetDomainAnalysisResult].
///
/// **Open-core ships [NoopResetDomainAnalysisService]** as the
/// registered default: `analyze` returns the empty result, per-signal
/// / per-domain queries return empty lists, and
/// `analysisInvalidated` never emits. The Pro overlay registers a
/// concrete `ProResetDomainAnalysisService` via `proOverrides` that
/// consumes the same elaborated netlist `loadedNetlistProvider`
/// produces and runs the full reset-domain + crossing detection
/// engine.
abstract interface class ResetDomainAnalysisService {
  /// Walks the netlist and returns the full reset-domain analysis
  /// result.
  ///
  /// Pass [ResetDomainAnalysisOptions] to tune the analysis (scope
  /// filter, custom synchronizer patterns, severity floor); omit or
  /// pass [ResetDomainAnalysisOptions.defaults] for the default
  /// behavior.
  ///
  /// Large designs (1k+ registers across 5 reset domains) should
  /// complete in under 2 s on a development workstation. Open-core's
  /// no-op resolves immediately.
  Future<ResetDomainAnalysisResult> analyze({
    ResetDomainAnalysisOptions? options,
  });

  /// Focused query: every crossing the analyzer has detected whose
  /// `signalId` matches the given canonical signal identifier. Used
  /// by the schematic context menu's "Show Reset Crossings for This
  /// Signal" entry to scope the panel to a single net's crossings.
  ///
  /// Returns an empty list when no crossings involve the signal or
  /// when no analysis has been run yet.
  Future<List<ResetCrossing>> crossingsForSignal(String signalPath);

  /// Focused query: every crossing whose `sourceDomainId` or
  /// `destinationDomainId` matches the given reset domain id. Used by
  /// the panel's domain filter dropdown.
  Future<List<ResetCrossing>> crossingsForDomain(String domainId);

  /// Stream that emits when the underlying inputs to the most recent
  /// analysis change — typically because the loaded netlist was
  /// re-elaborated. The per-tab
  /// `perTabResetDomainAnalysisResultProvider` listens to this stream
  /// and re-runs analysis so the panel content stays in sync with the
  /// live design.
  ///
  /// Open-core's no-op default never emits.
  Stream<void> get analysisInvalidated;
}

/// Open-core default: returns an empty analysis result for every
/// request, returns empty lists for the per-signal / per-domain
/// queries, and never emits on [analysisInvalidated].
///
/// The open-core build registers this implementation and mounts nothing
/// over it: [ResetDomainAnalysisPane] is mounted only by the Pro overlay.
/// The `showResetDomainAnalysisPane` / `runResetDomainAnalysis` /
/// `showResetCrossingForSelectedSignal` actions stay discoverable in the
/// menu bar / palette, and an open-core build refuses them with a "requires
/// NetCrux Pro" notice; `clearResetAnalysisSelection` is never gated and
/// runs the no-op opener.
class NoopResetDomainAnalysisService implements ResetDomainAnalysisService {
  /// Creates the no-op service.
  const NoopResetDomainAnalysisService();

  @override
  Future<ResetDomainAnalysisResult> analyze({
    ResetDomainAnalysisOptions? options,
  }) async {
    return ResetDomainAnalysisResult.empty;
  }

  @override
  Future<List<ResetCrossing>> crossingsForSignal(String signalPath) async {
    return const <ResetCrossing>[];
  }

  @override
  Future<List<ResetCrossing>> crossingsForDomain(String domainId) async {
    return const <ResetCrossing>[];
  }

  @override
  Stream<void> get analysisInvalidated => const Stream<void>.empty();
}
