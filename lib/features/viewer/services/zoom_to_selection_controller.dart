// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/domain/models/trace/trace_overlay.dart';
import 'package:netcrux/features/project/providers/current_laid_out_graph_provider.dart';
import 'package:netcrux/features/viewer/providers/schematic_canvas_key_provider.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/features/viewer/providers/trace_overlay_notifier.dart';
import 'package:netcrux/features/viewer/providers/viewport_transform_notifier.dart';
import 'package:netcrux/features/viewer/selection/selection_bounds.dart';

/// Zoom to Selection for one tab: frames the selection and, while a trace
/// overlay is active, everything the overlay highlights.
///
/// Uses the same reveal fit a search-result jump and a cone-of-influence
/// trace use ([ViewportTransformNotifier.revealBounds]), so a lone cell
/// lands at a readable zoom and a wide trace fits with a margin. Reads and
/// writes the tab-scoped providers off a [ProviderContainer] (the active tab
/// container), the way [ConeOfInfluenceController] does.
class ZoomToSelectionController {
  /// Creates a controller bound to [_container], an active tab container.
  const ZoomToSelectionController(this._container);

  final ProviderContainer _container;

  /// Frames the selection in [viewport], or in the canvas' live on-screen
  /// size when [viewport] is null. Returns false, leaving the camera alone,
  /// when nothing is selected, nothing resolves to laid-out geometry, or the
  /// canvas is not laid out.
  ///
  /// With [only], frames just those elements of a larger selection (and not
  /// the trace overlay), such as one register of a selected timing path.
  bool run({Size? viewport, Set<SelectedElement>? only}) {
    // Selection first: with nothing selected there is nothing to frame, and
    // reading the laid-out graph would start a layout nobody asked for.
    final selection = only ?? _container.read(selectedElementProvider).elements;
    if (selection.isEmpty) return false;
    final laidOut = _container.read(currentLaidOutGraphProvider).value;
    if (laidOut == null) return false;
    final bounds = selectionBounds(
      laidOut,
      selection: selection,
      overlay: only == null
          ? _container.read(traceOverlayProvider)
          : TraceOverlay.empty,
    );
    final size = viewport ?? _liveCanvasSize();
    if (bounds == null || size == null) return false;
    _container
        .read(viewportTransformProvider.notifier)
        .revealBounds(size, bounds);
    return true;
  }

  /// The canvas' live on-screen size, read off the per-tab canvas render
  /// object (the same key the PNG export and Zoom to Fit use). Null while
  /// the canvas is not mounted or laid out.
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
