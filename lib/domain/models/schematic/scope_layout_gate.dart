// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// The number of cells in a scope above which NetCrux waits to be asked
/// before laying the whole scope out.
///
/// Measured on synthetic standard-cell netlists with the native engine on a
/// 64 GB desktop: 21,000 cells lay out in 1.2 to 5 s using 1.3 to 1.9 GB,
/// 42,000 in 2.4 to 16 s using 2.4 to 4.3 GB, and 84,000 in 5 to 59 s using
/// 4.6 to 11.4 GB. The spread inside each size is the netlist's connectivity:
/// a wire that reaches far across the scope costs far more than a local one,
/// so the cell count alone bounds the cost only loosely. 40,000 keeps the
/// worst measured case near 16 s and 4.3 GB, which a typical laptop absorbs.
const int kDefaultLayoutCellLimit = 40000;

/// The memory, in bytes, that laying out one cell of a large scope is
/// assumed to need: the largest figure measured (11.4 GB for 84,444 cells,
/// the whole process including the design). It is an estimate to size a
/// decision by, not a promise.
const int kLayoutBytesPerCell = 130 * 1024;

/// The memory a whole-scope layout of [cellCount] cells is estimated to
/// need, in bytes.
int estimateLayoutBytes(int cellCount) => cellCount * kLayoutBytesPerCell;

/// Whether the whole of the scope on the canvas may be laid out now.
///
/// A scope with more than [limit] cells is not laid out when it is opened,
/// entered or restored: the canvas says so instead and offers the ways
/// forward. Reading the cell count of a scope costs nothing, so this is
/// decided before the schematic graph or the layout input is built.
///
/// A limit of `0` or less turns the guard off.
@immutable
class ScopeLayoutGate {
  /// Creates the gate for a scope of [cellCount] cells.
  const ScopeLayoutGate({
    required this.cellCount,
    required this.limit,
    this.approved = false,
    this.inCone = false,
  });

  /// No scope is selected, so there is nothing to hold back.
  static const ScopeLayoutGate none = ScopeLayoutGate(
    cellCount: 0,
    limit: kDefaultLayoutCellLimit,
  );

  /// Cells in the scope on the canvas.
  final int cellCount;

  /// Largest scope laid out without asking; `0` or less means no limit.
  final int limit;

  /// True once the user chose to lay this scope out anyway.
  final bool approved;

  /// True while the canvas shows a cone view of this scope, which lays out
  /// only the cone and so never needs the whole scope laid out.
  final bool inCone;

  /// True when the whole-scope layout must wait for the user.
  bool get deferred => limit > 0 && cellCount > limit && !approved && !inCone;

  /// The memory a whole-scope layout of this scope is estimated to need.
  int get estimatedBytes => estimateLayoutBytes(cellCount);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ScopeLayoutGate &&
          other.cellCount == cellCount &&
          other.limit == limit &&
          other.approved == approved &&
          other.inCone == inCone);

  @override
  int get hashCode => Object.hash(cellCount, limit, approved, inCone);

  @override
  String toString() =>
      'ScopeLayoutGate($cellCount cells, limit $limit, '
      'approved: $approved, inCone: $inCone)';
}
