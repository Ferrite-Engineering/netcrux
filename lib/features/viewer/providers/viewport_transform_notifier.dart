// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';
import 'package:netcrux/domain/models/layout/bounding_box.dart';
import 'package:netcrux/features/viewer/rendering/schematic_painter.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'viewport_transform_notifier.g.dart';

/// Per-canvas pan / zoom state.
///
/// Holds the current [ViewportTransform] (zoom + offset) the
/// [SchematicCanvasRenderObject] paints under. The gesture handler
/// calls into this notifier; the canvas widget watches the provider
/// and forwards the transform to the render object on rebuild.
///
/// Declared at root and re-bound per tab by `netcrux_tab_overrides.dart`,
/// so every tab keeps its own camera.
@Riverpod(keepAlive: true)
class ViewportTransformNotifier extends _$ViewportTransformNotifier {
  @override
  ViewportTransform build() => ViewportTransform.identity;

  /// The design bounds the current transform is a whole-design fit of, or
  /// null once the camera has been moved by hand.
  ///
  /// This is what makes a resize do the right thing without asking. A view
  /// nobody has touched since "fit" is showing *the design*, so growing the
  /// pane should keep showing the design — bigger. A view the user panned or
  /// zoomed is showing *a place at a scale they chose*, and re-fitting it
  /// would throw that away.
  BoundingBox? _fittedBounds;

  /// The viewport size the canvas last reported, through a fit, a reveal or
  /// a resize. What [zoomAboutCenter] anchors on; `null` until the canvas
  /// has laid out once.
  Size? _viewport;

  /// Whether the transform is still the untouched result of a fit.
  @visibleForTesting
  bool get isFitted => _fittedBounds != null;

  /// A camera waiting to be reinstated when the layout of the scope at the
  /// given path lands — a restored session's view. See [requestRestore].
  ({List<String> scopePath, ViewportTransform transform})? _pendingRestore;

  /// Asks the canvas to reinstate [transform] instead of fitting the design
  /// the next time a layout lands, provided that layout is the scope at
  /// [scopePath]. Replaces any earlier request.
  void requestRestore(List<String> scopePath, ViewportTransform transform) {
    _pendingRestore = (
      scopePath: List<String>.unmodifiable(scopePath),
      transform: transform,
    );
  }

  /// Consumes the pending restore for a layout of [scopePath] that just
  /// landed: returns its camera when the request was for that scope, and
  /// `null` otherwise. Either way the request is spent — a layout of a
  /// different scope means the user has moved on, and a camera applied to a
  /// later visit would be a surprise.
  ViewportTransform? takePendingRestore(List<String> scopePath) {
    final pending = _pendingRestore;
    _pendingRestore = null;
    if (pending == null) return null;
    if (pending.scopePath.length != scopePath.length) return null;
    for (var i = 0; i < scopePath.length; i++) {
      if (pending.scopePath[i] != scopePath[i]) return null;
    }
    return pending.transform;
  }

  /// Sets the camera to exactly [transform], clamping the zoom. The view is
  /// then the user's, not a fit, so a resize keeps it rather than refitting.
  void restore(ViewportTransform transform) {
    _fittedBounds = null;
    state = ViewportTransform(
      zoom: SchematicViewportLimits.clampZoom(transform.zoom),
      offset: transform.offset,
    );
  }

  /// Translates the view by [delta] screen-space pixels (positive
  /// values move the design to the right / down).
  void pan(Offset delta) {
    _fittedBounds = null;
    state = ViewportTransform(
      zoom: state.zoom,
      offset: state.offset + delta,
    );
  }

  /// Sets zoom directly, clamped to the painter's hard limits.
  /// Useful for "Fit All" and "100%" actions where the gesture
  /// handler computes the target zoom and we don't want it to drift
  /// out of bounds.
  /// Zooms by [factor] about the centre of the viewport, the anchor a step
  /// zoom from the toolbar, a menu, the palette or a global shortcut needs:
  /// keeping the offset stable, which [setZoom] does, means zooming about
  /// the design origin, and far from the origin in a large scope every step
  /// threw the view sideways. Falls back to [setZoom] before the canvas has
  /// reported a size.
  void zoomAboutCenter(double factor) {
    final viewport = _viewport;
    if (viewport == null) {
      setZoom(state.zoom * factor);
      return;
    }
    zoomAt(Offset(viewport.width / 2, viewport.height / 2), factor);
  }

  void setZoom(double zoom) {
    final clamped = SchematicViewportLimits.clampZoom(zoom);
    if (clamped == state.zoom) return;
    _fittedBounds = null;
    state = ViewportTransform(zoom: clamped, offset: state.offset);
  }

  /// Multiplies the current zoom by [factor] while keeping the
  /// design point under [focalPoint] (a canvas-local Offset) visually
  /// stationary. This is the operation the wheel-zoom and pinch-zoom
  /// gestures actually need.
  ///
  /// Given a canvas pixel `p` and a transform `(z, o)`, the design
  /// coordinate is `(p - o) / z`. To preserve that coordinate across
  /// a new zoom `z'`, the new offset must satisfy
  /// `p - o' = z' * (p - o) / z`, which simplifies to
  /// `o' = p - (z' / z) * (p - o)`.
  void zoomAt(Offset focalPoint, double factor) {
    final currentZoom = state.zoom;
    final nextZoom = SchematicViewportLimits.clampZoom(currentZoom * factor);
    if (nextZoom == currentZoom) return;
    _fittedBounds = null;
    final ratio = nextZoom / currentZoom;
    final newOffset = focalPoint - (focalPoint - state.offset) * ratio;
    state = ViewportTransform(zoom: nextZoom, offset: newOffset);
  }

  /// Resets to the identity transform (1.0 zoom, origin offset).
  void reset() {
    _fittedBounds = null;
    if (state == ViewportTransform.identity) return;
    state = ViewportTransform.identity;
  }

  /// Fits the design [bounds] into a [viewport] of the given size, centered,
  /// with a small margin ([padding] = fraction of the viewport the content
  /// fills). This is the real "Fit All" / open-a-scope behaviour: pick the
  /// uniform zoom that makes the whole layout visible, then offset so the
  /// content centre lands at the viewport centre.
  ///
  /// `screen = design * zoom + offset` (offset is post-scale translation),
  /// so centring means `offset = viewportCentre - contentCentre * zoom`.
  /// No-ops on a degenerate viewport or empty bounds so the caller can
  /// invoke it unconditionally when a layout loads.
  void fitToBounds(
    Size viewport,
    BoundingBox bounds, {
    double padding = 0.9,
  }) {
    if (viewport.width <= 0 ||
        viewport.height <= 0 ||
        bounds.width <= 0 ||
        bounds.height <= 0) {
      return;
    }
    _viewport = viewport;
    final zoomX = viewport.width / bounds.width;
    final zoomY = viewport.height / bounds.height;
    final fit = SchematicViewportLimits.clampZoom(
      (zoomX < zoomY ? zoomX : zoomY) * padding,
    );
    final centerX = bounds.x + bounds.width / 2;
    final centerY = bounds.y + bounds.height / 2;
    final offset = Offset(
      viewport.width / 2 - centerX * fit,
      viewport.height / 2 - centerY * fit,
    );
    _fittedBounds = bounds;
    _fitPadding = padding;
    state = ViewportTransform(zoom: fit, offset: offset);
  }

  /// Padding the live fit was computed with, so a resize reproduces it.
  double _fitPadding = 0.9;

  /// Re-aims the camera after the canvas changes size — a window resize or a
  /// panel-splitter drag.
  ///
  /// Two cases, and the difference is whether the user has moved the camera:
  ///
  ///   * **Still fitted** (nothing panned or zoomed since the last fit): the
  ///     design is re-fitted to the new viewport, so a wider pane shows the
  ///     same design larger rather than the same design plus empty space.
  ///   * **Moved by hand**: zoom is left exactly as the user set it and the
  ///     design point under the old viewport centre is kept under the new
  ///     one. This is what every canvas tool does — a resize reveals more or
  ///     less of the design, it does not rescale what you were looking at.
  ///
  /// Without this the offset is absolute, so growing the canvas pinned the
  /// design to the top-left corner and shrinking it pushed the design out of
  /// view — the resize appeared to do nothing at all.
  void handleViewportResize(Size oldViewport, Size newViewport) {
    if (newViewport.width <= 0 || newViewport.height <= 0) return;
    _viewport = newViewport;
    if (oldViewport == newViewport) return;

    final fitted = _fittedBounds;
    if (fitted != null) {
      fitToBounds(newViewport, fitted, padding: _fitPadding);
      return;
    }

    if (oldViewport.width <= 0 || oldViewport.height <= 0) return;
    final recenter = Offset(
      (newViewport.width - oldViewport.width) / 2,
      (newViewport.height - oldViewport.height) / 2,
    );
    state = ViewportTransform(
      zoom: state.zoom,
      offset: state.offset + recenter,
    );
  }

  /// Centers the viewport on [target] (design-space bounds) and zooms so the
  /// target is comfortably on-screen — the "reveal / jump to element"
  /// operation a search-result click (or a fit-to-cone) needs in a design
  /// too large to eyeball.
  ///
  /// Unlike [fitToBounds] — which frames the WHOLE design and would slam a
  /// single small cell to [SchematicViewportLimits.maxZoom] — this caps the
  /// zoom at [comfortZoom] so a tiny cell lands at a readable scale, while a
  /// larger [target] (e.g. a fan-out cone's union bounds) still fits with a
  /// [padding] margin. No-ops on a degenerate viewport or empty [target] so
  /// the caller can invoke it unconditionally.
  void revealBounds(
    Size viewport,
    BoundingBox target, {
    double comfortZoom = 1.5,
    double padding = 0.6,
  }) {
    if (viewport.width <= 0 ||
        viewport.height <= 0 ||
        target.width <= 0 ||
        target.height <= 0) {
      return;
    }
    _viewport = viewport;
    final zoomX = viewport.width / target.width;
    final zoomY = viewport.height / target.height;
    final fitZoom = (zoomX < zoomY ? zoomX : zoomY) * padding;
    final zoom = SchematicViewportLimits.clampZoom(
      fitZoom < comfortZoom ? fitZoom : comfortZoom,
    );
    final centerX = target.x + target.width / 2;
    final centerY = target.y + target.height / 2;
    // A reveal frames one element, not the design — a later resize must keep
    // the user on that element rather than pulling back to the whole scope.
    _fittedBounds = null;
    state = ViewportTransform(
      zoom: zoom,
      offset: Offset(
        viewport.width / 2 - centerX * zoom,
        viewport.height / 2 - centerY * zoom,
      ),
    );
  }
}
