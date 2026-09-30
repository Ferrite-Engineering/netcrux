// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Classification of how a clock signal was sourced — the "where did this
/// clock come from?" attribute the detector attaches to every
/// [ClockDomain].
///
/// The detector classifies each candidate clock by walking the driver
/// of its primary net and matching the structural pattern. Unrecognised
/// patterns fall through to [unknown]; the user can always force a
/// classification via the analysis-options API if they know better.
enum ClockDomainSourceKind {
  /// Clock is sourced from a top-level module-boundary input port.
  /// The most common case — board-level oscillators feeding the FPGA.
  primaryInput,

  /// Clock is sourced from a PLL / clock-management-tile instance.
  /// Detected by the driving cell's `type` matching common PLL
  /// patterns (`PLL`, `*PLL*`, `*pll*`, `MMCM*`, `*Mmcm*`).
  pll,

  /// Clock is sourced from a gated-clock cell (AND-style enable, or
  /// vendor clock-gating primitive). The user-driven enable becomes
  /// part of the clock's effective frequency, but the *domain* identity
  /// is still the gated output.
  gatedClock,

  /// Clock is sourced from a 2:1 (or wider) mux that selects between
  /// upstream clocks at runtime. The mux output's domain identity is
  /// distinct from any of its inputs.
  clockMux,

  /// Clock is sourced from a counter / divider feedback loop. Detected
  /// when the driver chain contains an arithmetic primitive whose
  /// output feeds back into a register clocked by the same chain.
  divider,

  /// Detector could not classify the source. Most likely the clock
  /// arrives through user-defined glue logic the heuristics don't
  /// match.
  unknown;

  /// Stable JSON tag used by fixture round-trip.
  String toJsonString() => name;

  /// Parses [raw] into a [ClockDomainSourceKind]. Unknown values map
  /// to [unknown] for forward compatibility.
  static ClockDomainSourceKind fromJsonString(String raw) {
    for (final v in ClockDomainSourceKind.values) {
      if (v.name == raw) return v;
    }
    return ClockDomainSourceKind.unknown;
  }
}
