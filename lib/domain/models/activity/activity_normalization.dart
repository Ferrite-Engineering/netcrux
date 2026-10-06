// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// How a [NetActivity.activityScore] is normalized to its 0.0..1.0
/// range from the raw per-net transition count.
///
/// Every mode normalizes the data nets only: a net the analyzer
/// identified as a clock (`NetActivity.isClock`) is left out of the
/// range, because a clock is nearly always the busiest net by far and
/// would otherwise take the whole scale.
///
/// The choice trades off interpretability vs. visual differentiation
/// between busy and idle nets:
///
/// * [rank] (the default) orders the distinct transition counts and
///   spaces them evenly over the scale: the quietest count scores 0.0,
///   the busiest 1.0, and nets with equal counts score alike. Every
///   level of activity in the design gets its own color however the
///   counts are spread, so a few busy nets cannot flatten the rest. The
///   cost is magnitude: 2 versus 1000 transitions reads the same as 2
///   versus 3, which is why the panel lists the counts beside the
///   colors.
/// * [perNet] scales each net linearly against the *maximum transition
///   count observed in the analysis result*. The hottest net always
///   renders at 1.0; everything else falls on a linear gradient below
///   it. Easy to read, but a single outlier net pins everything else
///   near 0.
/// * [globalMax] is an alias for [perNet]; explicit for callers that
///   want the "denominate by max observed" semantics without inferring
///   from the name.
/// * [logScale] applies `log(1 + count) / log(1 + maxCount)` so nets
///   that switch a few times become visible above the noise floor, at
///   the cost of crowding the low counts into the upper half.
enum ActivityNormalization {
  /// Linear scale against the maximum observed transition count.
  perNet,

  /// Alias for [perNet]; see the enum doc. Distinct enum value so a
  /// dropdown can surface "Global max" as a familiar label.
  globalMax,

  /// Log scale against the maximum observed transition count.
  /// Visible separation between low-activity nets at the cost of
  /// numeric interpretability.
  logScale,

  /// Dense rank of the net's transition count among the distinct counts
  /// observed, spaced evenly over `[0.0, 1.0]`. The default.
  rank;

  /// Stable JSON tag.
  String toJsonString() => name;

  /// Parses a tag back to a value. Unknown maps to [rank], the default.
  static ActivityNormalization fromJsonString(String raw) {
    for (final n in ActivityNormalization.values) {
      if (n.name == raw) return n;
    }
    return ActivityNormalization.rank;
  }
}
