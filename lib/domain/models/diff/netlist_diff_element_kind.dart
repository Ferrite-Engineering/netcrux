// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// The kind of netlist element described by an [ElementChange].
///
/// Distinct from `package:crux_cxp`'s [ElementKind]: the cross-suite
/// [ElementKind] covers every Crux product's element vocabulary
/// (signals, scopes, rules, breakpoints, …), whereas
/// [NetlistDiffElementKind] only enumerates the four element categories
/// the diff engine compares within a NetCrux netlist. The narrower enum
/// keeps the diff summary's cross-tabulation tidy and lets the open-core
/// [DiffPane] render category-specific icons without translating from
/// CXP's broader vocabulary.
enum NetlistDiffElementKind {
  /// A cell instance — Yosys `cells.<name>`.
  instance,

  /// A named net (wire / signal) — Yosys `netnames.<name>`.
  net,

  /// A module-boundary port — Yosys `ports.<name>`.
  port,

  /// A whole module entry under Yosys's `modules.<name>`.
  module,
}
