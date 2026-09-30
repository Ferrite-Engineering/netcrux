// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'pane_render_stats.g.dart';

/// One frame's worth of paint-pipeline metrics for a single
/// schematic canvas. Mirrors WaveCrux's `RenderPipelineStats`, so the Pane
/// Render Stats popover reads the same data shape in both products.
@immutable
class PaneRenderStats {
  /// Creates a stats sample.
  const PaneRenderStats({
    required this.frameNumber,
    required this.paintMicroseconds,
    required this.visibleCells,
    required this.visibleEdges,
    required this.totalCells,
    required this.totalEdges,
  });

  /// Initial zero sample. Used as the provider's default before the
  /// first paint completes.
  static const PaneRenderStats empty = PaneRenderStats(
    frameNumber: 0,
    paintMicroseconds: 0,
    visibleCells: 0,
    visibleEdges: 0,
    totalCells: 0,
    totalEdges: 0,
  );

  /// Monotonic counter — useful in tests that want to assert a paint
  /// happened. Increments on every paint() call.
  final int frameNumber;

  /// Wall-clock time the most recent paint() took.
  final int paintMicroseconds;

  /// Cells the painter actually drew last frame — i.e. those overlapping
  /// the visible design rect after viewport culling. Equals [totalCells]
  /// only when every cell is on-screen (or culling is disabled).
  final int visibleCells;

  /// Edges drawn last frame (post-cull). Same relationship to
  /// [totalEdges] as [visibleCells] has to [totalCells].
  final int visibleEdges;

  /// Cell count in the laid-out graph that was painted.
  final int totalCells;

  /// Edge count in the laid-out graph that was painted.
  final int totalEdges;

  /// Returns a copy with the given fields replaced.
  PaneRenderStats copyWith({
    int? frameNumber,
    int? paintMicroseconds,
    int? visibleCells,
    int? visibleEdges,
    int? totalCells,
    int? totalEdges,
  }) {
    return PaneRenderStats(
      frameNumber: frameNumber ?? this.frameNumber,
      paintMicroseconds: paintMicroseconds ?? this.paintMicroseconds,
      visibleCells: visibleCells ?? this.visibleCells,
      visibleEdges: visibleEdges ?? this.visibleEdges,
      totalCells: totalCells ?? this.totalCells,
      totalEdges: totalEdges ?? this.totalEdges,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PaneRenderStats &&
          other.frameNumber == frameNumber &&
          other.paintMicroseconds == paintMicroseconds &&
          other.visibleCells == visibleCells &&
          other.visibleEdges == visibleEdges &&
          other.totalCells == totalCells &&
          other.totalEdges == totalEdges);

  @override
  int get hashCode => Object.hash(
    frameNumber,
    paintMicroseconds,
    visibleCells,
    visibleEdges,
    totalCells,
    totalEdges,
  );

  @override
  String toString() =>
      'PaneRenderStats(frame=$frameNumber, '
      '$paintMicroseconds μs, $visibleCells/$totalCells cells, '
      '$visibleEdges/$totalEdges edges)';
}

/// Per-pane render-stats notifier.
///
/// The SchematicPainter calls [PaneRenderStatsNotifier.record] from
/// its paint() method (passing the [PaneRenderStats] for the frame
/// it just finished). Any UI surface that wants to display the data
/// — the Pane Render Stats popover, the App Diagnostics dialog —
/// `ref.watch`es this provider.
///
/// Lives per pane: `netcrux_pane_overrides.dart` re-binds it in each
/// pane's `ProviderContainer` (mirroring WaveCrux) so two simultaneous
/// canvases publish independent streams.
@Riverpod(keepAlive: true)
class PaneRenderStatsNotifier extends _$PaneRenderStatsNotifier {
  @override
  PaneRenderStats build() => PaneRenderStats.empty;

  /// Records a fresh stats sample from the painter. Kept as a method
  /// (not a setter) so the call site in `RenderStatsSink.record`
  /// reads consistently with the recording test sinks.
  // ignore: use_setters_to_change_properties
  void record(PaneRenderStats stats) {
    state = stats;
  }
}
