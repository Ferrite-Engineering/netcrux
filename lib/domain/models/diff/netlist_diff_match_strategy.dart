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
  /// Match elements with the same hierarchical name. Two elements with
  /// different names never match — additions and removals fall out
  /// naturally from the keyset difference. This is the v1 default.
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
