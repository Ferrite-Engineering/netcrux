// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:netcrux/domain/models/activity/net_activity.dart';
import 'package:netcrux/domain/models/activity/waveform_source.dart';
import 'package:netcrux/domain/models/activity/waveform_time_range.dart';

/// Aggregated result of an [ActivityAnalysisService.analyze] call.
///
/// Carries the per-net activity map, sorted top-N convenience lists,
/// and analysis-duration field useful for perf-budget tracking.
@immutable
class ActivityAnalysisResult {
  /// Creates an analysis result. Callers should use
  /// [ActivityAnalysisResult.from] when possible; the raw constructor
  /// is exposed for fixture / JSON round-trip use.
  const ActivityAnalysisResult({
    required this.source,
    required this.timeRange,
    required this.perNetActivity,
    required this.totalTransitions,
    required this.hottest,
    required this.coldest,
    required this.analysisDuration,
  });

  /// Convenience constructor: builds the [hottest] / [coldest] sorted
  /// top-N lists from [perNetActivity] in one place so callers don't
  /// re-implement the sort each time.
  factory ActivityAnalysisResult.from({
    required WaveformSource? source,
    required WaveformTimeRange timeRange,
    required Map<String, NetActivity> perNetActivity,
    required Duration analysisDuration,
    int topN = 50,
  }) {
    final all = perNetActivity.values.toList()
      ..sort((a, b) => b.activityScore.compareTo(a.activityScore));
    final hot = all.take(topN).toList(growable: false);
    final cold = all.reversed.take(topN).toList(growable: false);
    var total = 0;
    for (final v in perNetActivity.values) {
      total += v.transitionCount;
    }
    return ActivityAnalysisResult(
      source: source,
      timeRange: timeRange,
      perNetActivity: Map.unmodifiable(perNetActivity),
      totalTransitions: total,
      hottest: hot,
      coldest: cold,
      analysisDuration: analysisDuration,
    );
  }

  /// JSON round-trip constructor.
  factory ActivityAnalysisResult.fromJson(Map<String, Object?> json) {
    final sourceRaw = json['source'];
    final perNetRaw = json['perNetActivity'];
    final hottestRaw = json['hottest'];
    final coldestRaw = json['coldest'];
    final rangeRaw = json['timeRange'];
    final durationMicros =
        (json['analysisDurationMicros'] as num?)?.toInt() ?? 0;
    return ActivityAnalysisResult(
      source: sourceRaw is Map<String, Object?>
          ? WaveformSource.fromJson(sourceRaw)
          : null,
      timeRange: rangeRaw is Map<String, Object?>
          ? WaveformTimeRange.fromJson(rangeRaw)
          : WaveformTimeRange.fullSimulationSentinel,
      perNetActivity: perNetRaw is Map<String, Object?>
          ? <String, NetActivity>{
              for (final entry in perNetRaw.entries)
                if (entry.value is Map<String, Object?>)
                  entry.key: NetActivity.fromJson(
                    entry.value! as Map<String, Object?>,
                  ),
            }
          : const <String, NetActivity>{},
      totalTransitions: (json['totalTransitions'] as num?)?.toInt() ?? 0,
      hottest: hottestRaw is List
          ? <NetActivity>[
              for (final r in hottestRaw)
                if (r is Map<String, Object?>) NetActivity.fromJson(r),
            ]
          : const <NetActivity>[],
      coldest: coldestRaw is List
          ? <NetActivity>[
              for (final r in coldestRaw)
                if (r is Map<String, Object?>) NetActivity.fromJson(r),
            ]
          : const <NetActivity>[],
      analysisDuration: Duration(microseconds: durationMicros),
    );
  }

  /// Canonical empty result. Used by [NoopActivityAnalysisService]
  /// and by widgets rendering their empty state.
  static const ActivityAnalysisResult empty = ActivityAnalysisResult(
    source: null,
    timeRange: WaveformTimeRange.fullSimulationSentinel,
    perNetActivity: <String, NetActivity>{},
    totalTransitions: 0,
    hottest: <NetActivity>[],
    coldest: <NetActivity>[],
    analysisDuration: Duration.zero,
  );

  /// The waveform source the analysis was computed against. Null when
  /// no source was loaded (the empty-state path).
  final WaveformSource? source;

  /// The (expanded, non-sentinel) time range the analysis covered.
  /// Surfaced in the panel footer so the user knows exactly what the
  /// scores represent.
  final WaveformTimeRange timeRange;

  /// Full per-net activity map keyed by canonical net path.
  /// Unmodifiable; copy before mutating.
  final Map<String, NetActivity> perNetActivity;

  /// Sum of every [NetActivity.transitionCount] in the result.
  final int totalTransitions;

  /// Top-N nets sorted by [NetActivity.activityScore] descending. The
  /// panel's "Hot signals" list reads from this directly.
  final List<NetActivity> hottest;

  /// Bottom-N nets sorted by [NetActivity.activityScore] ascending.
  /// The panel's "Cold signals" expandable section reads from this.
  final List<NetActivity> coldest;

  /// Wall-clock duration the analysis pass took. Surfaced in the
  /// panel footer for perf tracking.
  final Duration analysisDuration;

  /// True when the analyzer found no nets at all — the source loaded
  /// but had no signals matching the scope filter, or no source has
  /// been loaded yet.
  bool get isEmpty => perNetActivity.isEmpty;

  /// Convenience lookup: activity by canonical net path, or null.
  NetActivity? activityForNet(String netPath) => perNetActivity[netPath];

  /// JSON map suitable for fixture round-trip.
  Map<String, Object?> toJson() => <String, Object?>{
    'source': source?.toJson(),
    'timeRange': timeRange.toJson(),
    'perNetActivity': <String, Object?>{
      for (final entry in perNetActivity.entries)
        entry.key: entry.value.toJson(),
    },
    'totalTransitions': totalTransitions,
    'hottest': <Map<String, Object?>>[
      for (final h in hottest) h.toJson(),
    ],
    'coldest': <Map<String, Object?>>[
      for (final c in coldest) c.toJson(),
    ],
    'analysisDurationMicros': analysisDuration.inMicroseconds,
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ActivityAnalysisResult) return false;
    if (source != other.source) return false;
    if (timeRange != other.timeRange) return false;
    if (totalTransitions != other.totalTransitions) return false;
    if (analysisDuration != other.analysisDuration) return false;
    if (perNetActivity.length != other.perNetActivity.length) return false;
    for (final entry in perNetActivity.entries) {
      if (other.perNetActivity[entry.key] != entry.value) return false;
    }
    if (hottest.length != other.hottest.length) return false;
    for (var i = 0; i < hottest.length; i++) {
      if (hottest[i] != other.hottest[i]) return false;
    }
    if (coldest.length != other.coldest.length) return false;
    for (var i = 0; i < coldest.length; i++) {
      if (coldest[i] != other.coldest[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    source,
    timeRange,
    totalTransitions,
    analysisDuration,
    perNetActivity.length,
    hottest.length,
    coldest.length,
  );

  @override
  String toString() =>
      'ActivityAnalysisResult('
      '${perNetActivity.length} nets, '
      '$totalTransitions transitions, '
      'range $timeRange, '
      'duration ${analysisDuration.inMilliseconds}ms)';
}
