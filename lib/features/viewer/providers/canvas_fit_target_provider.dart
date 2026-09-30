// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/models/layout/bounding_box.dart';

/// The information a chrome-level "Fit to screen" needs: the laid-out
/// [bounds] to frame, paired with the canvas viewport [size] measured when
/// the target was last published.
///
/// The [size] is only a FALLBACK: it is refreshed when the gesture handler
/// rebuilds (a scope change), so it lags a window/pane resize or panel
/// toggle. The chrome-level fit (`WorkspaceActionDispatcher.zoomFitAll`)
/// therefore measures the viewport live off the canvas render object and
/// uses this cached [size] only when that render object is unavailable. The
/// [bounds] carry no such caveat — they change only on a scope change, when
/// the handler does rebuild.
typedef CanvasFitTarget = ({Size size, BoundingBox bounds});

/// The active tab's schematic fit target — the measured canvas viewport
/// size and the current scope's laid-out bounds.
///
/// Published by [SchematicGestureHandler] (which owns the canvas
/// `RenderBox`, so knows its size, and watches the laid-out graph, so
/// knows the bounds) so that code running *outside* the canvas render
/// tree — chiefly the toolbar / palette "Fit to screen" action dispatched
/// from the workspace chrome — can frame the design against the real
/// viewport. The gesture handler's own `0`-key fit reads the size straight
/// off its render object; the toolbar button has no such render object in
/// scope, hence this seam.
///
/// Deliberately a plain synchronous value: the dispatcher must NOT reach
/// through to the async `currentLaidOutGraphProvider` (reading it kicks
/// off elaboration / layout and schedules work), so the bounds are pushed
/// here instead of pulled there.
///
/// Scoped per-tab like [viewportTransformProvider]: resolved from the
/// active tab's `ProviderContainer`, so the fit acts on the focused tab.
class CanvasFitTargetNotifier extends Notifier<CanvasFitTarget?> {
  @override
  CanvasFitTarget? build() => null;

  /// Records the latest measured canvas [size] and laid-out [bounds]. A
  /// no-op when unchanged so the frequent post-frame republish from the
  /// gesture handler doesn't churn listeners.
  void set(Size size, BoundingBox bounds) {
    final next = (size: size, bounds: bounds);
    if (state == next) return;
    state = next;
  }
}

/// Holds the active tab's schematic fit target, or `null` before the
/// canvas has been laid out.
final canvasFitTargetProvider =
    NotifierProvider<CanvasFitTargetNotifier, CanvasFitTarget?>(
      CanvasFitTargetNotifier.new,
    );
