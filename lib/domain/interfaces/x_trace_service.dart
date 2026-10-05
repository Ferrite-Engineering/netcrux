// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:netcrux/domain/models/schematic/laid_out_graph.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';

/// Why an [XTraceService.trace] traversal stopped.
///
/// The terminator is informational — the chain itself describes what was
/// visited; the reason lets the UI present a sensible status string
/// (e.g. "X origin reached", "depth limit reached", "no waveform
/// loaded").
enum XTraceTermination {
  /// The traversal found a cell that can produce an unknown by itself:
  /// **an** origin of the unknown propagation. The final [XTraceStep] in
  /// [XTraceResult.chain] is that origin, and [XTraceResult.originReason]
  /// says why it is one (an undriven or `x`-tied input, a register with no
  /// reset, or a cell with no driven inputs).
  ///
  /// Never "the origin". At a cell with several inputs the walk follows one
  /// of them, so the chain is a single route through a back-cone that
  /// usually has many, and a cone with several X inputs has other origins
  /// this result does not name. Copy rendering this value must not promise
  /// the cause — see `xTracePanelTerminationFoundOrigin`, which says
  /// "on this path" for exactly that reason.
  foundOrigin,

  /// The traversal hit the requested [XTraceRequest.maxDepth] before
  /// reaching an origin.
  maxDepthReached,

  /// The traversal terminated at a primary input / boundary port — the
  /// X propagates from outside the current scope and there is nothing
  /// further to walk in this view.
  reachedBoundary,

  /// The traversal could not produce a meaningful chain because no VCD
  /// was loaded and the pure-graph reachability fanned out without a
  /// stopping rule. Equivalent to [foundOrigin] in semantics but the
  /// caller may want to label it differently in the UI.
  noVcdLoaded,

  /// Combinational cycle detected — every port in the back-cone was
  /// already visited. The chain still describes the discovered loop so
  /// the engineer can inspect the cycle.
  cycleDetected,

  /// The selection had no traceable connectivity from which to start
  /// (e.g. an isolated cell selected, or an empty graph). The chain is
  /// empty.
  noTraceableSelection,
}

/// Why the cell a [XTraceTermination.foundOrigin] walk stopped at counts as
/// an origin of an unknown. Carried by [XTraceResult.originReason]; `null`
/// for every other termination.
enum XTraceOriginReason {
  /// An input of the cell is on a net nothing in the scope drives (the
  /// pin's tie is `PinTie.undriven`). [XTraceResult.originPortId] names it.
  undrivenInput,

  /// An input of the cell is tied to a constant with an `x` bit.
  /// [XTraceResult.originPortId] names it.
  xTiedInput,

  /// The cell is a register with no reset and no initial value, so it
  /// powers up unknown.
  registerWithoutReset,

  /// The cell has no driven inputs at all: it is a primary driver of its
  /// output in this scope.
  noDrivenInputs,
}

/// A single step on the X-trace causal chain.
///
/// Each step describes one element visited during the backward
/// traversal: the underlying net (carried by the edge that drove the
/// previous step), the cell that hosts the driver pin, and — when a
/// waveform is loaded — the value the net carried at the requested
/// simulation time. The earlier the step in [XTraceResult.chain] the
/// closer it is to the originally selected net; the last step is the
/// terminator (origin, boundary, cycle, depth limit).
///
/// Pure data: no Flutter imports, no callbacks. The Pro overlay
/// constructs these in `lib/features/x_trace/services/`.
@immutable
class XTraceStep {
  /// Creates a step.
  const XTraceStep({
    required this.depth,
    required this.netId,
    required this.edgeId,
    this.value,
    this.simulationTime,
    this.cellId,
    this.boundaryPortId,
  });

  /// Distance from the selection (0 = the selection itself; 1 = its
  /// immediate driver; …). Lets the UI render the chain as an indented
  /// list without recomputing depths.
  final int depth;

  /// The Yosys net id this step is on.
  final int netId;

  /// The laid-out-graph edge id this step traverses. The renderer can
  /// highlight this edge in the schematic (re-using the cone-of-
  /// influence overlay machinery).
  final String edgeId;

  /// The value the net held at [simulationTime]. `'x'` for unknown
  /// states, `null` when no VCD is loaded.
  final String? value;

  /// Simulation time the value was sampled at, in ticks. Mirrors
  /// [XTraceRequest.simulationTime] for the first step; for downstream
  /// steps the implementation may sample at the same tick (the natural
  /// case — "what fed this X at this exact time") or at the most-recent
  /// transition prior to that tick.
  final int? simulationTime;

  /// Cell id that hosts the driver pin reached at this step. `null` for
  /// boundary ports — see [boundaryPortId].
  final String? cellId;

  /// Boundary port id, if this step terminated at a module boundary
  /// (e.g. `'port:reset_n'`). Mutually exclusive with [cellId].
  final String? boundaryPortId;

  /// True when the value at this step is one of the X-family states.
  /// Cheap pre-computation so the renderer can colour the step.
  bool get isUnknown {
    final v = value;
    if (v == null) return false;
    if (v.isEmpty) return false;
    return v.contains('x') || v.contains('X');
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! XTraceStep) return false;
    return other.depth == depth &&
        other.netId == netId &&
        other.edgeId == edgeId &&
        other.value == value &&
        other.simulationTime == simulationTime &&
        other.cellId == cellId &&
        other.boundaryPortId == boundaryPortId;
  }

  @override
  int get hashCode => Object.hash(
    depth,
    netId,
    edgeId,
    value,
    simulationTime,
    cellId,
    boundaryPortId,
  );

  @override
  String toString() =>
      'XTraceStep(depth=$depth, net=$netId, edge=$edgeId, '
      'value=$value, cell=$cellId, boundary=$boundaryPortId)';
}

/// Request payload supplied to [XTraceService.trace].
///
/// Immutable so request shapes can be cached or compared cheaply by the
/// dispatcher and the result panel.
@immutable
class XTraceRequest {
  /// Creates an X-trace request.
  const XTraceRequest({
    required this.laidOut,
    required this.selection,
    this.simulationTime,
    this.maxDepth = defaultMaxDepth,
  });

  /// Default depth ceiling. Bounded so combinational-loop walks
  /// terminate even when [cycleDetected] paths are missed.
  static const int defaultMaxDepth = 64;

  /// The active scope's graph + layout.
  final LaidOutGraph laidOut;

  /// Element the trace radiates from (a net the user selected showing
  /// X, or a cell / port whose drivers we want to inspect).
  /// [SelectedElement.none] yields an empty chain.
  final SelectedElement selection;

  /// Simulation time (in ticks) the engineer wants to inspect. When
  /// `null`, the implementation falls back to pure-graph reachability.
  final int? simulationTime;

  /// Maximum chain length before bailing. Defaults to
  /// [defaultMaxDepth]. `0` short-circuits to [XTraceResult.empty].
  final int maxDepth;
}

/// Result returned by [XTraceService.trace].
///
/// Immutable so the result panel can compare two consecutive traces
/// and avoid repainting when nothing changed.
@immutable
class XTraceResult {
  /// Creates an X-trace result.
  const XTraceResult({
    required this.rootNetId,
    required this.chain,
    required this.termination,
    this.originReason,
    this.originPortId,
  });

  /// Empty result — the canonical "nothing to trace" snapshot.
  static const XTraceResult empty = XTraceResult(
    rootNetId: null,
    chain: <XTraceStep>[],
    termination: XTraceTermination.noTraceableSelection,
  );

  /// Yosys net id the trace started from, or `null` when the selection
  /// did not resolve to a single net (e.g. a cell with multiple
  /// outputs and no specific port).
  final int? rootNetId;

  /// Ordered list of steps from the selection outward to the
  /// terminator. May be empty (e.g. for [XTraceTermination.noTraceableSelection]).
  final List<XTraceStep> chain;

  /// Why the traversal stopped.
  final XTraceTermination termination;

  /// For [XTraceTermination.foundOrigin], why the last cell is an origin.
  /// `null` for every other termination, and from implementations that do
  /// not classify their origins.
  final XTraceOriginReason? originReason;

  /// For [XTraceOriginReason.undrivenInput] and
  /// [XTraceOriginReason.xTiedInput], the `<cellName>:<portName>` id of the
  /// input that is the source. `null` otherwise.
  final String? originPortId;

  /// True when the chain has no steps.
  bool get isEmpty => chain.isEmpty;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! XTraceResult) return false;
    if (other.rootNetId != rootNetId) return false;
    if (other.termination != termination) return false;
    if (other.originReason != originReason) return false;
    if (other.originPortId != originPortId) return false;
    if (other.chain.length != chain.length) return false;
    for (var i = 0; i < chain.length; i++) {
      if (other.chain[i] != chain[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    rootNetId,
    termination,
    originReason,
    originPortId,
    Object.hashAll(chain),
  );

  @override
  String toString() =>
      'XTraceResult(root=$rootNetId, '
      'chain.length=${chain.length}, termination=$termination, '
      'origin=$originReason $originPortId)';
}

/// Extension-point service that walks backward through driver
/// connectivity to find the origin of an `x` value on a net at a given
/// simulation time. Pro feature.
///
/// Open-core ships a [NoopXTraceService] default that always returns
/// [XTraceResult.empty] so the dispatch path (workspace screen →
/// service → results panel) is exercised without the Pro implementation
/// present. The closed-source Pro overlay registers a
/// concrete `ProXTraceService` via `proOverrides` that traverses the
/// laid-out graph's driving cone and (when a VCD is loaded) samples
/// signal values at the requested simulation time.
///
/// The contract is intentionally narrow: one method, one immutable
/// request, one immutable response. The dispatcher decides when to
/// invoke (typically when the `NetcruxAction.showXTrace` action fires
/// on a selected net) and what to do with the result (typically push it
/// into an `XTraceResultNotifier`).
abstract interface class XTraceService {
  /// Computes the X-trace chain for [request]. Implementations must be
  /// pure functions of [request] — no side effects, no provider reads.
  /// The dispatcher reads the active tab's selection / laid-out graph
  /// / cursor time and hands them in.
  ///
  /// Returns [XTraceResult.empty] for empty selections, empty graphs,
  /// or any other case the implementation cannot produce a meaningful
  /// trace for. Never throws.
  XTraceResult trace(XTraceRequest request);

  /// Isolate-offload seam. Async variant
  /// the action dispatcher should prefer over [trace]. The open-core default
  /// runs [trace] inline; the Pro overlay overrides this to offload a large
  /// back-cone walk to a background isolate so a 100K-cell scope does not
  /// lock the UI. Like [trace], never throws.
  Future<XTraceResult> traceAsync(XTraceRequest request);
}

/// Open-core no-op default. Always returns [XTraceResult.empty] so
/// feature gating short-circuits cleanly while the Pro overlay is not
/// loaded.
class NoopXTraceService implements XTraceService {
  /// Creates the open-core no-op default.
  const NoopXTraceService();

  @override
  XTraceResult trace(XTraceRequest request) => XTraceResult.empty;

  @override
  Future<XTraceResult> traceAsync(XTraceRequest request) async =>
      trace(request);
}
