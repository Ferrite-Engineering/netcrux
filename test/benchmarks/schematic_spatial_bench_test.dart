// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/schematic/laid_out_graph.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/features/viewer/rendering/schematic_painter.dart';
import 'package:netcrux/features/viewer/rendering/schematic_scene_index.dart';
import 'package:netcrux/features/viewer/selection/schematic_hit_test.dart';
import 'package:netcrux/features/viewer/selection/schematic_keyboard_navigator.dart';

import '../helpers/flattened_scope.dart';

/// The per-interaction cost of a large flat scope: one painted frame, one
/// click's hit-test, and one keyboard selection step, on the committed
/// `grid_100k` design (100,000 cells) laid out by [flattenedGrid100k].
///
/// These are the three paths that used to scan every cell and every edge of
/// the scope on each frame, click and keypress. Each row is appended to
/// `build/perf/schematic_spatial.jsonl` (gitignored). No hard assertion —
/// the numbers are recorded; the frame budget is 16.67 ms.
///
/// Gated behind `--dart-define=RUN_BENCHMARKS=true`; the default
/// `flutter test` skips it.
void main() {
  const runBenchmarks = bool.fromEnvironment('RUN_BENCHMARKS');
  final rows = <Map<String, Object?>>[];
  LaidOutGraph? built;
  LaidOutGraph scope() => built ??= flattenedGrid100k();

  void record(Map<String, Object?> row) {
    rows.add(row);
    // Emitting bench progress to stdout is the point of this job.
    // ignore: avoid_print
    print('spatial: $row');
  }

  tearDownAll(() {
    if (rows.isEmpty) return;
    final outDir = Directory('build/perf')..createSync(recursive: true);
    File('${outDir.path}/schematic_spatial.jsonl').writeAsStringSync(
      '${rows.map(jsonEncode).join('\n')}\n',
      mode: FileMode.append,
    );
  });

  testWidgets(
    'paint frame time on a 100,000-cell scope, per LOD band',
    (tester) async {
      final laidOut = scope();
      for (final (band, zoom) in <(String, double)>[
        ('detail', 1),
        ('mid', 0.4),
        ('overview', 0.05),
      ]) {
        final sink = RecordingRenderStatsSink();
        Future<void> pumpAt(double dx) => tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 1200,
                height: 800,
                child: SchematicCanvas(
                  laidOut: laidOut,
                  transform: ViewportTransform(
                    zoom: zoom,
                    // Somewhere in the middle of the design.
                    offset: Offset(-8000 * zoom - dx, -9000 * zoom),
                  ),
                  statsSink: sink,
                  theme: ThemeData.light(useMaterial3: true),
                ),
              ),
            ),
          ),
        );
        // Warm up: the first frame builds text layouts and any per-scope
        // caches, which is a one-time cost, not a per-frame one.
        await pumpAt(0);
        await pumpAt(1);
        sink.samples.clear();
        for (var i = 2; i <= 21; i++) {
          await pumpAt(i.toDouble());
        }
        final micros = sink.samples.map((s) => s.paintMicroseconds).toList()
          ..sort();
        record(<String, Object?>{
          'path': 'paint',
          'band': band,
          'cells': laidOut.graph.cells.length,
          'layoutEdges': laidOut.layout.edges.length,
          'visibleCells': sink.last?.visibleCells,
          'avgMs': (micros.reduce((a, b) => a + b) / micros.length / 1000)
              .toStringAsFixed(3),
          'p99Ms': (micros.last / 1000).toStringAsFixed(3),
        });
      }
    },
    skip: !runBenchmarks,
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'hit-test time per click on a 100,000-cell scope',
    () {
      final laidOut = scope();
      final bounds = laidOut.layout.bounds;
      final rng = Random(42);
      final points = <Offset>[
        for (var i = 0; i < 2000; i++)
          Offset(
            bounds.x + rng.nextDouble() * bounds.width,
            bounds.y + rng.nextDouble() * bounds.height,
          ),
      ];
      final tester = SchematicHitTester(
        laidOut: laidOut,
        transform: ViewportTransform.identity,
      );
      // First click pays any one-time per-scope cost; time it on its own.
      final first = Stopwatch()..start();
      tester.hitTest(points.first);
      first.stop();
      final perClick = <int>[];
      var hits = 0;
      for (final point in points) {
        final stopwatch = Stopwatch()..start();
        final hit = tester.hitTest(point);
        stopwatch.stop();
        perClick.add(stopwatch.elapsedMicroseconds);
        if (hit is! SelectedElementNone) hits++;
      }
      perClick.sort();
      record(<String, Object?>{
        'path': 'hitTest',
        'clicks': points.length,
        'hits': hits,
        'firstClickMs': (first.elapsedMicroseconds / 1000).toStringAsFixed(3),
        'avgMs': (perClick.reduce((a, b) => a + b) / perClick.length / 1000)
            .toStringAsFixed(4),
        'p99Ms': (perClick[(perClick.length * 0.99).floor()] / 1000)
            .toStringAsFixed(4),
      });
    },
    skip: !runBenchmarks,
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'keyboard selection step time on a 100,000-cell scope',
    () {
      final laidOut = scope();
      final navigator = SchematicKeyboardNavigator(laidOut);
      const steps = 50;
      // The first step of each kind pays any one-time per-scope cost; time
      // it on its own, then the steady state.
      final firstElement = Stopwatch()..start();
      var current = navigator.stepElement(
        const SelectedElement.none(),
        forward: true,
      );
      firstElement.stop();
      final byElement = Stopwatch()..start();
      for (var i = 0; i < steps; i++) {
        current = navigator.stepElement(current, forward: true);
      }
      byElement.stop();
      final anchor = navigator.anchorFor(current);
      final firstConnection = Stopwatch()..start();
      var pin = navigator.stepConnection(anchor, anchor, forward: true);
      firstConnection.stop();
      final byConnection = Stopwatch()..start();
      for (var i = 0; i < steps; i++) {
        pin = navigator.stepConnection(pin, anchor, forward: true);
      }
      byConnection.stop();
      String ms(int micros, [int per = 1]) =>
          (micros / per / 1000).toStringAsFixed(3);
      record(<String, Object?>{
        'path': 'keyboard',
        'steps': steps,
        'firstStepElementMs': ms(firstElement.elapsedMicroseconds),
        'stepElementAvgMs': ms(byElement.elapsedMicroseconds, steps),
        'firstStepConnectionMs': ms(firstConnection.elapsedMicroseconds),
        'stepConnectionAvgMs': ms(byConnection.elapsedMicroseconds, steps),
      });
    },
    skip: !runBenchmarks,
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'one-time scene index build per section on a 100,000-cell scope',
    () {
      // A fresh graph identity, so nothing is cached from the tests above.
      final shared = scope();
      final laidOut = LaidOutGraph(graph: shared.graph, layout: shared.layout);
      final scene = SchematicSceneIndex.of(laidOut);
      int time(void Function() build) {
        final stopwatch = Stopwatch()..start();
        build();
        return stopwatch.elapsedMicroseconds;
      }

      String ms(int micros) => (micros / 1000).toStringAsFixed(1);
      record(<String, Object?>{
        'path': 'indexBuild',
        // First paint builds these three.
        'cellsMs': ms(time(() => scene.cellsIn(Rect.zero))),
        'boundaryMs': ms(time(() => scene.boundaryPortsIn(Rect.zero))),
        'wiresMs': ms(time(() => scene.wiresIn(Rect.zero))),
        // First click adds these two.
        'pinsMs': ms(time(() => scene.pinsIn(Rect.zero))),
        'segmentsMs': ms(time(() => scene.wiresNear(Offset.zero, 6))),
        // The first keyboard element step adds this.
        'readingOrderMs': ms(time(() => scene.readingOrder)),
      });
    },
    skip: !runBenchmarks,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
