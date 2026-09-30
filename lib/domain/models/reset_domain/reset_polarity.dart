// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Polarity of a reset signal — which logical level holds the design
/// in reset.
///
/// Detected from naming conventions (e.g. `_n` / `_N` suffix → active
/// low) and structural evidence (presence of a NOT gate in the driver
/// chain to the register reset port). The naming convention is
/// authoritative when present; structural evidence is secondary.
/// Conflicting evidence falls back to [unknown] with a diagnostic.
enum ResetPolarity {
  /// Reset asserts on a logical high (`1`). Default when no `_n` suffix
  /// and no structural inversion is observed.
  activeHigh,

  /// Reset asserts on a logical low (`0`). Detected via `_n` / `_N` /
  /// `_rstn` / `_resetn` naming suffixes, or via a NOT gate in the
  /// driver chain.
  activeLow,

  /// Detector could not classify the polarity (conflicting evidence,
  /// or a signal that doesn't match any known convention).
  unknown;

  /// Stable JSON tag used by fixture round-trip.
  String toJsonString() => name;

  /// Parses [raw] into a [ResetPolarity]. Unknown values map to
  /// [unknown] for forward compatibility.
  static ResetPolarity fromJsonString(String raw) {
    for (final v in ResetPolarity.values) {
      if (v.name == raw) return v;
    }
    return ResetPolarity.unknown;
  }
}
