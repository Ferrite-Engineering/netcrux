// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// Direction of a one-step trace overlay.
enum TraceOverlayMode {
  /// Fanin: highlight drivers of the selected element.
  fanin,

  /// Fanout: highlight loads of the selected element.
  fanout,
}

/// Snapshot of which elements the fanin / fanout overlay should
/// highlight on the next paint.
///
/// All other elements are dimmed at paint time. An [TraceOverlay.empty]
/// snapshot means "no overlay active — paint everything normally".
@immutable
class TraceOverlay {
  /// Creates a trace overlay snapshot.
  const TraceOverlay({
    required this.mode,
    required this.highlightedCellIds,
    required this.highlightedEdgeIds,
    required this.highlightedBoundaryPortIds,
  });

  /// Empty overlay — paint normally.
  static const TraceOverlay empty = TraceOverlay(
    mode: null,
    highlightedCellIds: <String>{},
    highlightedEdgeIds: <String>{},
    highlightedBoundaryPortIds: <String>{},
  );

  /// Active mode — `null` when [isEmpty].
  final TraceOverlayMode? mode;

  /// Set of cell ids the painter should keep at full intensity.
  final Set<String> highlightedCellIds;

  /// Set of edge ids (from the laid-out graph) the painter should
  /// keep at full intensity.
  final Set<String> highlightedEdgeIds;

  /// Set of boundary-port ids the painter should keep at full
  /// intensity.
  final Set<String> highlightedBoundaryPortIds;

  /// True when no overlay is active.
  bool get isEmpty =>
      mode == null &&
      highlightedCellIds.isEmpty &&
      highlightedEdgeIds.isEmpty &&
      highlightedBoundaryPortIds.isEmpty;

  /// True when [id] is part of the highlighted cell set.
  bool highlightsCell(String id) => highlightedCellIds.contains(id);

  /// True when [id] is part of the highlighted edge set.
  bool highlightsEdge(String id) => highlightedEdgeIds.contains(id);

  /// True when [id] is part of the highlighted boundary-port set.
  bool highlightsBoundaryPort(String id) =>
      highlightedBoundaryPortIds.contains(id);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! TraceOverlay) return false;
    if (other.mode != mode) return false;
    if (other.highlightedCellIds.length != highlightedCellIds.length) {
      return false;
    }
    for (final id in highlightedCellIds) {
      if (!other.highlightedCellIds.contains(id)) return false;
    }
    if (other.highlightedEdgeIds.length != highlightedEdgeIds.length) {
      return false;
    }
    for (final id in highlightedEdgeIds) {
      if (!other.highlightedEdgeIds.contains(id)) return false;
    }
    if (other.highlightedBoundaryPortIds.length !=
        highlightedBoundaryPortIds.length) {
      return false;
    }
    for (final id in highlightedBoundaryPortIds) {
      if (!other.highlightedBoundaryPortIds.contains(id)) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    mode,
    Object.hashAllUnordered(highlightedCellIds),
    Object.hashAllUnordered(highlightedEdgeIds),
    Object.hashAllUnordered(highlightedBoundaryPortIds),
  );
}
