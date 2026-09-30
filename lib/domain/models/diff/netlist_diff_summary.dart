// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:netcrux/domain/models/diff/element_change.dart';
import 'package:netcrux/domain/models/diff/netlist_diff_element_kind.dart';

/// Per-elementKind counters used by [NetlistDiffSummary].
@immutable
class NetlistDiffKindCounts {
  /// Creates a per-elementKind count tuple.
  const NetlistDiffKindCounts({
    this.added = 0,
    this.removed = 0,
    this.modified = 0,
    this.unchanged = 0,
  });

  /// The empty / zero tuple.
  static const NetlistDiffKindCounts empty = NetlistDiffKindCounts();

  /// Number of `added` rows for the owning elementKind.
  final int added;

  /// Number of `removed` rows for the owning elementKind.
  final int removed;

  /// Number of `modified` rows for the owning elementKind.
  final int modified;

  /// Number of `unchanged` rows for the owning elementKind.
  final int unchanged;

  /// Total across the four buckets.
  int get total => added + removed + modified + unchanged;

  @override
  bool operator ==(Object other) =>
      other is NetlistDiffKindCounts &&
      other.added == added &&
      other.removed == removed &&
      other.modified == modified &&
      other.unchanged == unchanged;

  @override
  int get hashCode => Object.hash(added, removed, modified, unchanged);

  @override
  String toString() =>
      'NetlistDiffKindCounts(added: $added, removed: $removed, '
      'modified: $modified, unchanged: $unchanged)';
}

/// Cross-tabulated aggregate counts for a [NetlistDiff].
///
/// The (kind × elementKind) matrix tells consumers at a glance how
/// many elements of each category fell into each of the four buckets.
/// The summary header in the open-core [DiffPane] renders directly off
/// this object; the Pro `DiffPanePanel` uses it to populate filter-chip
/// counters.
///
/// [modificationIntensity] is a 0.0 – 1.0 scalar that quantifies how
/// different the two netlists are: 0.0 means identical (every common
/// element unchanged), 1.0 means completely different (every element
/// was added, removed, or modified). The score is `(changedCount /
/// totalCount)` where `changedCount = added + removed + modified` and
/// `totalCount = added + removed + modified + unchanged`. When both
/// netlists are empty the score is defined as 0.0 (an empty design is
/// trivially identical to another empty design).
@immutable
class NetlistDiffSummary {
  /// Creates a summary. All counts default to zero so callers can
  /// build the summary by mutation through [NetlistDiffSummary.from]
  /// and then freeze it.
  const NetlistDiffSummary({
    this.counts = const <NetlistDiffElementKind, NetlistDiffKindCounts>{},
  });

  /// Computes a summary from an [elementChanges] list. The list is
  /// walked once; counts are aggregated per (kind × elementKind).
  factory NetlistDiffSummary.from(Iterable<ElementChange> elementChanges) {
    final accum = <NetlistDiffElementKind, _MutableKindCounts>{};
    for (final change in elementChanges) {
      final bucket = accum.putIfAbsent(
        change.elementKind,
        _MutableKindCounts.new,
      );
      switch (change.kind) {
        case ElementChangeKind.added:
          bucket.added++;
        case ElementChangeKind.removed:
          bucket.removed++;
        case ElementChangeKind.modified:
          bucket.modified++;
        case ElementChangeKind.unchanged:
          bucket.unchanged++;
      }
    }
    return NetlistDiffSummary(
      counts: <NetlistDiffElementKind, NetlistDiffKindCounts>{
        for (final entry in accum.entries) entry.key: entry.value.freeze(),
      },
    );
  }

  /// JSON round-trip constructor.
  factory NetlistDiffSummary.fromJson(Map<String, Object?> json) {
    final out = <NetlistDiffElementKind, NetlistDiffKindCounts>{};
    for (final entry in json.entries) {
      final ek = NetlistDiffElementKind.values
          .where((k) => k.name == entry.key)
          .toList();
      if (ek.isEmpty) continue;
      final value = entry.value;
      if (value is! Map<String, Object?>) continue;
      out[ek.first] = NetlistDiffKindCounts(
        added: (value['added'] as num?)?.toInt() ?? 0,
        removed: (value['removed'] as num?)?.toInt() ?? 0,
        modified: (value['modified'] as num?)?.toInt() ?? 0,
        unchanged: (value['unchanged'] as num?)?.toInt() ?? 0,
      );
    }
    return NetlistDiffSummary(counts: out);
  }

  /// Per-elementKind counts. A missing key means zero of that kind.
  final Map<NetlistDiffElementKind, NetlistDiffKindCounts> counts;

  /// Convenience accessor: count of `added` rows for [kind].
  int added(NetlistDiffElementKind kind) => counts[kind]?.added ?? 0;

  /// Convenience accessor: count of `removed` rows for [kind].
  int removed(NetlistDiffElementKind kind) => counts[kind]?.removed ?? 0;

  /// Convenience accessor: count of `modified` rows for [kind].
  int modified(NetlistDiffElementKind kind) => counts[kind]?.modified ?? 0;

  /// Convenience accessor: count of `unchanged` rows for [kind].
  int unchanged(NetlistDiffElementKind kind) => counts[kind]?.unchanged ?? 0;

  /// Total across every elementKind for the four buckets.
  int get totalAdded => counts.values.fold(0, (s, c) => s + c.added);

  /// Sum of `removed` rows across every elementKind.
  int get totalRemoved => counts.values.fold(0, (s, c) => s + c.removed);

  /// Sum of `modified` rows across every elementKind.
  int get totalModified => counts.values.fold(0, (s, c) => s + c.modified);

  /// Sum of `unchanged` rows across every elementKind.
  int get totalUnchanged => counts.values.fold(0, (s, c) => s + c.unchanged);

  /// `added + removed + modified` — the number of rows that
  /// represent a divergence between baseline and comparison.
  int get totalChanged => totalAdded + totalRemoved + totalModified;

  /// `added + removed + modified + unchanged`.
  int get totalElements => totalChanged + totalUnchanged;

  /// 0.0 – 1.0 modification intensity. `0.0` when the two netlists are
  /// identical (or both empty), `1.0` when every element diverges.
  double get modificationIntensity {
    final total = totalElements;
    if (total == 0) return 0;
    return totalChanged / total;
  }

  /// JSON map suitable for fixture serialization.
  Map<String, Object?> toJson() => <String, Object?>{
    for (final entry in counts.entries)
      entry.key.name: <String, Object?>{
        'added': entry.value.added,
        'removed': entry.value.removed,
        'modified': entry.value.modified,
        'unchanged': entry.value.unchanged,
      },
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! NetlistDiffSummary) return false;
    if (other.counts.length != counts.length) return false;
    for (final entry in counts.entries) {
      if (other.counts[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode {
    var hash = 0;
    for (final entry in counts.entries) {
      hash ^= Object.hash(entry.key, entry.value);
    }
    return hash;
  }

  @override
  String toString() =>
      'NetlistDiffSummary(added: $totalAdded, removed: $totalRemoved, '
      'modified: $totalModified, unchanged: $totalUnchanged, '
      'intensity: ${modificationIntensity.toStringAsFixed(3)})';
}

class _MutableKindCounts {
  int added = 0;
  int removed = 0;
  int modified = 0;
  int unchanged = 0;

  NetlistDiffKindCounts freeze() => NetlistDiffKindCounts(
    added: added,
    removed: removed,
    modified: modified,
    unchanged: unchanged,
  );
}
