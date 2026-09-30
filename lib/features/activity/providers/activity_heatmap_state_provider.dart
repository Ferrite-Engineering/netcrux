// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:netcrux/domain/models/activity/activity_analysis_result.dart';
import 'package:netcrux/domain/models/activity/activity_color_scheme.dart';
import 'package:netcrux/domain/models/activity/net_activity.dart';
import 'package:netcrux/domain/models/activity/waveform_time_range.dart';
import 'package:netcrux/services/activity/activity_analysis_service_provider.dart';

/// Per-tab snapshot of the Switching Activity Heatmap pane's state.
///
/// Holds:
///   * The most-recent [ActivityAnalysisResult] for the tab.
///   * The currently-focused net path (drives schematic selection
///     sync — when the user clicks a hot-net row the matching net
///     highlights on the schematic).
///   * The active [WaveformTimeRange] the next analyze() pass uses.
///   * The active [ActivityColorScheme] the Pro overlay's painter
///     integration interpolates against.
@immutable
class ActivityHeatmapState {
  /// Creates a snapshot.
  const ActivityHeatmapState({
    this.result = ActivityAnalysisResult.empty,
    this.selectedNetPath,
    this.timeRange = WaveformTimeRange.fullSimulationSentinel,
    this.colorScheme = ActivityColorScheme.heatmapRedBlue,
  });

  /// Canonical empty snapshot.
  static const ActivityHeatmapState empty = ActivityHeatmapState();

  /// The most-recent analysis result for this tab.
  final ActivityAnalysisResult result;

  /// Canonical hierarchical path of the focused net, or null when
  /// nothing is focused.
  final String? selectedNetPath;

  /// Active time range the next analyze() pass uses.
  final WaveformTimeRange timeRange;

  /// Active color scheme the painter override interpolates against.
  final ActivityColorScheme colorScheme;

  /// Convenience lookup for the focused [NetActivity].
  NetActivity? get selectedNetActivity {
    final path = selectedNetPath;
    if (path == null) return null;
    return result.activityForNet(path);
  }

  /// Returns a copy with the given fields replaced. Pass
  /// `clearSelectedNet` to reset the selection explicitly.
  ActivityHeatmapState copyWith({
    ActivityAnalysisResult? result,
    String? selectedNetPath,
    WaveformTimeRange? timeRange,
    ActivityColorScheme? colorScheme,
    bool clearSelectedNet = false,
  }) => ActivityHeatmapState(
    result: result ?? this.result,
    selectedNetPath: clearSelectedNet
        ? null
        : (selectedNetPath ?? this.selectedNetPath),
    timeRange: timeRange ?? this.timeRange,
    colorScheme: colorScheme ?? this.colorScheme,
  );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ActivityHeatmapState) return false;
    return result == other.result &&
        selectedNetPath == other.selectedNetPath &&
        timeRange == other.timeRange &&
        colorScheme == other.colorScheme;
  }

  @override
  int get hashCode => Object.hash(
    result,
    selectedNetPath,
    timeRange,
    colorScheme,
  );
}

/// Notifier owning the per-tab [ActivityHeatmapState].
///
/// Lives in a per-tab `ProviderContainer` (mirrors CDC / reset
/// domain / FSM / diff / source pane scoping) so each open tab keeps
/// its own analysis result, selection, time range, and color scheme.
class ActivityHeatmapNotifier extends Notifier<ActivityHeatmapState> {
  @override
  ActivityHeatmapState build() {
    // Drop the stale activity result when the active tab re-elaborates
    // (inert on Open Core: the no-op service uses an empty invalidation
    // stream) so an open heatmap does not keep showing the previous
    // elaboration's per-net activity until a manual re-run. Time range
    // and color scheme are user view preferences and are preserved.
    final service = ref.watch(activityAnalysisServiceProvider);
    final sub = service.analysisInvalidated.listen((_) => _onInvalidated());
    ref.onDispose(sub.cancel);
    return ActivityHeatmapState.empty;
  }

  void _onInvalidated() {
    if (state.result == ActivityAnalysisResult.empty &&
        state.selectedNetPath == null) {
      return;
    }
    state = state.copyWith(
      result: ActivityAnalysisResult.empty,
      clearSelectedNet: true,
    );
  }

  /// Installs a freshly-computed [ActivityAnalysisResult]. Preserves
  /// the currently-selected net only when the new result contains
  /// the corresponding path; otherwise clears it.
  void setResult(ActivityAnalysisResult result) {
    final keepSelection =
        state.selectedNetPath != null &&
            result.activityForNet(state.selectedNetPath!) != null
        ? state.selectedNetPath
        : null;
    state = state.copyWith(
      result: result,
      selectedNetPath: keepSelection,
      clearSelectedNet: keepSelection == null,
    );
  }

  /// Focuses the net at [netPath] (or clears the selection when
  /// null). Silently ignored when the path is unknown to the
  /// current result.
  void selectNet(String? netPath) {
    if (netPath == null) {
      state = state.copyWith(clearSelectedNet: true);
      return;
    }
    if (state.result.activityForNet(netPath) == null) return;
    state = state.copyWith(selectedNetPath: netPath);
  }

  /// Replaces the active [timeRange]. Does not re-run analysis — the
  /// hosting Pro panel triggers analyze() in response.
  void setTimeRange(WaveformTimeRange timeRange) {
    state = state.copyWith(timeRange: timeRange);
  }

  /// Replaces the active [colorScheme]. The Pro overlay's painter
  /// integration watches this and republishes the per-edge color
  /// override map in response.
  void setColorScheme(ActivityColorScheme colorScheme) {
    state = state.copyWith(colorScheme: colorScheme);
  }

  /// Clears the net selection. Leaves the analysis result, time
  /// range, and color scheme intact.
  void clearSelection() {
    state = state.copyWith(clearSelectedNet: true);
  }

  /// Resets the entire pane state back to [ActivityHeatmapState.empty].
  void reset() {
    state = ActivityHeatmapState.empty;
  }
}

/// Per-tab provider exposing the [ActivityHeatmapNotifier]. Scoped
/// per-tab via the workspace's `TabContainerManager`, same pattern
/// as CDC / reset domain / FSM / diff / source pane / bookmarks /
/// X-trace.
final activityHeatmapStateProvider =
    NotifierProvider<ActivityHeatmapNotifier, ActivityHeatmapState>(
      ActivityHeatmapNotifier.new,
      name: 'activityHeatmapStateProvider',
    );

/// Convenience: only the most-recent [ActivityAnalysisResult]. Lets
/// widgets that only render the result rebuild without re-firing on
/// selection / range / scheme changes.
final perTabActivityAnalysisResultProvider = Provider<ActivityAnalysisResult>(
  (ref) => ref.watch(activityHeatmapStateProvider).result,
  name: 'perTabActivityAnalysisResultProvider',
);

/// Convenience: only the currently-focused [NetActivity] (or null).
final selectedNetActivityProvider = Provider<NetActivity?>(
  (ref) => ref.watch(activityHeatmapStateProvider).selectedNetActivity,
  name: 'selectedNetActivityProvider',
);

/// Convenience: only the active [WaveformTimeRange].
final activeActivityTimeRangeProvider = Provider<WaveformTimeRange>(
  (ref) => ref.watch(activityHeatmapStateProvider).timeRange,
  name: 'activeActivityTimeRangeProvider',
);

/// Convenience: only the active [ActivityColorScheme].
final activeActivityColorSchemeProvider = Provider<ActivityColorScheme>(
  (ref) => ref.watch(activityHeatmapStateProvider).colorScheme,
  name: 'activeActivityColorSchemeProvider',
);
