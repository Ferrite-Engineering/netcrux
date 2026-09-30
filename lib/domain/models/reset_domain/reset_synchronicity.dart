// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// IEEE 1850 SAS classification of a reset's assert / deassert
/// synchronicity relative to the clock that samples it.
///
/// This is the headline correctness claim of the reset domain
/// visualization feature — every reset domain carries one of these
/// values, and the synchronizer-status of crossings is interpreted
/// against this classification.
enum ResetSynchronicity {
  /// Asynchronous assert + asynchronous deassert. Reset is applied and
  /// removed without regard to the clock edge. Common in simple designs
  /// where reset is held active long enough for downstream logic to
  /// settle, but the deassert edge is a metastability hazard if it
  /// arrives mid-cycle.
  asyncAssertAsyncDeassert,

  /// Asynchronous assert + synchronous deassert. The most common
  /// pattern in real SoCs — register reset ports are wired async, and
  /// a 2-flop synchronizer aligns the deassert edge with the receiving
  /// clock domain. Safest practical choice for most designs.
  asyncAssertSyncDeassert,

  /// Synchronous assert + synchronous deassert. Reset is applied and
  /// removed only on a clock edge. Requires the clock to be running
  /// when reset is asserted, so unsuitable for power-on reset of the
  /// clocking infrastructure itself.
  syncAssertSyncDeassert,

  /// Detector could not classify the synchronicity (conflicting
  /// evidence in the netlist, or the reset feeds registers via paths
  /// that don't match any of the known patterns).
  unknown;

  /// Stable JSON tag used by fixture round-trip.
  String toJsonString() => name;

  /// Parses [raw] into a [ResetSynchronicity]. Unknown values map to
  /// [unknown] for forward compatibility.
  static ResetSynchronicity fromJsonString(String raw) {
    for (final v in ResetSynchronicity.values) {
      if (v.name == raw) return v;
    }
    return ResetSynchronicity.unknown;
  }
}
