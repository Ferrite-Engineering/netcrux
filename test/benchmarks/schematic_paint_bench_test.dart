// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/layout/bounding_box.dart';
import 'package:netcrux/domain/models/layout/edge_route.dart';
import 'package:netcrux/domain/models/layout/netlist_layout.dart';
import 'package:netcrux/domain/models/layout/node_position.dart';
import 'package:netcrux/domain/models/netlist/port_direction.dart';
import 'package:netcrux/domain/models/schematic/cell_kind.dart';
import 'package:netcrux/domain/models/schematic/laid_out_graph.dart';
import 'package:netcrux/domain/models/schematic/schematic_graph.dart';
import 'package:netcrux/features/viewer/rendering/schematic_painter.dart';

/// Schematic paint benchmark. Paints a
/// 500 / 1000 / 5000-cell grid against a fixed canvas in **two modes** —
/// culled (production) and no-cull (`cullingEnabled: false`) — and records
/// the per-frame paint time (avg / p99) plus the post-cull visible-cell count
/// to `build/perf/schematic_paint.jsonl` (gitignored). No hard assertion —
/// the numbers are recorded; the goal is 60 fps (< 16.67 ms/frame).
///
/// The grid is far larger than the 1200×800 canvas, so only a viewport
/// window is on-screen: no-cull iterates + builds every cell each frame,
/// while culled pays only for the visible window — the delta is the culling
/// win. `visibleCells` in each row is what the painter actually drew.
///
/// Gated behind `--dart-define=RUN_BENCHMARKS=true`; the default `flutter
/// test` skips it.
void main() {
  const runBenchmarks = bool.fromEnvironment('RUN_BENCHMARKS');

  testWidgets(
    'paint frame time vs cell count, culled vs no-cull',
    (tester) async {
      const cellCounts = <int>[500, 1000, 5000];
      final rows = <Map<String, Object?>>[];

      for (final culled in <bool>[true, false]) {
        for (final count in cellCounts) {
          final graph = _gridGraph(count);
          final sink = RecordingRenderStatsSink();

          Future<void> pumpAt(double dx) => tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: SizedBox(
                  width: 1200,
                  height: 800,
                  child: SchematicCanvas(
                    laidOut: graph,
                    transform: ViewportTransform(
                      zoom: 1,
                      offset: Offset(dx, 0),
                    ),
                    statsSink: sink,
                    theme: ThemeData.light(useMaterial3: true),
                    cullingEnabled: culled,
                  ),
                ),
              ),
            ),
          );

          // Warm up (first paint compiles shaders / builds caches).
          await pumpAt(0);
          // Nudge the offset each iteration to force a real repaint.
          for (var i = 1; i <= 20; i++) {
            await pumpAt(i.toDouble());
          }

          final micros = sink.samples.map((s) => s.paintMicroseconds).toList()
            ..sort();
          if (micros.isEmpty) continue;
          final avg = micros.reduce((a, b) => a + b) / micros.length;
          final p99 =
              micros[(micros.length * 0.99).floor().clamp(
                0,
                micros.length - 1,
              )];
          rows.add(<String, Object?>{
            'mode': culled ? 'culled' : 'no-cull',
            'totalCells': count,
            'visibleCells': sink.last?.visibleCells ?? count,
            'samples': micros.length,
            'avgPaintMs': (avg / 1000).toStringAsFixed(3),
            'p99PaintMs': (p99 / 1000).toStringAsFixed(3),
          });
          // Emitting bench progress to stdout is the point of this job.
          // ignore: avoid_print
          print(
            'paint[${culled ? 'culled ' : 'no-cull'} $count cells]: '
            '${rows.last}',
          );
        }
      }

      // dart:io's File operations hand off to a background isolate via a
      // raw receive port; `TestWidgetsFlutterBinding`'s fake-async pump
      // loop never services that port, so writing directly here hangs
      // indefinitely (confirmed: two independent runs both timed out with
      // a 0-byte output file). `runAsync` executes the callback in the
      // real (non-fake-async) zone so the isolate round-trip completes.
      await tester.runAsync(() async {
        final outDir = Directory('build/perf')..createSync(recursive: true);
        final sink = File(
          '${outDir.path}/schematic_paint.jsonl',
        ).openWrite(mode: FileMode.append);
        for (final row in rows) {
          sink.writeln(jsonEncode(row));
        }
        await sink.flush();
        await sink.close();
      });
    },
    // testWidgets.skip is bool-only; gate on the RUN_BENCHMARKS define.
    skip: !runBenchmarks,
    // 126 pumps across 6 configs (up to 5000 cells, no-cull) is bounded work;
    // cap well above the observed run time so a genuine hang fails the job
    // instead of consuming the whole nightly run.
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

/// Builds an `n`-cell grid of flip-flops with a horizontal edge per row, laid
/// out on a fixed pitch — a synthetic "visible scope" for the paint hot path.
LaidOutGraph _gridGraph(int n) {
  const cols = 50;
  const pitchX = 90.0;
  const pitchY = 70.0;
  final cells = <SchematicCell>[];
  final nodes = <NodePosition>[];
  for (var i = 0; i < n; i++) {
    final id = 'ff$i';
    cells.add(
      SchematicCell(
        id: id,
        kind: CellKind.flipFlop,
        type: r'$_DFF_P_',
        ports: <SchematicPort>[
          SchematicPort(
            id: '$id:D',
            name: 'D',
            direction: PortDirection.input,
            side: SchematicPortSide.west,
          ),
          SchematicPort(
            id: '$id:Q',
            name: 'Q',
            direction: PortDirection.output,
            side: SchematicPortSide.east,
          ),
        ],
      ),
    );
    final x = (i % cols) * pitchX;
    final y = (i ~/ cols) * pitchY;
    nodes.add(
      NodePosition(
        id: id,
        bounds: BoundingBox(x: x, y: y, width: 60, height: 50),
        ports: <String, BoundingBox>{
          '$id:D': const BoundingBox(x: 0, y: 22, width: 4, height: 4),
          '$id:Q': const BoundingBox(x: 56, y: 22, width: 4, height: 4),
        },
      ),
    );
  }
  final cellCols = cols < n ? cols : n;
  return LaidOutGraph(
    graph: SchematicGraph(
      moduleName: 'grid_$n',
      cells: cells,
      boundaryPorts: const <SchematicBoundaryPort>[],
      edges: const <SchematicEdge>[],
    ),
    layout: NetlistLayout(
      nodes: nodes,
      edges: const <EdgeRoute>[],
      bounds: BoundingBox(
        x: 0,
        y: 0,
        width: cellCols * pitchX,
        height: ((n / cols).ceil()) * pitchY,
      ),
    ),
  );
}
