// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/netlist/module.dart';
import 'package:netcrux/services/layout/elk_layout_service.dart';
import 'package:netcrux/services/yosys/streaming_yosys_json_reader.dart';

/// ELK layout benchmark. Times
/// `ElkLayoutService.layout` over the committed `chain_1k` / `chain_10k`
/// scopes and records wall-time to `build/perf/elk_layout.jsonl` (gitignored).
///
/// **Caveat:** this benchmark drives the layout pipeline through the same
/// deterministic [ElkSolver] the integration tests use. It therefore measures
/// the **Dart-side** cost (elk-graph build + result parse + `NetlistLayout`
/// construction), not the engine's solve, which the elkrs benches and the
/// running app measure. No hard assertion; the goal is < 2 s for a typical
/// scope change.
///
/// Gated behind `--dart-define=RUN_BENCHMARKS=true`.
void main() {
  const runBenchmarks = bool.fromEnvironment('RUN_BENCHMARKS');

  test(
    'elk layout pipeline wall-time per scope',
    () async {
      final rows = <Map<String, Object?>>[];
      for (final name in <String>['chain_1k', 'chain_10k']) {
        final module = _loadModule(name);
        final service = ElkLayoutService(solverFactory: _RowSolver.new);
        // Warm once, then time.
        await service.layout(module);
        final stopwatch = Stopwatch()..start();
        final layout = await service.layout(module);
        stopwatch.stop();
        rows.add(<String, Object?>{
          'scope': name,
          'cells': module.cells.length,
          'nodes': layout.nodes.length,
          'layoutMs': stopwatch.elapsedMilliseconds,
        });
        // Emitting bench progress to stdout is the point of this job.
        // ignore: avoid_print
        print('elk[$name]: ${rows.last}');
      }

      final outDir = Directory('build/perf')..createSync(recursive: true);
      final sink = File(
        '${outDir.path}/elk_layout.jsonl',
      ).openWrite(mode: FileMode.append);
      for (final row in rows) {
        sink.writeln(jsonEncode(row));
      }
      await sink.flush();
      await sink.close();
    },
    skip: runBenchmarks ? false : 'set --dart-define=RUN_BENCHMARKS=true',
  );
}

Module _loadModule(String name) {
  final base = 'test/fixtures/netlist/$name/generated/$name.netlist.json';
  final plain = File(base);
  final raw = plain.existsSync()
      ? plain.readAsStringSync()
      : utf8.decode(GZipCodec().decode(File('$base.gz').readAsBytesSync()));
  final model = const StreamingYosysJsonReader().parse(raw);
  return model.modules[name]!;
}

/// Deterministic [ElkSolver] that fabricates a row-of-boxes layout for its
/// input, so the pipeline runs end to end without a real engine. Mirrors the
/// integration tests' solver.
class _RowSolver implements ElkSolver {
  @override
  String get engineDescription => 'row';

  @override
  String solve(String inputJson) {
    final input = jsonDecode(inputJson) as Map<String, Object?>;
    final children = (input['children'] as List<Object?>?) ?? const <Object?>[];
    final laidOutNodes = <Map<String, Object?>>[
      for (var i = 0; i < children.length; i++)
        <String, Object?>{
          'id': (children[i]! as Map<String, Object?>)['id'],
          'x': 50.0 + (i * 100),
          'y': 50.0,
          'width': 80.0,
          'height': 32.0,
        },
    ];
    return jsonEncode(<String, Object?>{
      'id': 'root',
      'x': 0.0,
      'y': 0.0,
      'width': 50.0 + (children.length * 100) + 50.0,
      'height': 132.0,
      'children': laidOutNodes,
      'edges': <Map<String, Object?>>[],
    });
  }

  @override
  void dispose() {}
}
