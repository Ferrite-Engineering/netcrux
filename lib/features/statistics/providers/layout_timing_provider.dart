// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';

/// How many layout timings the rolling window keeps.
const int kLayoutTimingWindow = 30;

/// Timing history for the ELK layout pass.
///
/// Layout is the slowest non-elaboration step in the rendering pipeline —
/// slow enough on a large scope that "is it hung or is it working?" is a
/// real question, which is why the plan calls it out as NetCrux's
/// product-specific strip segment.
///
/// Root-scope rather than per-pane: ELK runs once per scope change, not
/// per pane, and two panes showing the same scope share the result.
/// ### Why there is no `isRunning` here
///
/// "A layout pass is in flight" is already expressed exactly by
/// `currentLaidOutGraphProvider`'s `AsyncValue.isLoading` — that provider
/// *is* the layout pass. Mirroring it into this notifier would be a second
/// source of truth that can disagree with the first, and setting it from
/// inside the graph provider's build is something Riverpod correctly
/// forbids ("providers are not allowed to modify other providers during
/// their initialization"). The strip reads the running flag from the graph
/// provider and the durations from here.
@immutable
class LayoutTimingStats {
  /// Creates a snapshot.
  const LayoutTimingStats({
    required this.lastMicroseconds,
    required this.recentMillis,
  });

  /// The idle, never-run state.
  static const LayoutTimingStats empty = LayoutTimingStats(
    lastMicroseconds: 0,
    recentMillis: <double>[],
  );

  /// Wall-clock duration of the most recent completed layout.
  final int lastMicroseconds;

  /// Recent layout durations in milliseconds, oldest first — the
  /// sparkline series.
  final List<double> recentMillis;

  /// Whether any layout has completed.
  bool get hasSample => lastMicroseconds > 0;

  @override
  String toString() => 'LayoutTimingStats(last: ${lastMicroseconds}us)';
}

/// Layout timing history, root-scope.
class LayoutTimingNotifier extends Notifier<LayoutTimingStats> {
  final List<double> _recent = <double>[];

  @override
  LayoutTimingStats build() => LayoutTimingStats.empty;

  /// Records a completed pass.
  ///
  /// Called after the layout future resolves, never during the graph
  /// provider's synchronous build.
  void completed(Duration elapsed) {
    _recent.add(elapsed.inMicroseconds / 1000.0);
    if (_recent.length > kLayoutTimingWindow) _recent.removeAt(0);
    state = LayoutTimingStats(
      lastMicroseconds: elapsed.inMicroseconds,
      recentMillis: List<double>.unmodifiable(_recent),
    );
  }
}

/// This tab's layout timing history.
///
/// Per-tab — registered in `netcruxTabOverridesFactory` alongside
/// `currentLaidOutGraphProvider`, which is what writes it. Left at root it
/// resolved a single shared instance for every tab, so elaborating a large
/// design in tab A left tab B's statistics strip reporting A's layout time
/// for a design B had never laid out.
final NotifierProvider<LayoutTimingNotifier, LayoutTimingStats>
layoutTimingProvider =
    NotifierProvider<LayoutTimingNotifier, LayoutTimingStats>(
      LayoutTimingNotifier.new,
    );
