// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Three-level severity for a [ResetCrossing], derived deterministically
/// from the `(crossingKind × synchronizerStatus × polarity)` matrix in
/// `ResetCrossing.severityFor`.
///
/// Used by the panel's severity filter chips and the per-row severity
/// icon coloring.
enum ResetSeverity {
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

  /// Parses [raw] into a [ResetSeverity]. Unknown values map to
  /// [warning] for forward compatibility — a middle-ground default
  /// that doesn't silently hide bugs or over-warn.
  static ResetSeverity fromJsonString(String raw) {
    for (final v in ResetSeverity.values) {
      if (v.name == raw) return v;
    }
    return ResetSeverity.warning;
  }
}

/// Confidence the detector has in a given reset crossing's
/// classification.
///
/// Reported alongside [ResetSeverity] so power users can see which
/// findings the heuristics nailed and which deserve a manual look.
enum ResetConfidence {
  /// Classification is structurally unambiguous — the path matches a
  /// known signature exactly.
  high,

  /// Classification is best-guess from heuristics. Worth manual
  /// review.
  medium,

  /// Classification is borderline or the detector bailed at a
  /// configurable max-depth. Treat as a candidate to investigate.
  low;

  /// Stable JSON tag used by fixture round-trip.
  String toJsonString() => name;

  /// Parses [raw] into a [ResetConfidence]. Unknown values map to
  /// [medium] for forward compatibility.
  static ResetConfidence fromJsonString(String raw) {
    for (final v in ResetConfidence.values) {
      if (v.name == raw) return v;
    }
    return ResetConfidence.medium;
  }
}
