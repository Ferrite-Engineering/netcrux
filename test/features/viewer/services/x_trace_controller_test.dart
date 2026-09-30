// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/interfaces/x_trace_service.dart';
import 'package:netcrux/domain/models/trace/trace_overlay.dart';
import 'package:netcrux/features/viewer/providers/trace_overlay_notifier.dart';
import 'package:netcrux/features/viewer/providers/x_trace_result_notifier.dart';
import 'package:netcrux/features/viewer/services/x_trace_controller.dart';

XTraceResult _chain() => const XTraceResult(
  rootNetId: 7,
  chain: <XTraceStep>[
    XTraceStep(depth: 0, netId: 7, edgeId: 'e7', cellId: 'buf1'),
    XTraceStep(depth: 1, netId: 4, edgeId: 'e4', cellId: 'buf0'),
    XTraceStep(depth: 2, netId: 1, edgeId: 'e1', boundaryPortId: 'port:d_in'),
  ],
  termination: XTraceTermination.reachedBoundary,
);

void main() {
  group('overlayFor', () {
    test('highlights every edge, cell and boundary port in the chain', () {
      final overlay = overlayFor(_chain());
      expect(overlay.mode, TraceOverlayMode.fanin);
      expect(overlay.highlightedEdgeIds, {'e7', 'e4', 'e1'});
      expect(overlay.highlightedCellIds, {'buf1', 'buf0'});
      expect(overlay.highlightedBoundaryPortIds, {'port:d_in'});
    });

    test('an empty result paints nothing rather than dimming everything', () {
      // A `TraceOverlay` with a mode but no highlights would dim the whole
      // canvas — worse than no overlay at all.
      expect(overlayFor(XTraceResult.empty), TraceOverlay.empty);
      expect(overlayFor(XTraceResult.empty).isEmpty, isTrue);
    });

    test('a back cone is a fanin, so it reuses the cone-of-influence mode', () {
      expect(overlayFor(_chain()).mode, TraceOverlayMode.fanin);
    });
  });

  group('clear', () {
    test('empties the result AND the overlay it painted', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(xTraceResultProvider.notifier).set(_chain());
      container.read(traceOverlayProvider.notifier).set(overlayFor(_chain()));

      XTraceController.fromContainer(container).clear();

      expect(container.read(xTraceResultProvider).isEmpty, isTrue);
      // Clearing only the result would leave the schematic dimmed around a
      // cone the panel no longer lists.
      expect(container.read(traceOverlayProvider).isEmpty, isTrue);
    });
  });
}
