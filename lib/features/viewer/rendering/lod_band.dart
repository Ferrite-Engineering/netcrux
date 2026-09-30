// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Level-of-detail bands the schematic painter switches between based
/// on the active viewport zoom.
///
/// The painter picks a band per frame from the current
/// [ViewportTransform.zoom]:
///
/// - [detail]     — zoom ≥ 0.75: symbol-library shapes, port labels,
///   wire labels.
/// - [mid]        — 0.25 ≤ zoom < 0.75: symbol shapes only (no labels),
///   simplified wires.
/// - [overview]   — zoom < 0.25: cells drawn as solid rectangles
///   colored by cell-type family, wires as thin uncolored lines.
///
/// Kept as an enum (not a sealed class) so the painter can `switch`
/// over it exhaustively. The breakpoint thresholds live on the enum
/// via [LodBandRouter] so they can be reused by tests.
enum LodBand {
  /// Full-detail rendering.
  detail,

  /// Mid-detail rendering.
  mid,

  /// Overview rendering.
  overview,
}

/// Maps a zoom value to its [LodBand].
///
/// Static-only utility class so the mapping is in one place and easy
/// to assert against in tests. The boundary cases use `>=` (inclusive
/// from the upper band) so the transition at exactly 0.75 / 0.25
/// stays deterministic.
abstract final class LodBandRouter {
  /// Upper boundary of the [LodBand.overview] band (exclusive).
  static const double overviewUpper = 0.25;

  /// Upper boundary of the [LodBand.mid] band (exclusive).
  static const double midUpper = 0.75;

  /// Returns the band the painter should use at [zoom].
  static LodBand bandFor(double zoom) {
    if (zoom >= midUpper) return LodBand.detail;
    if (zoom >= overviewUpper) return LodBand.mid;
    return LodBand.overview;
  }
}
