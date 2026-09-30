// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Classification of how a reset signal was sourced — the "where did
/// this reset come from?" attribute the detector attaches to every
/// [ResetDomain].
///
/// The detector classifies each candidate reset by walking the driver
/// of its primary net and matching the structural pattern. Unrecognised
/// patterns fall through to [unknown].
enum ResetSourceKind {
  /// Reset is sourced from a top-level module-boundary input port. The
  /// most common case — board-level reset signals feeding the FPGA /
  /// ASIC.
  primaryInput,

  /// Reset is sourced from a power-on-reset cell or counter that
  /// generates a deassert pulse after a configurable delay. Detected
  /// by driver naming patterns (`*_por*`, `por_*`, `power_on_reset`,
  /// `*ResetGen*`) or by counter-feedback structural shapes.
  powerOnReset,

  /// Reset is sourced from a register whose data input is software-
  /// writable. Detected when the driver is a flip-flop whose D input
  /// traces back to a CSR / register-bank write path.
  softwareTriggered,

  /// Reset is sourced from a 2:1 (or wider) mux that selects between
  /// multiple upstream reset sources at runtime — typically the
  /// power-on reset OR the software-triggered reset.
  resetMux,

  /// Reset is sourced from a divider / counter feedback loop. Less
  /// common than power-on reset but a real pattern in designs that
  /// generate a slower reset domain from a faster clock.
  divider,

  /// Detector could not classify the source. Most likely the reset
  /// arrives through user-defined glue logic the heuristics don't
  /// match.
  unknown;

  /// Stable JSON tag used by fixture round-trip.
  String toJsonString() => name;

  /// Parses [raw] into a [ResetSourceKind]. Unknown values map to
  /// [unknown] for forward compatibility.
  static ResetSourceKind fromJsonString(String raw) {
    for (final v in ResetSourceKind.values) {
      if (v.name == raw) return v;
    }
    return ResetSourceKind.unknown;
  }
}
