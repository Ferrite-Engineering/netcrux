// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:netcrux/domain/models/trace/trace_overlay.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'trace_overlay_notifier.g.dart';

/// Per-canvas tracing overlay.
///
/// The trace service computes the highlighted set from the current
/// selection + graph + mode, then writes it here. The painter watches
/// this provider; when non-empty, every cell / edge / port not in the
/// highlight set is rendered with the dim color from the design system.
@Riverpod(keepAlive: true)
class TraceOverlayNotifier extends _$TraceOverlayNotifier {
  @override
  TraceOverlay build() => TraceOverlay.empty;

  /// Replaces the overlay with [overlay].
  void set(TraceOverlay overlay) {
    if (state == overlay) return;
    state = overlay;
  }

  /// Clears the overlay — paint normally on the next frame.
  void clear() {
    if (state.isEmpty) return;
    state = TraceOverlay.empty;
  }
}
