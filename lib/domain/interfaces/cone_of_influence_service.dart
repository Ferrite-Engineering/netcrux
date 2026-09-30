// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:netcrux/domain/models/schematic/laid_out_graph.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/domain/models/trace/trace_overlay.dart';

/// Direction of a cone-of-influence traversal.
///
/// - [fanin] walks **backward** through the netlist from the selected
///   element, gathering every cell / boundary input / wire that ultimately
///   drives the selection.
/// - [fanout] walks **forward** from the selection, gathering every cell
///   / boundary output / wire driven by it.
enum ConeOfInfluenceMode {
  /// Trace drivers of the selected element up to [ConeOfInfluenceRequest.depth].
  fanin,

  /// Trace loads of the selected element up to [ConeOfInfluenceRequest.depth].
  fanout,
}

/// Request payload supplied to [ConeOfInfluenceService.compute].
///
/// Immutable so request shapes can be cached or compared cheaply.
@immutable
class ConeOfInfluenceRequest {
  /// Creates a cone-of-influence request.
  const ConeOfInfluenceRequest({
    required this.laidOut,
    required this.selection,
    required this.mode,
    required this.depth,
  });

  /// The graph (cells, ports, edges) the cone is traced inside.
  final LaidOutGraph laidOut;

  /// Element the trace radiates from. Must be a non-empty selection.
  /// [SelectedElement.none] yields an empty overlay.
  final SelectedElement selection;

  /// Whether to walk drivers ([ConeOfInfluenceMode.fanin]) or loads
  /// ([ConeOfInfluenceMode.fanout]).
  final ConeOfInfluenceMode mode;

  /// Maximum BFS depth from the selection. `1` reproduces the
  /// open-core [TraceService] one-step semantics. `null` traces to
  /// the natural boundary (primary inputs / outputs / driving FFs).
  final int? depth;
}

/// Extension-point service that computes a multi-step cone-of-influence
/// (fanin / fanout) for the selected element. Pro feature.
///
/// Open-core ships a [NoopConeOfInfluenceService] that always returns an
/// empty overlay so the dispatch path is testable without the Pro
/// implementation present. The closed-source Pro overlay
/// registers a concrete `ProConeOfInfluenceService` via `proOverrides`
/// that performs depth-bounded BFS over the [LaidOutGraph] using the
/// shared port/edge connectivity already exposed by [SchematicGraph].
///
/// The contract is intentionally narrow: one method, one immutable
/// request, one immutable response. The dispatcher decides when to
/// invoke (typically after a `showConeOfInfluenceFanin` /
/// `showConeOfInfluenceFanout` action fires) and what to do with the
/// result (typically push it into `TraceOverlayNotifier`).
abstract interface class ConeOfInfluenceService {
  /// Computes the cone-of-influence overlay for [request]. Implementations
  /// must be pure functions of [request] — no side effects, no provider
  /// reads. The dispatcher hands the returned overlay to
  /// `TraceOverlayNotifier`.
  ///
  /// Returns [TraceOverlay.empty] for empty selections, empty graphs, or
  /// any other case the implementation cannot produce a meaningful trace
  /// for. Never throws.
  TraceOverlay compute(ConeOfInfluenceRequest request);

  /// Isolate-offload seam. Async variant
  /// the action dispatcher should prefer over [compute]. The open-core
  /// default runs [compute] inline (a completed future); the Pro overlay
  /// overrides this to offload a large trace to a background isolate so a
  /// 100K-cell scope does not lock the UI. Like [compute], never throws.
  Future<TraceOverlay> computeAsync(ConeOfInfluenceRequest request);
}

/// Open-core no-op default. Always returns [TraceOverlay.empty] so feature
/// gating short-circuits cleanly while the Pro overlay is not loaded.
class NoopConeOfInfluenceService implements ConeOfInfluenceService {
  /// Creates the open-core no-op default.
  const NoopConeOfInfluenceService();

  @override
  TraceOverlay compute(ConeOfInfluenceRequest request) => TraceOverlay.empty;

  @override
  Future<TraceOverlay> computeAsync(ConeOfInfluenceRequest request) async =>
      compute(request);
}
