// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Heuristic classification of how an FSM's state register encodes its
/// discrete states. Inferred by [FsmDetectionService] from the set of
/// observed state values plus the structural shape of the driving
/// next-state logic.
///
/// Used by:
///
///   * The bubble diagram chrome to label the FSM's encoding scheme.
///   * The detector itself to validate optimisation hints (e.g. catching
///     a register the user *thinks* is one-hot but is actually binary).
///
/// The values are deliberately ordered from most-restrictive to
/// least-restrictive so the picker in the detection-results dialog can
/// surface stricter classifications first.
enum FsmEncodingHint {
  /// Exactly one bit is set in every state value. Width equals state
  /// count. Common in low-power FSMs and in some FPGA tooling defaults
  /// because the next-state logic decomposes to a fan-in of AND gates.
  oneHot,

  /// State values form a contiguous range starting at zero (0, 1, 2,
  /// 3, …). The default encoding most synthesizers emit when given no
  /// explicit hint.
  binary,

  /// Adjacent state values differ by exactly one bit. Reduces glitching
  /// on the state register at the expense of larger next-state logic.
  /// Common in metastability-sensitive designs.
  gray,

  /// Rotating bit pattern (the bit shifts left by one each transition,
  /// wrapping at the top). Common in counters and synchronous FIFOs.
  johnson,

  /// Encoding could not be classified — neither one-hot, binary, gray
  /// nor johnson fit the observed state set. The bubble diagram still
  /// renders; the encoding badge surfaces "Unknown" so the user knows
  /// the detector wasn't sure.
  unknown,
}
