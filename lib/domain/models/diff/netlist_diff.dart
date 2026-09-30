// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:netcrux/domain/models/diff/element_change.dart';
import 'package:netcrux/domain/models/diff/netlist_diff_request.dart';
import 'package:netcrux/domain/models/diff/netlist_diff_summary.dart';

/// Result of a [NetlistDiffService.compare] call.
///
/// Carries the structured per-element change list, a precomputed
/// summary suitable for header rendering, and the baseline /
/// comparison netlist refs so the UI can show what was compared
/// without needing to re-thread the [NetlistDiffRequest].
///
/// Immutable — every Pro service call returns a fresh [NetlistDiff]
/// so the per-tab `activeDiffProvider` can publish it cheaply.
@immutable
class NetlistDiff {
  /// Creates a diff result. [summary] is normally computed via
  /// [NetlistDiffSummary.from] over [elementChanges]; passing it
  /// explicitly is allowed for tests / fixture deserialization.
  NetlistDiff({
    required this.baselineNetlist,
    required this.comparisonNetlist,
    required this.generatedAt,
    required this.elementChanges,
    NetlistDiffSummary? summary,
  }) : summary = summary ?? NetlistDiffSummary.from(elementChanges);

  /// Empty diff — used by [NoopNetlistDiffService] and as the initial
  /// value of [activeDiffProvider] when no comparison is active.
  factory NetlistDiff.empty() => NetlistDiff(
    baselineNetlist: const NetlistRef(identifier: '', displayLabel: ''),
    comparisonNetlist: const NetlistRef(identifier: '', displayLabel: ''),
    generatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    elementChanges: const <ElementChange>[],
  );

  /// JSON round-trip constructor.
  factory NetlistDiff.fromJson(Map<String, Object?> json) {
    final changesRaw = json['elementChanges'];
    final changes = <ElementChange>[];
    if (changesRaw is List) {
      for (final entry in changesRaw) {
        if (entry is Map<String, Object?>) {
          changes.add(ElementChange.fromJson(entry));
        }
      }
    }
    final summaryRaw = json['summary'];
    return NetlistDiff(
      baselineNetlist: NetlistRef.fromJson(
        json['baselineNetlist'] as Map<String, Object?>? ?? const {},
      ),
      comparisonNetlist: NetlistRef.fromJson(
        json['comparisonNetlist'] as Map<String, Object?>? ?? const {},
      ),
      generatedAt: DateTime.parse(
        json['generatedAt']?.toString() ?? '1970-01-01T00:00:00.000Z',
      ),
      elementChanges: changes,
      summary: summaryRaw is Map<String, Object?>
          ? NetlistDiffSummary.fromJson(summaryRaw)
          : null,
    );
  }

  /// The baseline netlist reference (input to [NetlistDiffService.compare]).
  final NetlistRef baselineNetlist;

  /// The comparison netlist reference.
  final NetlistRef comparisonNetlist;

  /// When the diff was computed. Surfaced in the panel footer.
  final DateTime generatedAt;

  /// Per-element changes, in arbitrary but stable order (the engine
  /// orders by element kind then element id so subsequent re-runs of
  /// the same comparison produce the same list).
  final List<ElementChange> elementChanges;

  /// Precomputed cross-tab summary. Always consistent with
  /// [elementChanges]: the open-core no-op service emits the empty
  /// diff with `NetlistDiffSummary.from(const [])` so callers don't
  /// have to special-case "no diff".
  final NetlistDiffSummary summary;

  /// True when this diff has no element changes (the empty case or
  /// two identical netlists where the engine chose not to emit
  /// `unchanged` rows). Distinct from [isIdentical] which checks the
  /// *content* of [summary], not its emptiness.
  bool get isEmpty => elementChanges.isEmpty;

  /// True when every element in the comparison matches the baseline
  /// — no rows fall into the `added` / `removed` / `modified`
  /// buckets, even if `unchanged` rows are present.
  bool get isIdentical =>
      summary.totalAdded == 0 &&
      summary.totalRemoved == 0 &&
      summary.totalModified == 0;

  /// Returns a copy with the given fields replaced.
  NetlistDiff copyWith({
    NetlistRef? baselineNetlist,
    NetlistRef? comparisonNetlist,
    DateTime? generatedAt,
    List<ElementChange>? elementChanges,
    NetlistDiffSummary? summary,
  }) {
    return NetlistDiff(
      baselineNetlist: baselineNetlist ?? this.baselineNetlist,
      comparisonNetlist: comparisonNetlist ?? this.comparisonNetlist,
      generatedAt: generatedAt ?? this.generatedAt,
      elementChanges: elementChanges ?? this.elementChanges,
      summary: summary ?? this.summary,
    );
  }

  /// JSON map suitable for fixture serialization.
  Map<String, Object?> toJson() => <String, Object?>{
    'baselineNetlist': baselineNetlist.toJson(),
    'comparisonNetlist': comparisonNetlist.toJson(),
    'generatedAt': generatedAt.toUtc().toIso8601String(),
    'elementChanges': <Map<String, Object?>>[
      for (final c in elementChanges) c.toJson(),
    ],
    'summary': summary.toJson(),
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! NetlistDiff) return false;
    if (other.baselineNetlist != baselineNetlist) return false;
    if (other.comparisonNetlist != comparisonNetlist) return false;
    if (other.generatedAt != generatedAt) return false;
    if (other.summary != summary) return false;
    if (other.elementChanges.length != elementChanges.length) return false;
    for (var i = 0; i < elementChanges.length; i++) {
      if (other.elementChanges[i] != elementChanges[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    baselineNetlist,
    comparisonNetlist,
    generatedAt,
    summary,
    Object.hashAll(elementChanges),
  );

  @override
  String toString() =>
      'NetlistDiff(${baselineNetlist.identifier} vs '
      '${comparisonNetlist.identifier}, '
      '${elementChanges.length} changes, $summary)';
}
