// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// Narrows a crossing-analysis pane (CDC or reset domain) to the
/// crossings one signal takes part in.
///
/// Set by "Show Crossings for This Signal" when the signal takes part in
/// more than one crossing; the panel shows a chip naming [label] whose
/// delete button drops the filter. [crossingIds] are ids in the result the
/// filter was built against: installing a result that lacks any of them
/// drops the filter rather than showing a partial list.
@immutable
class CrossingSignalFilter {
  /// Creates a filter showing only [crossingIds], described by [label].
  const CrossingSignalFilter({required this.label, required this.crossingIds});

  /// The signal the filter was built for, as the panel chip names it.
  final String label;

  /// Ids of the crossings the pane shows while the filter is active.
  final Set<String> crossingIds;

  /// Whether the crossing with [id] passes the filter.
  bool admits(String id) => crossingIds.contains(id);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! CrossingSignalFilter) return false;
    if (label != other.label) return false;
    if (crossingIds.length != other.crossingIds.length) return false;
    return crossingIds.every(other.crossingIds.contains);
  }

  @override
  int get hashCode => Object.hash(label, Object.hashAllUnordered(crossingIds));
}
