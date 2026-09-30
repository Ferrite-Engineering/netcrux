// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:meta/meta.dart';
import 'package:netcrux/domain/models/fsm/fsm.dart';

/// Aggregated result of an [FsmDetectionService.detect] call.
///
/// Carries three lists:
///
///   * [detectedFsms] — registers that passed the structural-signature
///     filter *and* had a parseable transition graph. The bubble
///     diagram panel renders these directly.
///   * [candidateRegisters] — registers that *looked* FSM-shape but
///     couldn't be fully analysed (no parseable next-state logic,
///     ambiguous reset, width out of range). Surfaced in the detection
///     results dialog with a "Force detection" action that calls
///     `detectAt` to push past the structural filter.
///   * [detectionDiagnostics] — free-form English diagnostic lines the
///     detector emitted while walking the netlist. Displayed in the
///     results dialog's diagnostics expander so power users can audit
///     why a borderline register was rejected.
@immutable
class FsmDetectionResult {
  /// Creates a detection result.
  const FsmDetectionResult({
    required this.detectedFsms,
    required this.candidateRegisters,
    required this.detectionDiagnostics,
  });

  /// JSON round-trip constructor.
  factory FsmDetectionResult.fromJson(Map<String, Object?> json) {
    final fsmsRaw = json['detectedFsms'];
    final candidatesRaw = json['candidateRegisters'];
    final diagnosticsRaw = json['detectionDiagnostics'];
    return FsmDetectionResult(
      detectedFsms: fsmsRaw is List
          ? <Fsm>[
              for (final f in fsmsRaw)
                if (f is Map<String, Object?>) Fsm.fromJson(f),
            ]
          : const <Fsm>[],
      candidateRegisters: candidatesRaw is List
          ? <ElementId>[
              for (final c in candidatesRaw)
                if (c is Map<String, Object?>) ElementId.fromJson(c),
            ]
          : const <ElementId>[],
      detectionDiagnostics: diagnosticsRaw is List
          ? <String>[for (final d in diagnosticsRaw) d.toString()]
          : const <String>[],
    );
  }

  /// Canonical empty result. Used by [NoopFsmDetectionService] and
  /// by widgets rendering their empty state.
  static const FsmDetectionResult empty = FsmDetectionResult(
    detectedFsms: <Fsm>[],
    candidateRegisters: <ElementId>[],
    detectionDiagnostics: <String>[],
  );

  /// FSMs the detector fully analysed.
  final List<Fsm> detectedFsms;

  /// Registers that looked FSM-shape but couldn't be fully analysed.
  /// The "Force detection" action in the results dialog calls
  /// `detectAt` against these to bypass the structural-signature filter.
  final List<ElementId> candidateRegisters;

  /// Free-form English diagnostic lines emitted by the detector.
  final List<String> detectionDiagnostics;

  /// True when neither FSMs nor candidates were found. The results
  /// dialog renders its empty-state explainer.
  bool get isEmpty => detectedFsms.isEmpty && candidateRegisters.isEmpty;

  /// Convenience lookup: FSM with the given [id], or null.
  Fsm? fsmById(String id) {
    for (final f in detectedFsms) {
      if (f.id == id) return f;
    }
    return null;
  }

  /// JSON map suitable for fixture round-trip.
  Map<String, Object?> toJson() => <String, Object?>{
    'detectedFsms': <Map<String, Object?>>[
      for (final f in detectedFsms) f.toJson(),
    ],
    'candidateRegisters': <Map<String, Object?>>[
      for (final c in candidateRegisters) c.toJson(),
    ],
    'detectionDiagnostics': detectionDiagnostics,
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! FsmDetectionResult) return false;
    if (detectedFsms.length != other.detectedFsms.length) return false;
    for (var i = 0; i < detectedFsms.length; i++) {
      if (detectedFsms[i] != other.detectedFsms[i]) return false;
    }
    if (candidateRegisters.length != other.candidateRegisters.length) {
      return false;
    }
    for (var i = 0; i < candidateRegisters.length; i++) {
      if (candidateRegisters[i] != other.candidateRegisters[i]) return false;
    }
    if (detectionDiagnostics.length != other.detectionDiagnostics.length) {
      return false;
    }
    for (var i = 0; i < detectionDiagnostics.length; i++) {
      if (detectionDiagnostics[i] != other.detectionDiagnostics[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    Object.hashAll(detectedFsms),
    Object.hashAll(candidateRegisters),
    Object.hashAll(detectionDiagnostics),
  );

  @override
  String toString() =>
      'FsmDetectionResult('
      '${detectedFsms.length} detected, '
      '${candidateRegisters.length} candidates, '
      '${detectionDiagnostics.length} diagnostics)';
}
