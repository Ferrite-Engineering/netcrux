// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Classification of how a CDC crossing was synchronized — the safety
/// posture of the design at this crossing point.
///
/// Paired with [CdcCrossingKind] it determines the [CdcSeverity] of
/// the crossing via the deterministic
/// `(crossingKind × synchronizerStatus)` matrix documented in
/// [CdcCrossing.severityFor].
enum CdcSynchronizerStatus {
  /// Two flip-flops cascaded in the destination domain, no
  /// combinational logic between them. The canonical safe synchronizer
  /// for single-bit control flags.
  properTwoFlopSync,

  /// Three flip-flops cascaded ("paranoid" synchronizer). Marginally
  /// safer than 2-flop at the cost of one extra cycle latency; common
  /// in space / aerospace designs.
  properThreeFlopSync,

  /// The destination register's cell type or enclosing module name
  /// contains `FIFO`. A name match, reported at medium confidence; the
  /// detector does not verify the pointer scheme inside.
  asyncFifo,

  /// A data bus qualified by a separately synchronized request or
  /// valid, so the receiver samples it only once it is stable. **Never
  /// emitted by the shipped detector**: the enum value, the severity
  /// matrix column and the panel label exist, but no req/ack pairing
  /// produces it. Kept because the severity matrix, the panel and the
  /// fixture round-trip already cover it.
  handshakeProtocol,

  /// Crossing uses a custom synchronizer module whose name matches a
  /// user-provided pattern (via
  /// `CdcAnalysisOptions.userSynchronizerPatterns`). The detector
  /// trusts the user's assertion that the module synchronizes the
  /// signal correctly.
  customSynchronizer,

  /// Crossing has no synchronizer on the destination side — the signal
  /// is consumed by combinational logic directly. Critical metastability
  /// bug.
  missingSynchronizer,

  /// Exactly one destination-domain flop receives the crossing and no
  /// second stage follows it, so downstream logic can read the value
  /// before it has settled. Higher risk of metastability propagation
  /// than a properly-spaced design.
  metastable;

  /// Stable JSON tag used by fixture round-trip.
  String toJsonString() => name;

  /// Parses [raw] into a [CdcSynchronizerStatus]. Unknown values map to
  /// [missingSynchronizer] for forward compatibility (most conservative
  /// default — surfaces unknown classifications as critical).
  static CdcSynchronizerStatus fromJsonString(String raw) {
    for (final v in CdcSynchronizerStatus.values) {
      if (v.name == raw) return v;
    }
    return CdcSynchronizerStatus.missingSynchronizer;
  }
}
