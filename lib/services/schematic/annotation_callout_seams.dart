// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shows or hides the annotation callouts on the active tab's schematic.
///
/// Drawing the notes on the canvas is a NetCrux Pro capability, so open core
/// resolves [toggleAnnotationCalloutsOpenerProvider] to null and the action
/// that reaches it answers with the "requires NetCrux Pro" notice instead of
/// doing nothing. Moving callouts to open core is overriding this and
/// [schematicCalloutLayerBuilderProvider] here rather than in the overlay.
typedef ToggleAnnotationCalloutsOpener = void Function(BuildContext context);

/// The overlay's [ToggleAnnotationCalloutsOpener]; null in open core.
final Provider<ToggleAnnotationCalloutsOpener?>
toggleAnnotationCalloutsOpenerProvider =
    Provider<ToggleAnnotationCalloutsOpener?>(
      (_) => null,
      name: 'toggleAnnotationCalloutsOpenerProvider',
    );

/// Builds the layer drawn over the schematic canvas that carries the
/// annotation callouts, or null in open core, where the canvas draws none.
///
/// The layer is laid out over the canvas, inside the canvas gesture handler,
/// so a pointer that misses every callout still pans, zooms and selects. A
/// callout that takes a pointer claims it through
/// [canvasOverlayGestureClaimProvider].
final Provider<WidgetBuilder?> schematicCalloutLayerBuilderProvider =
    Provider<WidgetBuilder?>(
      (_) => null,
      name: 'schematicCalloutLayerBuilderProvider',
    );

/// Whether something drawn over the schematic (a callout being dragged,
/// tapped or right-clicked) owns the current pointer sequence.
///
/// The canvas gesture handler reads raw pointer events through a `Listener`,
/// which sees every event in its subtree whatever wins the gesture arena; a
/// callout's own gesture detector therefore cannot stop a label drag from also
/// panning the canvas, or a click on it from selecting what lies beneath. The
/// callout sets this on pointer-down and clears it, on a microtask, after
/// pointer-up; the handler ignores pointers while it is set.
final NotifierProvider<CanvasOverlayGestureClaim, bool>
canvasOverlayGestureClaimProvider =
    NotifierProvider<CanvasOverlayGestureClaim, bool>(
      CanvasOverlayGestureClaim.new,
      name: 'canvasOverlayGestureClaimProvider',
    );

/// The flag behind [canvasOverlayGestureClaimProvider].
class CanvasOverlayGestureClaim extends Notifier<bool> {
  @override
  bool build() => false;

  /// Whether a canvas overlay owns the pointer.
  bool get active => state;

  /// Claims (`true`) or releases (`false`) the pointer.
  set active(bool value) {
    if (state != value) state = value;
  }
}
