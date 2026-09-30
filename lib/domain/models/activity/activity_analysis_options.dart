// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:meta/meta.dart';
import 'package:netcrux/domain/models/activity/activity_normalization.dart';
import 'package:netcrux/domain/models/activity/waveform_time_range.dart';

/// Tuning knobs passed to [ActivityAnalysisService.analyze].
///
/// All knobs are optional; the defaults give a sensible behavior for
/// typical netlists (a few hundred to a few thousand nets analyzed
/// against the full simulation range).
@immutable
class ActivityAnalysisOptions {
  /// Creates an options bundle.
  const ActivityAnalysisOptions({
    this.scopeFilter,
    this.timeRange = WaveformTimeRange.fullSimulationSentinel,
    this.normalization = ActivityNormalization.perNet,
    this.topN = 50,
    this.excludedNetPaths = const <String>[],
  });

  /// Canonical "use all defaults" instance.
  static const ActivityAnalysisOptions defaults = ActivityAnalysisOptions();

  /// Optional canonical hierarchical-path prefix that restricts the
  /// walk to a sub-tree of the design (e.g. `"top.cpu"`). Null walks
  /// the entire design.
  final ElementId? scopeFilter;

  /// Time window the analyzer runs over. Defaults to the
  /// [WaveformTimeRange.fullSimulationSentinel] which the analyzer
  /// expands against the loaded source's end time.
  final WaveformTimeRange timeRange;

  /// How per-net scores are normalized to `[0.0, 1.0]`. See
  /// [ActivityNormalization] for the trade-offs.
  final ActivityNormalization normalization;

  /// Number of "hottest" and "coldest" rows the panel surfaces. The
  /// analyzer always retains the full per-net result; this knob only
  /// controls the size of the convenience `hottest` / `coldest`
  /// lists on the result.
  final int topN;

  /// Canonical hierarchical net paths the analyzer should skip
  /// entirely (e.g. the user right-clicked a hot clock and chose
  /// "Exclude from analysis"). Match is exact-string against the
  /// resolved net path.
  final List<String> excludedNetPaths;

  /// Returns a copy with the given fields replaced. Pass
  /// `clearScopeFilter` to reset the scope to null explicitly.
  ActivityAnalysisOptions copyWith({
    ElementId? scopeFilter,
    WaveformTimeRange? timeRange,
    ActivityNormalization? normalization,
    int? topN,
    List<String>? excludedNetPaths,
    bool clearScopeFilter = false,
  }) => ActivityAnalysisOptions(
    scopeFilter: clearScopeFilter ? null : (scopeFilter ?? this.scopeFilter),
    timeRange: timeRange ?? this.timeRange,
    normalization: normalization ?? this.normalization,
    topN: topN ?? this.topN,
    excludedNetPaths: excludedNetPaths ?? this.excludedNetPaths,
  );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ActivityAnalysisOptions) return false;
    if (scopeFilter != other.scopeFilter) return false;
    if (timeRange != other.timeRange) return false;
    if (normalization != other.normalization) return false;
    if (topN != other.topN) return false;
    if (excludedNetPaths.length != other.excludedNetPaths.length) {
      return false;
    }
    for (var i = 0; i < excludedNetPaths.length; i++) {
      if (excludedNetPaths[i] != other.excludedNetPaths[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    scopeFilter,
    timeRange,
    normalization,
    topN,
    Object.hashAll(excludedNetPaths),
  );

  @override
  String toString() =>
      'ActivityAnalysisOptions('
      'scope: ${scopeFilter?.path ?? "all"}, '
      'range: $timeRange, '
      'normalization: ${normalization.name}, '
      'topN: $topN, '
      'excluded: ${excludedNetPaths.length})';
}
