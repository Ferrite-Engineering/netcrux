// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Three-level severity for a [CdcCrossing], derived deterministically
/// from the `(crossingKind × synchronizerStatus)` matrix in
/// `CdcCrossing.severityFor`.
///
/// Used by the panel's severity filter chips and the graph canvas's
/// arrow-color encoding.
enum CdcSeverity {
  /// Critical bug — almost certainly broken silicon if shipped. The
  /// panel paints these red.
  critical,

  /// Warning — design is technically safe but fragile or non-idiomatic.
  /// The panel paints these amber.
  warning,

  /// Informational — the crossing is fine and well-handled, surfaced
  /// only for completeness. The panel paints these green.
  info;

  /// Stable JSON tag used by fixture round-trip.
  String toJsonString() => name;

  /// Parses [raw] into a [CdcSeverity]. Unknown values map to [warning]
  /// for forward compatibility — a middle-ground default that doesn't
  /// silently hide bugs or over-warn.
  static CdcSeverity fromJsonString(String raw) {
    for (final v in CdcSeverity.values) {
      if (v.name == raw) return v;
    }
    return CdcSeverity.warning;
  }
}

/// Confidence the detector has in a given crossing's classification.
///
/// Reported alongside [CdcSeverity] so power users can see which
/// findings the heuristics nailed and which deserve a manual look.
enum CdcConfidence {
  /// Classification is structurally unambiguous — the path matches a
  /// known signature exactly.
  high,

  /// Classification is best-guess from heuristics. Worth manual review.
  medium,

  /// Classification is borderline or the detector bailed at a
  /// configurable max-depth. Treat as a candidate to investigate.
  low;

  /// Stable JSON tag used by fixture round-trip.
  String toJsonString() => name;

  /// Parses [raw] into a [CdcConfidence]. Unknown values map to
  /// [medium] for forward compatibility.
  static CdcConfidence fromJsonString(String raw) {
    for (final v in CdcConfidence.values) {
      if (v.name == raw) return v;
    }
    return CdcConfidence.medium;
  }
}
