// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/features/viewer/providers/pane_render_stats.dart';

void main() {
  group('PaneRenderStats', () {
    test('empty has zero counters', () {
      const empty = PaneRenderStats.empty;
      expect(empty.frameNumber, 0);
      expect(empty.paintMicroseconds, 0);
      expect(empty.visibleCells, 0);
      expect(empty.visibleEdges, 0);
      expect(empty.totalCells, 0);
      expect(empty.totalEdges, 0);
    });

    test('equality compares all observable fields', () {
      const a = PaneRenderStats(
        frameNumber: 1,
        paintMicroseconds: 200,
        visibleCells: 3,
        visibleEdges: 4,
        totalCells: 5,
        totalEdges: 6,
      );
      const b = PaneRenderStats(
        frameNumber: 1,
        paintMicroseconds: 200,
        visibleCells: 3,
        visibleEdges: 4,
        totalCells: 5,
        totalEdges: 6,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('copyWith replaces individual fields', () {
      const initial = PaneRenderStats(
        frameNumber: 1,
        paintMicroseconds: 200,
        visibleCells: 3,
        visibleEdges: 4,
        totalCells: 5,
        totalEdges: 6,
      );
      final copy = initial.copyWith(visibleCells: 10);
      expect(copy.visibleCells, 10);
      expect(copy.visibleEdges, 4);
      expect(copy.frameNumber, 1);
    });

    test('toString includes the major counters', () {
      const stats = PaneRenderStats(
        frameNumber: 12,
        paintMicroseconds: 5432,
        visibleCells: 3,
        visibleEdges: 4,
        totalCells: 5,
        totalEdges: 6,
      );
      final s = stats.toString();
      expect(s, contains('frame=12'));
      expect(s, contains('5432'));
      expect(s, contains('3/5'));
      expect(s, contains('4/6'));
    });
  });

  group('paneRenderStatsProvider', () {
    test('starts at PaneRenderStats.empty and reflects record() updates', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(
        container.read(paneRenderStatsProvider),
        PaneRenderStats.empty,
      );
      container
          .read(paneRenderStatsProvider.notifier)
          .record(
            const PaneRenderStats(
              frameNumber: 1,
              paintMicroseconds: 100,
              visibleCells: 1,
              visibleEdges: 0,
              totalCells: 1,
              totalEdges: 0,
            ),
          );
      final after = container.read(paneRenderStatsProvider);
      expect(after.frameNumber, 1);
      expect(after.totalCells, 1);
    });
  });
}
