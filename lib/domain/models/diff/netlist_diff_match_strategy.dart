// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Strategy used by a [NetlistDiffService] to match elements between two
/// netlists.
///
/// V1 of the diff engine implements [exactNameMatch] only. The other two
/// values are reserved for future fuzzy / structural matching and are
/// surfaced here so the v1 [NetlistDiffRequest] API is forward-compatible.
///
/// A Pro service that does not implement a strategy throws
/// [UnsupportedError] when asked for it.
enum NetlistDiffMatchStrategy {
  /// Match user-named elements by their exact name, and Yosys-generated
  /// ones (names starting with `$`) by structure. This is the default.
  ///
  /// A user-named module, cell, net or port with no namesake on the other
  /// side is added or removed. A generated name embeds the source path,
  /// the line and a running counter, so it is no identity: the same `$add`
  /// is renamed by any edit that moves its line, and differs between two
  /// files outright. Generated cells and nets are therefore paired by type,
  /// parameters and their connections to named nets and ports, refined
  /// through chains of generated cells; only what stays unpaired is added
  /// or removed.
  exactNameMatch,

  /// Reserved for v2: match elements by name with Levenshtein /
  /// substring tolerance to recognise minor renames as modifications.
  /// V1 services throw [UnsupportedError].
  fuzzyNameMatch,

  /// Reserved for v2: match elements by their structural fingerprint
  /// (port shape, immediate fan-in/fan-out) so a renamed instance with
  /// otherwise identical structure is recognised as a modification, not
  /// an add + remove pair. V1 services throw [UnsupportedError].
  structuralFingerprint,
}
