// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:netcrux/domain/models/cdc/cdc_crossing.dart';
import 'package:netcrux/domain/models/cdc/cdc_severity.dart';
import 'package:netcrux/domain/models/cdc/clock_domain.dart';

/// Aggregated result of a [ClockDomainAnalysisService.analyze] call.
///
/// Carries three primary lists plus an analysis-duration field useful
/// for perf-budget tracking:
///
///   * [detectedDomains] — every clock domain the detector recovered.
///   * [detectedCrossings] — every signal crossing between distinct
///     domains the analyzer found.
///   * [analysisDiagnostics] — free-form English diagnostic lines the
///     analyzer emitted while walking the netlist. Displayed in the
///     panel's diagnostics expander so power users can audit why a
///     borderline crossing got the classification it did.
@immutable
class CdcAnalysisResult {
  /// Creates an analysis result.
  const CdcAnalysisResult({
    required this.detectedDomains,
    required this.detectedCrossings,
    required this.analysisDiagnostics,
    required this.analysisDuration,
  });

  /// JSON round-trip constructor.
  factory CdcAnalysisResult.fromJson(Map<String, Object?> json) {
    final domainsRaw = json['detectedDomains'];
    final crossingsRaw = json['detectedCrossings'];
    final diagnosticsRaw = json['analysisDiagnostics'];
    final durationMicros =
        (json['analysisDurationMicros'] as num?)?.toInt() ?? 0;
    return CdcAnalysisResult(
      detectedDomains: domainsRaw is List
          ? <ClockDomain>[
              for (final d in domainsRaw)
                if (d is Map<String, Object?>) ClockDomain.fromJson(d),
            ]
          : const <ClockDomain>[],
      detectedCrossings: crossingsRaw is List
          ? <CdcCrossing>[
              for (final c in crossingsRaw)
                if (c is Map<String, Object?>) CdcCrossing.fromJson(c),
            ]
          : const <CdcCrossing>[],
      analysisDiagnostics: diagnosticsRaw is List
          ? <String>[for (final d in diagnosticsRaw) d.toString()]
          : const <String>[],
      analysisDuration: Duration(microseconds: durationMicros),
    );
  }

  /// Canonical empty result. Used by [NoopClockDomainAnalysisService]
  /// and by widgets rendering their empty state.
  static const CdcAnalysisResult empty = CdcAnalysisResult(
    detectedDomains: <ClockDomain>[],
    detectedCrossings: <CdcCrossing>[],
    analysisDiagnostics: <String>[],
    analysisDuration: Duration.zero,
  );

  /// All clock domains detected during analysis.
  final List<ClockDomain> detectedDomains;

  /// All domain-crossings detected during analysis.
  final List<CdcCrossing> detectedCrossings;

  /// Free-form English diagnostics emitted by the analyzer.
  final List<String> analysisDiagnostics;

  /// Wall-clock duration the analysis pass took. Surfaced in the panel
  /// footer for performance tracking.
  final Duration analysisDuration;

  /// True when the analyzer found no domains *and* no crossings — the
  /// design either has only one domain (and so no crossings) or no
  /// recognizable clocks at all.
  bool get isEmpty => detectedDomains.isEmpty && detectedCrossings.isEmpty;

  /// Number of crossings at [CdcSeverity.critical]. Used by the panel
  /// header summary chip ("3 critical / 5 warnings / 2 info").
  int get criticalCount => _countBySeverity(CdcSeverity.critical);

  /// Number of crossings at [CdcSeverity.warning].
  int get warningCount => _countBySeverity(CdcSeverity.warning);

  /// Number of crossings at [CdcSeverity.info].
  int get infoCount => _countBySeverity(CdcSeverity.info);

  int _countBySeverity(CdcSeverity s) {
    var count = 0;
    for (final c in detectedCrossings) {
      if (c.severity == s) count++;
    }
    return count;
  }

  /// Convenience lookup: domain by [ClockDomain.id], or null.
  ClockDomain? domainById(String id) {
    for (final d in detectedDomains) {
      if (d.id == id) return d;
    }
    return null;
  }

  /// Convenience lookup: crossing by [CdcCrossing.id], or null.
  CdcCrossing? crossingById(String id) {
    for (final c in detectedCrossings) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// JSON map suitable for fixture round-trip.
  Map<String, Object?> toJson() => <String, Object?>{
    'detectedDomains': <Map<String, Object?>>[
      for (final d in detectedDomains) d.toJson(),
    ],
    'detectedCrossings': <Map<String, Object?>>[
      for (final c in detectedCrossings) c.toJson(),
    ],
    'analysisDiagnostics': analysisDiagnostics,
    'analysisDurationMicros': analysisDuration.inMicroseconds,
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! CdcAnalysisResult) return false;
    if (detectedDomains.length != other.detectedDomains.length) return false;
    for (var i = 0; i < detectedDomains.length; i++) {
      if (detectedDomains[i] != other.detectedDomains[i]) return false;
    }
    if (detectedCrossings.length != other.detectedCrossings.length) {
      return false;
    }
    for (var i = 0; i < detectedCrossings.length; i++) {
      if (detectedCrossings[i] != other.detectedCrossings[i]) return false;
    }
    if (analysisDiagnostics.length != other.analysisDiagnostics.length) {
      return false;
    }
    for (var i = 0; i < analysisDiagnostics.length; i++) {
      if (analysisDiagnostics[i] != other.analysisDiagnostics[i]) {
        return false;
      }
    }
    if (analysisDuration != other.analysisDuration) return false;
    return true;
  }

  @override
  int get hashCode => Object.hash(
    Object.hashAll(detectedDomains),
    Object.hashAll(detectedCrossings),
    Object.hashAll(analysisDiagnostics),
    analysisDuration,
  );

  @override
  String toString() =>
      'CdcAnalysisResult('
      '${detectedDomains.length} domains, '
      '${detectedCrossings.length} crossings '
      '[$criticalCount critical, $warningCount warnings, $infoCount info], '
      '${analysisDiagnostics.length} diagnostics, '
      'duration ${analysisDuration.inMilliseconds}ms)';
}
