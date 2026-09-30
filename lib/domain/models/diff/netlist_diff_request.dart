// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:netcrux/domain/models/diff/netlist_diff_match_strategy.dart';

/// Reference to one side of a [NetlistDiffRequest].
///
/// The diff engine has to identify "which netlist" without holding the
/// netlist content itself — the content is loaded via the engine's
/// internal pipeline (file → Yosys → [NetlistModel]). This thin wrapper
/// carries the user-facing pointer (typically a project file path,
/// occasionally a synthetic in-memory key for tests) plus an optional
/// display label.
///
/// Two refs are equal when their [identifier] is equal — the optional
/// [displayLabel] is descriptive only and does not participate in
/// equality.
@immutable
class NetlistRef {
  /// Creates a netlist reference.
  const NetlistRef({required this.identifier, this.displayLabel});

  /// JSON round-trip constructor.
  factory NetlistRef.fromJson(Map<String, Object?> json) => NetlistRef(
    identifier: json['identifier']?.toString() ?? '',
    displayLabel: json['displayLabel']?.toString(),
  );

  /// Canonical, addressable identifier — typically a project / source
  /// file path. The diff service consumes this through its loader to
  /// elaborate the netlist content.
  final String identifier;

  /// Optional short label for the panel header / breadcrumb (e.g.
  /// `baseline.v`). Falls back to [identifier] when null.
  final String? displayLabel;

  /// JSON map suitable for fixture serialization.
  Map<String, Object?> toJson() => <String, Object?>{
    'identifier': identifier,
    if (displayLabel != null) 'displayLabel': displayLabel,
  };

  @override
  bool operator ==(Object other) =>
      other is NetlistRef && other.identifier == identifier;

  @override
  int get hashCode => identifier.hashCode;

  @override
  String toString() => 'NetlistRef($identifier)';
}

/// Description of a diff job — passed to [NetlistDiffService.compare].
///
/// The [scopeFilter] is an optional hierarchical-path prefix that
/// restricts the engine to a sub-tree of the design (useful for
/// "compare this module across both runs" workflows driven by the
/// schematic context-menu's "Compare with this Element in Baseline"
/// entry). When null the full design is compared.
@immutable
class NetlistDiffRequest {
  /// Creates a diff request.
  const NetlistDiffRequest({
    required this.baselineNetlist,
    required this.comparisonNetlist,
    this.matchStrategy = NetlistDiffMatchStrategy.exactNameMatch,
    this.scopeFilter,
  });

  /// JSON round-trip constructor.
  factory NetlistDiffRequest.fromJson(Map<String, Object?> json) {
    final strategyStr = json['matchStrategy'] as String? ?? 'exactNameMatch';
    return NetlistDiffRequest(
      baselineNetlist: NetlistRef.fromJson(
        json['baselineNetlist'] as Map<String, Object?>? ?? const {},
      ),
      comparisonNetlist: NetlistRef.fromJson(
        json['comparisonNetlist'] as Map<String, Object?>? ?? const {},
      ),
      matchStrategy: NetlistDiffMatchStrategy.values.firstWhere(
        (s) => s.name == strategyStr,
        orElse: () => NetlistDiffMatchStrategy.exactNameMatch,
      ),
      scopeFilter: json['scopeFilter'] as String?,
    );
  }

  /// The "before" netlist. Elements present here but missing from
  /// [comparisonNetlist] are reported as `removed`.
  final NetlistRef baselineNetlist;

  /// The "after" netlist. Elements present here but missing from
  /// [baselineNetlist] are reported as `added`.
  final NetlistRef comparisonNetlist;

  /// Which matching strategy the engine should use. V1 of the Pro
  /// service only supports [NetlistDiffMatchStrategy.exactNameMatch]
  /// and throws [UnsupportedError] for the other two.
  final NetlistDiffMatchStrategy matchStrategy;

  /// Optional hierarchical-path prefix that scopes the comparison to a
  /// sub-tree of the design. When non-null, only elements whose
  /// [ElementId.path] starts with this prefix are included in the
  /// resulting [NetlistDiff.elementChanges].
  final String? scopeFilter;

  /// Returns a copy with the given fields replaced. Passing
  /// [clearScopeFilter] resets [scopeFilter] to null explicitly.
  NetlistDiffRequest copyWith({
    NetlistRef? baselineNetlist,
    NetlistRef? comparisonNetlist,
    NetlistDiffMatchStrategy? matchStrategy,
    String? scopeFilter,
    bool clearScopeFilter = false,
  }) {
    return NetlistDiffRequest(
      baselineNetlist: baselineNetlist ?? this.baselineNetlist,
      comparisonNetlist: comparisonNetlist ?? this.comparisonNetlist,
      matchStrategy: matchStrategy ?? this.matchStrategy,
      scopeFilter: clearScopeFilter ? null : (scopeFilter ?? this.scopeFilter),
    );
  }

  /// JSON map suitable for fixture serialization.
  Map<String, Object?> toJson() => <String, Object?>{
    'baselineNetlist': baselineNetlist.toJson(),
    'comparisonNetlist': comparisonNetlist.toJson(),
    'matchStrategy': matchStrategy.name,
    if (scopeFilter != null) 'scopeFilter': scopeFilter,
  };

  @override
  bool operator ==(Object other) =>
      other is NetlistDiffRequest &&
      other.baselineNetlist == baselineNetlist &&
      other.comparisonNetlist == comparisonNetlist &&
      other.matchStrategy == matchStrategy &&
      other.scopeFilter == scopeFilter;

  @override
  int get hashCode => Object.hash(
    baselineNetlist,
    comparisonNetlist,
    matchStrategy,
    scopeFilter,
  );

  @override
  String toString() =>
      'NetlistDiffRequest(${baselineNetlist.identifier} vs '
      '${comparisonNetlist.identifier}, ${matchStrategy.name}'
      '${scopeFilter != null ? ', scope: $scopeFilter' : ''})';
}
