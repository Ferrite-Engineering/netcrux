// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:netcrux/domain/models/schematic/laid_out_graph.dart';
import 'package:netcrux/domain/models/selection/selection.dart';
import 'package:netcrux/domain/models/trace/trace_overlay.dart';
import 'package:netcrux/features/project/providers/current_laid_out_graph_provider.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/features/viewer/providers/trace_overlay_notifier.dart';
import 'package:netcrux/services/schematic/trace_service.dart';

/// Thin facade that wires the [TraceService] into the viewer's
/// providers. Pulled out of `ProjectScreen` so the dispatch path
/// stays declarative (action → controller method) and so the
/// service can be exercised in a `ProviderContainer` without
/// pumping the full screen.
class TraceOverlayController {
  /// Creates a controller that reads from a [WidgetRef].
  ///
  /// Use this constructor inside a tab-scoped widget tree (gesture
  /// handlers, context-menu controllers) where the surrounding
  /// `UncontrolledProviderScope` already resolves [WidgetRef] to the
  /// active tab's container.
  TraceOverlayController(WidgetRef ref) : _widgetRef = ref, _container = null;

  /// Creates a controller that reads from a raw [ProviderContainer].
  ///
  /// Use this constructor outside the tab widget tree (workspace-screen
  /// command dispatcher, CLI launch intent) and pass the active tab's
  /// container so the per-tab selection / laid-out graph / overlay
  /// providers resolve correctly.
  TraceOverlayController.fromContainer(ProviderContainer container)
    : _widgetRef = null,
      _container = container;

  final WidgetRef? _widgetRef;
  final ProviderContainer? _container;

  /// Service used for the fanin/fanout computation. Kept as a const
  /// instance because the service is stateless.
  static const TraceService _service = TraceService();

  /// Computes and publishes the fanin overlay for the current
  /// selection. No-op when there is no selection.
  void showFanin() => _publish(TraceOverlayMode.fanin);

  /// Computes and publishes the fanout overlay.
  void showFanout() => _publish(TraceOverlayMode.fanout);

  T _read<T>(ProviderListenable<T> provider) {
    final container = _container;
    if (container != null) return container.read(provider);
    return _widgetRef!.read(provider);
  }

  void _publish(TraceOverlayMode mode) {
    final selection = _read<Selection>(selectedElementProvider);
    if (selection.isEmpty) return;
    final laidOut = _read<AsyncValue<LaidOutGraph>>(
      currentLaidOutGraphProvider,
    ).value;
    if (laidOut == null || laidOut.isEmpty) return;
    final overlay = _service.compute(
      laidOut: laidOut,
      // Trace anchors on the primary selection — when the user has
      // multi-selected, the most recently clicked element drives the
      // overlay (mirrors the inspector's "follow the click" rule).
      selection: selection.primary,
      mode: mode,
    );
    _read<TraceOverlayNotifier>(traceOverlayProvider.notifier).set(overlay);
  }
}
