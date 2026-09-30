// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:netcrux/domain/models/activity/activity_analysis_options.dart';
import 'package:netcrux/domain/models/activity/activity_analysis_result.dart';
import 'package:netcrux/domain/models/activity/net_activity.dart';
import 'package:netcrux/domain/models/activity/waveform_time_range.dart';

/// Extension-point service powering the Switching Activity
/// Heatmap's analysis pass.
///
/// Walks the loaded netlist + waveform source, computes per-net
/// transition counts + duty cycles over the requested time range,
/// and emits an [ActivityAnalysisResult] with sorted top-N
/// convenience lists.
///
/// **Open-core ships [NoopActivityAnalysisService]** as the
/// registered default: [analyze] returns
/// [ActivityAnalysisResult.empty], focused per-net queries return
/// null, and [analysisInvalidated] never emits. The Pro overlay
/// registers a concrete `ProActivityAnalysisService` via
/// `proOverrides` that consumes the loaded netlist + the active
/// [WaveformSourceService] to compute real activity.
abstract interface class ActivityAnalysisService {
  /// Walks the netlist + waveform source and returns the full
  /// per-net activity result.
  ///
  /// Pass [ActivityAnalysisOptions] to tune the analysis (scope
  /// filter, time range, normalization, top-N, excluded nets); omit
  /// or pass [ActivityAnalysisOptions.defaults] for the default
  /// behavior.
  ///
  /// 1000-net analysis over a 100 ms window should complete in
  /// under 2 s on a development workstation. Open-core's no-op
  /// resolves immediately.
  Future<ActivityAnalysisResult> analyze({
    ActivityAnalysisOptions? options,
  });

  /// Focused query: returns the per-net activity record for
  /// [netPath] inside [range], or null when:
  ///   * No waveform is loaded.
  ///   * The net is not present in the loaded source.
  ///   * No transitions fall inside the window.
  Future<NetActivity?> activityForNet(
    String netPath,
    WaveformTimeRange range,
  );

  /// Stream that emits when the underlying inputs to the most-recent
  /// analysis change — typically because the waveform source was
  /// unloaded / reloaded or the netlist was re-elaborated. The
  /// per-tab `currentActivityAnalysisProvider` listens to invalidate
  /// its cache and re-run analysis so the panel stays in sync with
  /// the live design.
  ///
  /// Open-core's no-op default never emits.
  Stream<void> get analysisInvalidated;
}

/// Open-core default: returns the empty result for every request,
/// null for per-net queries, and never emits on [analysisInvalidated].
///
/// The open-core build registers this implementation and reads nothing
/// through it: [ActivityHeatmapPane] is mounted only by the Pro overlay,
/// and the activity actions are refused with a "requires NetCrux Pro"
/// notice. Widget tests mount the pane over this default to render its
/// empty state without the overlay.
class NoopActivityAnalysisService implements ActivityAnalysisService {
  /// Creates the no-op service.
  const NoopActivityAnalysisService();

  @override
  Future<ActivityAnalysisResult> analyze({
    ActivityAnalysisOptions? options,
  }) async => ActivityAnalysisResult.empty;

  @override
  Future<NetActivity?> activityForNet(
    String netPath,
    WaveformTimeRange range,
  ) async => null;

  @override
  Stream<void> get analysisInvalidated => const Stream<void>.empty();
}
