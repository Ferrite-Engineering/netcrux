// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:netcrux/domain/models/reset_domain/reset_crossing.dart';
import 'package:netcrux/domain/models/reset_domain/reset_domain.dart';
import 'package:netcrux/domain/models/reset_domain/reset_severity.dart';
import 'package:netcrux/domain/models/reset_domain/unreset_register.dart';

/// Aggregated result of a [ResetDomainAnalysisService.analyze] call.
///
/// Carries three primary lists plus an analysis-duration field useful
/// for perf-budget tracking:
///
///   * [detectedDomains] — every reset domain the detector recovered.
///   * [detectedCrossings] — every signal crossing between distinct
///     reset domains the analyzer found.
///   * [analysisDiagnostics] — free-form English diagnostic lines the
///     analyzer emitted while walking the netlist. Displayed in the
///     panel's diagnostics expander so power users can audit why a
///     borderline crossing got the classification it did.
@immutable
class ResetDomainAnalysisResult {
  /// Creates an analysis result.
  const ResetDomainAnalysisResult({
    required this.detectedDomains,
    required this.detectedCrossings,
    required this.analysisDiagnostics,
    required this.analysisDuration,
    this.unresetRegisters = const <UnresetRegister>[],
  });

  /// JSON round-trip constructor.
  factory ResetDomainAnalysisResult.fromJson(Map<String, Object?> json) {
    final domainsRaw = json['detectedDomains'];
    final crossingsRaw = json['detectedCrossings'];
    final diagnosticsRaw = json['analysisDiagnostics'];
    final durationMicros =
        (json['analysisDurationMicros'] as num?)?.toInt() ?? 0;
    return ResetDomainAnalysisResult(
      detectedDomains: domainsRaw is List
          ? <ResetDomain>[
              for (final d in domainsRaw)
                if (d is Map<String, Object?>) ResetDomain.fromJson(d),
            ]
          : const <ResetDomain>[],
      detectedCrossings: crossingsRaw is List
          ? <ResetCrossing>[
              for (final c in crossingsRaw)
                if (c is Map<String, Object?>) ResetCrossing.fromJson(c),
            ]
          : const <ResetCrossing>[],
      analysisDiagnostics: diagnosticsRaw is List
          ? <String>[for (final d in diagnosticsRaw) d.toString()]
          : const <String>[],
      analysisDuration: Duration(microseconds: durationMicros),
      unresetRegisters: json['unresetRegisters'] is List
          ? <UnresetRegister>[
              for (final u in json['unresetRegisters']! as List)
                if (u is Map<String, Object?>) UnresetRegister.fromJson(u),
            ]
          : const <UnresetRegister>[],
    );
  }

  /// Canonical empty result. Used by [NoopResetDomainAnalysisService]
  /// and by widgets rendering their empty state.
  static const ResetDomainAnalysisResult empty = ResetDomainAnalysisResult(
    detectedDomains: <ResetDomain>[],
    detectedCrossings: <ResetCrossing>[],
    analysisDiagnostics: <String>[],
    analysisDuration: Duration.zero,
  );

  /// All reset domains detected during analysis.
  final List<ResetDomain> detectedDomains;

  /// All domain-crossings detected during analysis.
  final List<ResetCrossing> detectedCrossings;

  /// Registers with no reset (`X` at power-up) found during analysis.
  /// Reported alongside the crossings as a distinct warning-severity
  /// finding class; empty when the design has no reset domains or every
  /// flop is reset.
  final List<UnresetRegister> unresetRegisters;

  /// Free-form English diagnostics emitted by the analyzer.
  final List<String> analysisDiagnostics;

  /// Wall-clock duration the analysis pass took. Surfaced in the panel
  /// footer for performance tracking.
  final Duration analysisDuration;

  /// True when the analyzer found no domains *and* no crossings — the
  /// design either has only one reset domain (and so no crossings) or
  /// no recognizable resets at all.
  bool get isEmpty => detectedDomains.isEmpty && detectedCrossings.isEmpty;

  /// Number of crossings at [ResetSeverity.critical]. Used by the
  /// panel header summary chip ("3 critical / 5 warnings / 2 info").
  int get criticalCount => _countBySeverity(ResetSeverity.critical);

  /// Number of crossings at [ResetSeverity.warning].
  int get warningCount => _countBySeverity(ResetSeverity.warning);

  /// Number of crossings at [ResetSeverity.info].
  int get infoCount => _countBySeverity(ResetSeverity.info);

  int _countBySeverity(ResetSeverity s) {
    var count = 0;
    for (final c in detectedCrossings) {
      if (c.severity == s) count++;
    }
    return count;
  }

  /// Convenience lookup: domain by [ResetDomain.id], or null.
  ResetDomain? domainById(String id) {
    for (final d in detectedDomains) {
      if (d.id == id) return d;
    }
    return null;
  }

  /// Convenience lookup: crossing by [ResetCrossing.id], or null.
  ResetCrossing? crossingById(String id) {
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
    'unresetRegisters': <Map<String, Object?>>[
      for (final u in unresetRegisters) u.toJson(),
    ],
    'analysisDiagnostics': analysisDiagnostics,
    'analysisDurationMicros': analysisDuration.inMicroseconds,
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ResetDomainAnalysisResult) return false;
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
    if (unresetRegisters.length != other.unresetRegisters.length) return false;
    for (var i = 0; i < unresetRegisters.length; i++) {
      if (unresetRegisters[i] != other.unresetRegisters[i]) return false;
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
    Object.hashAll(unresetRegisters),
    Object.hashAll(analysisDiagnostics),
    analysisDuration,
  );

  @override
  String toString() =>
      'ResetDomainAnalysisResult('
      '${detectedDomains.length} domains, '
      '${detectedCrossings.length} crossings '
      '[$criticalCount critical, $warningCount warnings, $infoCount info], '
      '${unresetRegisters.length} unreset registers, '
      '${analysisDiagnostics.length} diagnostics, '
      'duration ${analysisDuration.inMilliseconds}ms)';
}
