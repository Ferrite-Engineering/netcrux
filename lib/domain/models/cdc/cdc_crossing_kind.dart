// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Classification of a CDC crossing by signal shape and protocol intent.
///
/// Used as one axis of the severity-derivation matrix (see
/// [CdcCrossing.severity]); paired with [CdcSynchronizerStatus] it
/// determines whether the crossing is critical, a warning, or just
/// informational.
enum CdcCrossingKind {
  /// Single-bit control or status flag crossing between domains. The
  /// canonical "well-known" CDC case — typically handled by a 2-flop
  /// synchronizer.
  singleBit,

  /// Multi-bit data bus crossing — the net is wider than one bit.
  /// Requires an async-FIFO, a gray-coded pointer scheme or a
  /// handshake-qualified capture to be safe; a naked 2-flop sync per
  /// bit is a bug. The detector does not recognise the gray-coded or
  /// handshake-qualified forms, so they classify here as well.
  multiBit,

  /// Enable / select style control signal, classified by name
  /// (`_en`, `_enable`, `_sel`, `_select`, `ctrl`). No partner signal
  /// is looked up.
  control,

  /// Signal named like half of a request/acknowledge or valid/ready
  /// pair (`_req`, `_ack`, `_valid`, `_ready`, or containing
  /// `handshake`). Classified by name alone: the detector does not
  /// pair the two directions, and [CdcCrossing.synchronizerInstances]
  /// carries the destination-side flop chain, never a partner.
  handshake;

  /// Stable JSON tag used by fixture round-trip.
  String toJsonString() => name;

  /// Parses [raw] into a [CdcCrossingKind]. Unknown values map to
  /// [singleBit] for forward compatibility (most permissive default).
  static CdcCrossingKind fromJsonString(String raw) {
    for (final v in CdcCrossingKind.values) {
      if (v.name == raw) return v;
    }
    return CdcCrossingKind.singleBit;
  }
}
