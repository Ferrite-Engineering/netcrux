// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Classification of how a reset crossing was synchronized — the
/// safety posture of the design at this reset crossing point.
///
/// Paired with [ResetCrossingKind] and [ResetPolarity] it determines
/// the [ResetSeverity] of the crossing via the deterministic
/// `(crossingKind × synchronizerStatus × polarity)` matrix documented
/// in [ResetCrossing.severityFor].
enum ResetSynchronizerStatus {
  /// Classic async-assert + sync-deassert reset synchronizer — the
  /// most common and safest pattern in real SoCs. Two flip-flops in
  /// the destination domain on the deassertion path; the assert path
  /// is async because reset must apply even when the destination
  /// clock is not running.
  properAsyncAssertSyncDeassert,

  /// Synchronous-assert + synchronous-deassert reset synchronizer.
  /// Less common but valid; requires the destination clock to be
  /// running when reset is asserted, so unsuitable for power-on reset
  /// of the clocking infrastructure itself.
  properSyncAssertSyncDeassert,

  /// Crossing runs through a vendor-specific reset synchronizer cell
  /// or a library reset-synchronizer macro. The detector trusts the
  /// vendor's assertion that the cell synchronizes the reset
  /// correctly.
  properResetSynchronizer,

  /// Crossing runs through a user-asserted custom synchronizer
  /// module — its name matches a user-provided pattern (via
  /// [ResetDomainAnalysisOptions.userSynchronizerPatterns]).
  customSynchronizer,

  /// Crossing has no synchronizer on the destination side — the reset
  /// edge reaches register reset ports (or downstream data paths)
  /// without any synchronization. Critical metastability bug for
  /// resetDeassertCrossing; critical or warning for
  /// dataCrossesResetBoundary depending on detector confidence.
  missingSynchronizer,

  /// Synchronizer is structurally present but combinational logic in
  /// the deassertion path could cause glitches (e.g. AND-gating the
  /// synchronized reset with another signal, or routing through a
  /// mux). Warning class — the deassert edge may not be cleanly
  /// rising.
  ///
  /// Part of the severity vocabulary and rendered wherever a status is
  /// shown, but no analyzer emits it today: chain walks follow direct
  /// Q→D register hops, so a combinational cell between flops
  /// terminates the chain instead of classifying it. Detecting it needs
  /// a combinational-path check that has not been built.
  glitchProne;

  /// Stable JSON tag used by fixture round-trip.
  String toJsonString() => name;

  /// Parses [raw] into a [ResetSynchronizerStatus]. Unknown values map
  /// to [missingSynchronizer] for forward compatibility — most
  /// conservative default that surfaces unknown classifications as
  /// critical.
  static ResetSynchronizerStatus fromJsonString(String raw) {
    for (final v in ResetSynchronizerStatus.values) {
      if (v.name == raw) return v;
    }
    return ResetSynchronizerStatus.missingSynchronizer;
  }
}
