// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/interfaces/x_trace_service.dart';
import 'package:netcrux/features/viewer/providers/x_trace_result_notifier.dart';

void main() {
  group('XTraceResultNotifier', () {
    test('default state is XTraceResult.empty', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(xTraceResultProvider), XTraceResult.empty);
    });

    test('set publishes a non-empty result', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      const result = XTraceResult(
        rootNetId: 3,
        chain: <XTraceStep>[
          XTraceStep(depth: 0, netId: 3, edgeId: 'e_3', value: 'x'),
        ],
        termination: XTraceTermination.foundOrigin,
      );
      container.read(xTraceResultProvider.notifier).set(result);
      expect(container.read(xTraceResultProvider), result);
    });

    test('set is a no-op when state is unchanged', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      const result = XTraceResult(
        rootNetId: 7,
        chain: <XTraceStep>[
          XTraceStep(depth: 0, netId: 7, edgeId: 'e_7', value: 'x'),
        ],
        termination: XTraceTermination.reachedBoundary,
      );
      container.read(xTraceResultProvider.notifier).set(result);
      // Same value again — must not produce a fresh state.
      final before = container.read(xTraceResultProvider);
      container.read(xTraceResultProvider.notifier).set(result);
      final after = container.read(xTraceResultProvider);
      expect(identical(before, after), isTrue);
    });

    test('clear resets to XTraceResult.empty', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      const result = XTraceResult(
        rootNetId: 11,
        chain: <XTraceStep>[],
        termination: XTraceTermination.cycleDetected,
      );
      container.read(xTraceResultProvider.notifier).set(result);
      container.read(xTraceResultProvider.notifier).clear();
      expect(container.read(xTraceResultProvider), XTraceResult.empty);
    });

    test('clear on already-empty state is a no-op', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final before = container.read(xTraceResultProvider);
      container.read(xTraceResultProvider.notifier).clear();
      final after = container.read(xTraceResultProvider);
      expect(identical(before, after), isTrue);
    });
  });
}
