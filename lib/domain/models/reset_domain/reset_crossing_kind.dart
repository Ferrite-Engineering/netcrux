// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Classification of a reset crossing by what specifically crosses
/// between the source and destination reset domains.
///
/// Used as one axis of the severity-derivation matrix (see
/// [ResetCrossing.severityFor]); paired with [ResetSynchronizerStatus]
/// and [ResetPolarity] it determines whether the crossing is critical,
/// a warning, or just informational.
enum ResetCrossingKind {
  /// A data signal driven by a register reset by domain A is consumed
  /// by a register reset by domain B. Without proper synchronization
  /// of the data on the boundary, the boundary register can sample a
  /// register caught mid-reset on the source side — corrupt or
  /// inconsistent values.
  dataCrossesResetBoundary,

  /// The reset deassert edge of one reset reaches registers in another
  /// reset domain. This is the canonical reset CDC bug — the deassert
  /// edge must be synchronized to prevent metastability propagation
  /// when registers in the destination domain release reset on a
  /// rising clock edge that happens to coincide with the deassert.
  /// The analyzer reports every reset-edge crossing under this kind:
  /// the deassert edge is the metastability hazard, and the structural
  /// signature (a reset port driven from another domain) cannot
  /// distinguish assert-only exposure.
  resetDeassertCrossing;

  /// Stable JSON tag used by fixture round-trip.
  String toJsonString() => name;

  /// Parses [raw] into a [ResetCrossingKind]. Unknown values map to
  /// [resetDeassertCrossing] for forward compatibility — the
  /// most-critical default surfaces unknown classifications as
  /// metastability hazards rather than silently downgrading them.
  static ResetCrossingKind fromJsonString(String raw) {
    for (final v in ResetCrossingKind.values) {
      if (v.name == raw) return v;
    }
    return ResetCrossingKind.resetDeassertCrossing;
  }
}
