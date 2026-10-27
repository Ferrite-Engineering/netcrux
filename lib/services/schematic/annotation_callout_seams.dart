// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';

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
