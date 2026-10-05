// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:meta/meta.dart';
import 'package:netcrux/domain/models/diff/netlist_diff_element_kind.dart';

/// Classification of a single [ElementChange].
///
/// One of the four buckets the diff engine sorts elements into when it
/// walks both netlists in lockstep. [added] and [removed] are the elements
/// left without a match on the other side; [modified] and [unchanged] come
/// from comparing the attributes of a matched pair.
enum ElementChangeKind {
  /// The element is present in the comparison netlist but missing
  /// from the baseline.
  added,

  /// The element is present in the baseline netlist but missing from
  /// the comparison.
  removed,

  /// The element exists in both netlists but at least one of its
  /// attributes differs.
  modified,

  /// The element exists in both netlists with identical attributes.
  unchanged,
}

/// One row in a [NetlistDiff] — describes how a single netlist element
/// (instance / net / port / module) differs (or doesn't) between the
/// baseline and comparison sides.
///
/// Construction invariants:
///
/// * `kind == added` → [baselineSnapshot] is null, [comparisonSnapshot]
///   is non-null, [modifiedAttributes] is empty.
/// * `kind == removed` → [baselineSnapshot] is non-null, [comparisonSnapshot]
///   is null, [modifiedAttributes] is empty.
/// * `kind == modified` → both snapshots are non-null, and
///   [modifiedAttributes] lists at least one attribute name that
///   differs.
/// * `kind == unchanged` → both snapshots are non-null and
///   [modifiedAttributes] is empty.
///
/// Snapshots are plain `Map<String, String>`s of attribute name →
/// stringified value, kept JSON-natural so the entire [NetlistDiff]
/// round-trips through fixtures and reports without bespoke
/// serialization. The diff engine decides which subset of each
/// element's attributes are diff-significant; un-diffed attributes
/// simply do not appear in the snapshot.
@immutable
class ElementChange {
  /// Creates a change row. Callers must respect the per-kind
  /// invariants documented on the class.
  const ElementChange({
    required this.kind,
    required this.elementKind,
    required this.elementId,
    this.baselineSnapshot,
    this.comparisonSnapshot,
    this.modifiedAttributes = const <String>[],
    this.sourceLocation,
    this.comparisonName,
  });

  /// JSON round-trip constructor. Mirrors [toJson] so a [NetlistDiff]
  /// can be persisted and re-read by tests / fixtures.
  factory ElementChange.fromJson(Map<String, Object?> json) {
    final kindStr = json['kind'] as String? ?? 'unchanged';
    final elementKindStr = json['elementKind'] as String? ?? 'instance';
    final elementIdRaw = json['elementId'];
    final elementId = elementIdRaw is Map<String, Object?>
        ? ElementId.fromJson(elementIdRaw)
        : const ElementId(kind: ElementKind.signal, path: '');
    final modifiedAttrsRaw = json['modifiedAttributes'];
    return ElementChange(
      kind: ElementChangeKind.values.firstWhere(
        (k) => k.name == kindStr,
        orElse: () => ElementChangeKind.unchanged,
      ),
      elementKind: NetlistDiffElementKind.values.firstWhere(
        (k) => k.name == elementKindStr,
        orElse: () => NetlistDiffElementKind.instance,
      ),
      elementId: elementId,
      baselineSnapshot: _readSnapshot(json['baselineSnapshot']),
      comparisonSnapshot: _readSnapshot(json['comparisonSnapshot']),
      modifiedAttributes: modifiedAttrsRaw is List
          ? <String>[for (final v in modifiedAttrsRaw) v.toString()]
          : const <String>[],
      sourceLocation: json['sourceLocation'] as String?,
      comparisonName: json['comparisonName'] as String?,
    );
  }

  /// Which of the four buckets this row belongs to.
  final ElementChangeKind kind;

  /// What kind of netlist element (instance / net / port / module).
  final NetlistDiffElementKind elementKind;

  /// Canonical cross-suite identifier for the element. The Pro service
  /// builds these via [NetcruxNameResolver] so they can be used
  /// interchangeably with the rest of the per-tab schematic-selection
  /// surfaces (cross-probe, source pane, X-trace).
  final ElementId elementId;

  /// Stringified attribute map for the baseline side of this element.
  /// `null` when the element only exists on the comparison side
  /// (`kind == added`).
  final Map<String, String>? baselineSnapshot;

  /// Stringified attribute map for the comparison side of this element.
  /// `null` when the element only exists on the baseline side
  /// (`kind == removed`).
  final Map<String, String>? comparisonSnapshot;

  /// Attribute names that differ between [baselineSnapshot] and
  /// [comparisonSnapshot]. Populated only for `kind == modified`;
  /// empty otherwise.
  final List<String> modifiedAttributes;

  /// The element's Yosys `src` attribute (`path:line.col-line.col`) on the
  /// side [elementId] names: the baseline for removed, modified and
  /// unchanged rows, the comparison for added rows. Null when the element
  /// carries none. Display only: it never takes part in classification,
  /// since an edit above an element moves its line without changing it.
  final String? sourceLocation;

  /// The comparison-side name of an element matched by structure rather
  /// than by name. Yosys names the cells and nets it generates after the
  /// source path, the line and a running counter, so the same `$add` is
  /// `$add$a.v:14$3` on one side and `$add$b.v:17$3` on the other; the row
  /// is keyed on the baseline name and this records the other. Null when
  /// both sides share the name, and on added or removed rows.
  final String? comparisonName;

  /// Returns a copy with the given fields replaced.
  ElementChange copyWith({
    ElementChangeKind? kind,
    NetlistDiffElementKind? elementKind,
    ElementId? elementId,
    Map<String, String>? baselineSnapshot,
    Map<String, String>? comparisonSnapshot,
    List<String>? modifiedAttributes,
    String? sourceLocation,
    String? comparisonName,
  }) {
    return ElementChange(
      kind: kind ?? this.kind,
      elementKind: elementKind ?? this.elementKind,
      elementId: elementId ?? this.elementId,
      baselineSnapshot: baselineSnapshot ?? this.baselineSnapshot,
      comparisonSnapshot: comparisonSnapshot ?? this.comparisonSnapshot,
      modifiedAttributes: modifiedAttributes ?? this.modifiedAttributes,
      sourceLocation: sourceLocation ?? this.sourceLocation,
      comparisonName: comparisonName ?? this.comparisonName,
    );
  }

  /// JSON map suitable for fixture serialization. Round-trips through
  /// [ElementChange.fromJson].
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind.name,
    'elementKind': elementKind.name,
    'elementId': elementId.toJson(),
    if (baselineSnapshot != null) 'baselineSnapshot': baselineSnapshot,
    if (comparisonSnapshot != null) 'comparisonSnapshot': comparisonSnapshot,
    if (modifiedAttributes.isNotEmpty) 'modifiedAttributes': modifiedAttributes,
    if (sourceLocation != null) 'sourceLocation': sourceLocation,
    if (comparisonName != null) 'comparisonName': comparisonName,
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ElementChange) return false;
    if (other.kind != kind) return false;
    if (other.elementKind != elementKind) return false;
    if (other.elementId != elementId) return false;
    if (!_mapEquals(other.baselineSnapshot, baselineSnapshot)) return false;
    if (!_mapEquals(other.comparisonSnapshot, comparisonSnapshot)) {
      return false;
    }
    if (other.sourceLocation != sourceLocation) return false;
    if (other.comparisonName != comparisonName) return false;
    if (other.modifiedAttributes.length != modifiedAttributes.length) {
      return false;
    }
    for (var i = 0; i < modifiedAttributes.length; i++) {
      if (other.modifiedAttributes[i] != modifiedAttributes[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    kind,
    elementKind,
    elementId,
    _mapHash(baselineSnapshot),
    _mapHash(comparisonSnapshot),
    Object.hashAll(modifiedAttributes),
    sourceLocation,
    comparisonName,
  );

  @override
  String toString() =>
      'ElementChange(${kind.name} ${elementKind.name} '
      '${elementId.path})';
}

Map<String, String>? _readSnapshot(Object? value) {
  if (value is! Map) return null;
  return <String, String>{
    for (final entry in value.entries)
      entry.key.toString(): entry.value?.toString() ?? '',
  };
}

bool _mapEquals(Map<String, String>? a, Map<String, String>? b) {
  if (a == null && b == null) return true;
  if (a == null || b == null) return false;
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}

int _mapHash(Map<String, String>? m) {
  if (m == null) return 0;
  var hash = 0;
  for (final entry in m.entries) {
    hash ^= Object.hash(entry.key, entry.value);
  }
  return hash;
}
