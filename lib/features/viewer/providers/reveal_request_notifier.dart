// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'reveal_request_notifier.g.dart';

/// A pending "reveal this cell" request — the id of a cell the viewport
/// should center on as soon as the owning scope's layout is available.
///
/// Search (and any future jump-to-element source) writes the target here
/// rather than driving the camera imperatively, because selecting a result
/// in a different scope re-elaborates and re-lays-out that scope
/// asynchronously. A direct `fitToBounds` at click time would frame the
/// OLD scope (the target cell isn't laid out yet), so the request is parked
/// here and the gesture handler — which owns the canvas `RenderBox` and
/// watches [`currentLaidOutGraphProvider`] — consumes it once the target
/// cell appears in the laid-out graph, then clears it.
///
/// Scoped per-tab (see [`netcruxTabOverridesFactory`]) alongside
/// [`viewportTransformProvider`] and [`selectedElementProvider`] so a reveal
/// acts on the focused tab's canvas.
@Riverpod(keepAlive: true)
class RevealRequestNotifier extends _$RevealRequestNotifier {
  @override
  String? build() => null;

  /// Requests that the viewport reveal the cell with [cellId] once its
  /// scope's layout is laid out. Replaces any prior unsatisfied request.
  void request(String cellId) {
    if (state == cellId) return;
    state = cellId;
  }

  /// Clears a satisfied (or abandoned) request.
  void clear() {
    if (state == null) return;
    state = null;
  }
}
