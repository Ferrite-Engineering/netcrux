// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// How a [NetActivity.activityScore] is normalized to its 0.0..1.0
/// range from the raw per-net transition count.
///
/// The choice trades off interpretability vs. visual differentiation
/// between busy and idle nets:
///
/// * [perNet] — each net's score scales linearly against the *maximum
///   transition count observed in the analysis result*. The hottest
///   net always renders at 1.0; everything else falls on a linear
///   gradient below it. Easy to read, but a single outlier net (e.g.
///   the clock) pins everything else near 0.
/// * [globalMax] — alias for [perNet]; explicit for callers that want
///   the "denominate by max observed" semantics without inferring
///   from the name. Same math as [perNet]; kept distinct so the
///   panel's normalization dropdown surfaces a familiar label.
/// * [logScale] — applies `log(1 + count) / log(1 + maxCount)` so
///   nets that switch a few times become visible above the noise
///   floor. The clock still saturates at 1.0 but the low end isn't
///   crushed.
enum ActivityNormalization {
  /// Linear scale against the maximum observed transition count.
  perNet,

  /// Alias for [perNet] — see enum doc. Distinct enum value so the
  /// panel's dropdown can surface "Global max" as a familiar label.
  globalMax,

  /// Log scale against the maximum observed transition count.
  /// Visible separation between low-activity nets at the cost of
  /// numeric interpretability.
  logScale;

  /// Stable JSON tag.
  String toJsonString() => name;

  /// Parses a tag back to a value. Unknown maps to [perNet].
  static ActivityNormalization fromJsonString(String raw) {
    for (final n in ActivityNormalization.values) {
      if (n.name == raw) return n;
    }
    return ActivityNormalization.perNet;
  }
}
