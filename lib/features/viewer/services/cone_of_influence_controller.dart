// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/interfaces/cone_of_influence_service.dart';
import 'package:netcrux/domain/models/layout/bounding_box.dart';
import 'package:netcrux/domain/models/schematic/laid_out_graph.dart';
import 'package:netcrux/domain/models/trace/trace_overlay.dart';
import 'package:netcrux/features/project/providers/current_laid_out_graph_provider.dart';
import 'package:netcrux/features/viewer/providers/schematic_canvas_key_provider.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/features/viewer/providers/trace_overlay_notifier.dart';
import 'package:netcrux/features/viewer/providers/viewport_transform_notifier.dart';
import 'package:netcrux/services/schematic/cone_of_influence_service_provider.dart';

/// Runs a cone-of-influence (fanin / fanout) trace for the active tab's
/// selection, paints it, and FRAMES it — the single funnel both the
/// command-palette / menu-bar action (`WorkspaceActionDispatcher`) and the
/// schematic context-menu entries route through, so every surface that
/// starts a cone gets the same painting, fit-to-cone, and cell-count
/// readout.
///
/// Reads and writes the tab-scoped viewer providers off a [ProviderContainer]
/// (mirrors [TraceOverlayController.fromContainer]) so it works under
/// split-pane / multi-tab without a [WidgetRef]. The tier gate is the
/// caller's responsibility — this runs only once activation is permitted.
class ConeOfInfluenceController {
  /// Creates a controller bound to [_container] (an active tab container).
  const ConeOfInfluenceController(this._container);

  /// Convenience constructor mirroring the trace controller's factory.
  factory ConeOfInfluenceController.fromContainer(
    ProviderContainer container,
  ) => ConeOfInfluenceController(container);

  final ProviderContainer _container;

  /// Computes the cone for the current selection in [mode], paints it into
  /// the trace overlay, and fits the viewport to the cone's bounds.
  ///
  /// Returns the number of cells in the cone, or `null` when there was
  /// nothing to compute (empty selection or an empty / unavailable layout)
  /// so the caller can skip the "N cells in cone" readout.
  Future<int?> run(ConeOfInfluenceMode mode) async {
    final selection = _container.read(selectedElementProvider);
    if (selection.isEmpty) return null;
    final laidOut = _container.read(currentLaidOutGraphProvider).value;
    if (laidOut == null || laidOut.isEmpty) return null;
    final service = _container.read(coneOfInfluenceServiceProvider);
    // Prefer the async seam so the Pro overlay can offload a large trace to
    // a background isolate; the open-core default resolves it inline.
    final overlay = await service.computeAsync(
      ConeOfInfluenceRequest(
        laidOut: laidOut,
        selection: selection.primary,
        mode: mode,
        depth: null,
      ),
    );
    _container.read(traceOverlayProvider.notifier).set(overlay);
    _fitToCone(laidOut, overlay);
    return overlay.highlightedCellIds.length;
  }

  /// Frames the cone (the set of highlighted cells) in the viewport. No-op
  /// when the cone is empty or the canvas isn't laid out / mounted.
  void _fitToCone(LaidOutGraph laidOut, TraceOverlay overlay) {
    if (overlay.highlightedCellIds.isEmpty) return;
    final bounds = coneBounds(laidOut, overlay.highlightedCellIds);
    if (bounds == null) return;
    final size = _liveCanvasSize();
    if (size == null) return;
    _container
        .read(viewportTransformProvider.notifier)
        .revealBounds(size, bounds);
  }

  /// The union of the layout bounds of [cellIds] in [laidOut], or `null`
  /// when none of them resolve to a laid-out node. Pure — exposed for tests.
  static BoundingBox? coneBounds(LaidOutGraph laidOut, Set<String> cellIds) {
    return BoundingBox.encompass(<BoundingBox>[
      for (final id in cellIds)
        if (laidOut.layout.findNode(id) case final node?) node.bounds,
    ]);
  }

  /// The active canvas' live on-screen size, read off the per-tab canvas
  /// render object (the same key the PNG export + "Fit All" use). Null when
  /// the canvas isn't mounted / laid out yet.
  Size? _liveCanvasSize() {
    final box = _container
        .read(schematicCanvasKeyProvider)
        .currentContext
        ?.findRenderObject();
    if (box is RenderBox && box.hasSize && !box.size.isEmpty) {
      return box.size;
    }
    return null;
  }
}
