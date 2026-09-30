// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/interfaces/x_trace_service.dart';
import 'package:netcrux/domain/models/trace/trace_overlay.dart';
import 'package:netcrux/features/project/providers/current_laid_out_graph_provider.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/features/viewer/providers/trace_overlay_notifier.dart';
import 'package:netcrux/features/viewer/providers/x_trace_in_flight_provider.dart';
import 'package:netcrux/features/viewer/providers/x_trace_result_notifier.dart';
import 'package:netcrux/services/schematic/x_trace_service_provider.dart';

/// Runs an X-trace back-cone walk for the active tab's selection, publishes
/// the chain and paints it — the single funnel every surface that starts or
/// ends a trace routes through, so the menu bar, the command palette, the
/// dock strip's Clear button and the Pro schematic context menu cannot drift
/// apart. Modelled on [`ConeOfInfluenceController`], for the same reason it
/// exists: when each surface implements the flow itself, the context-menu
/// path drifts from the palette path and forgets a step.
///
/// Reads and writes the tab-scoped viewer providers off a [ProviderContainer]
/// rather than a `WidgetRef`, so it works under split-pane / multi-tab and is
/// callable from a dock strip that has no dispatcher in scope. The tier gate
/// is the caller's responsibility — [run] executes only once activation is
/// permitted, which is why the *walk* is Pro while [clear] is not.
class XTraceController {
  /// Creates a controller bound to [_container] (an active tab container).
  const XTraceController(this._container);

  /// Convenience constructor mirroring the cone / trace controllers.
  factory XTraceController.fromContainer(ProviderContainer container) =>
      XTraceController(container);

  final ProviderContainer _container;

  /// Walks the back cone from the current selection, publishes the chain into
  /// the per-tab result provider, and paints the whole chain as a fanin
  /// overlay.
  ///
  /// Returns the resulting chain length, or `null` when there was nothing to
  /// walk (empty selection, or an empty / unavailable layout) so the caller
  /// can skip revealing a panel that would only show the empty state.
  Future<int?> run() async {
    final selection = _container.read(selectedElementProvider);
    if (selection.isEmpty) return null;
    final laidOut = _container.read(currentLaidOutGraphProvider).value;
    if (laidOut == null || laidOut.isEmpty) return null;
    final service = _container.read(xTraceServiceProvider);
    final inFlight = _container.read(xTraceInFlightProvider.notifier);
    // Read every notifier BEFORE the await: a `Ref` is invalid across an async
    // gap, and `lifecycle_ref_use_test` enforces it.
    final resultNotifier = _container.read(xTraceResultProvider.notifier);
    final overlayNotifier = _container.read(traceOverlayProvider.notifier);
    inFlight.set(running: true);
    final XTraceResult result;
    try {
      // Prefer the async seam so the Pro overlay can offload a large back-cone
      // walk to a background isolate; the open-core no-op resolves it inline.
      result = await service.traceAsync(
        XTraceRequest(laidOut: laidOut, selection: selection.primary),
      );
    } finally {
      inFlight.set(running: false);
    }
    resultNotifier.set(result);
    overlayNotifier.set(overlayFor(result));
    return result.chain.length;
  }

  /// Clears the chain AND the overlay it painted.
  ///
  /// Both halves matter: clearing only the result would leave the schematic
  /// dimmed around a cone the panel no longer lists. The panel itself stays
  /// open and falls back to its empty state — closing is the dock tab's `×`,
  /// which is a different affordance with a different meaning.
  void clear() {
    _container.read(xTraceResultProvider.notifier).clear();
    _container.read(traceOverlayProvider.notifier).clear();
  }
}

/// The schematic overlay for [result] — every edge, cell and boundary port the
/// chain visited, highlighted at full intensity with everything else dimmed.
///
/// `TraceOverlayMode.fanin` because a back cone *is* a fanin; this deliberately
/// reuses the cone-of-influence overlay machinery exactly as `XTraceStep`'s own
/// doc comment prescribes, so X-trace costs no new painting code. The coupling
/// that follows is accepted: `traceOverlayProvider` is shared with
/// cone-of-influence, so Escape (`clearOverlay`) and `clearConeOfInfluence`
/// both un-dim the canvas while the panel still lists the chain. Escape meaning
/// "un-dim" is consistent across the app, and the chain is not lost — a
/// dedicated X-trace overlay would instead require the painter to merge two
/// overlays, which is a canvas change for a cosmetic gain.
TraceOverlay overlayFor(XTraceResult result) {
  if (result.isEmpty) return TraceOverlay.empty;
  return TraceOverlay(
    mode: TraceOverlayMode.fanin,
    highlightedEdgeIds: <String>{
      for (final step in result.chain)
        if (step.edgeId.isNotEmpty) step.edgeId,
    },
    highlightedCellIds: <String>{
      for (final step in result.chain)
        if (step.cellId != null) step.cellId!,
    },
    highlightedBoundaryPortIds: <String>{
      for (final step in result.chain)
        if (step.boundaryPortId != null) step.boundaryPortId!,
    },
  );
}
