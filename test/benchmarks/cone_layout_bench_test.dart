// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/netlist/hierarchy_node.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/domain/models/trace/cone_view.dart';
import 'package:netcrux/services/layout/elk_layout_service.dart';
import 'package:netcrux/services/layout/native_elk_solver.dart';
import 'package:netcrux/services/schematic/cone_membership.dart';
import 'package:netcrux/services/schematic/declared_cell_ports.dart';
import 'package:netcrux/services/schematic/schematic_graph_builder.dart';
import 'package:netcrux/services/yosys/streaming_yosys_json_reader.dart';

import '../helpers/elk_ffi_library_gate.dart';

/// Cone view against whole-scope layout, on the native engine.
///
/// For each flat fixture, times cone views of a cell near the middle of the
/// scope at several depths and then the whole scope's layout, both walked the
/// way the app walks them: the graph built, the cone resolved on it, the ELK
/// input built for the cone and solved. Each solve is cold (a fresh service,
/// no cache). Rows go to `build/perf/cone_layout.jsonl` (gitignored) and to
/// stdout.
///
/// Gated behind `--dart-define=RUN_BENCHMARKS=true`. The fixtures default to
/// the flat ones in the corpus and are chosen with
/// `--dart-define=CONE_BENCH_FIXTURES=picorv32,grid_100k`.
void main() {
  const runBenchmarks = bool.fromEnvironment('RUN_BENCHMARKS');
  const fixtures = String.fromEnvironment(
    'CONE_BENCH_FIXTURES',
    defaultValue: 'picorv32,chain_10k,grid_100k',
  );

  test(
    'cone view layout time against whole-scope layout time',
    () async {
      if (!requireElkFfiLibrary()) return;
      final rows = <Map<String, Object?>>[];
      for (final name in fixtures.split(',')) {
        final model = _load(name);
        final node = HierarchyNode.rootOf(model)!;
        final module = withDeclaredCellPorts(model, node.resolve(model)!);
        final graphWatch = Stopwatch()..start();
        final graph = const SchematicGraphBuilder().build(model, node);
        graphWatch.stop();
        final cells = graph.cells.toList();
        // Past the middle by a two-hundredth of the scope, so the root of a
        // scope built of chains (grid_100k's rows) is inside a chain rather
        // than at its head, where a fan-in cone would end at once.
        final root = SelectedElement.cell(
          cellId: cells[cells.length ~/ 2 + cells.length ~/ 200].id,
        );

        for (final (direction, depth) in <(ConeViewDirection, int)>[
          (ConeViewDirection.fanIn, 1),
          (ConeViewDirection.fanIn, 2),
          (ConeViewDirection.fanIn, 4),
          (ConeViewDirection.fanIn, 8),
          (ConeViewDirection.fanInAndFanOut, 2),
          (ConeViewDirection.fanInAndFanOut, 8),
        ]) {
          final walk = Stopwatch()..start();
          final members = coneViewMembership(
            graph,
            root,
            direction: direction,
            depth: depth,
          );
          final sub = coneSubgraph(graph, members);
          walk.stop();
          final service = ElkLayoutService(solverFactory: NativeElkSolver.open);
          final solve = Stopwatch()..start();
          final layout = await service.layout(
            module,
            only: ElkSubgraph(
              cellIds: <String>{for (final c in sub.cells) c.id},
              boundaryPortIds: <String>{
                for (final b in sub.boundaryPorts) b.id,
              },
              edgeIds: <String>{for (final e in sub.edges) e.id},
            ),
          );
          solve.stop();
          service.dispose();
          rows.add(<String, Object?>{
            'scope': name,
            'scopeCells': graph.cells.length,
            'cone': '${direction.name}/$depth',
            'coneCells': sub.cells.length,
            'nodes': layout.nodes.length,
            'graphMs': graphWatch.elapsedMilliseconds,
            'walkMs': walk.elapsedMilliseconds,
            'layoutMs': solve.elapsedMilliseconds,
          });
          // Emitting bench progress to stdout is the point of this job.
          // ignore: avoid_print
          print('cone[$name]: ${rows.last}');
        }

        final service = ElkLayoutService(solverFactory: NativeElkSolver.open);
        final full = Stopwatch()..start();
        final layout = await service.layout(module);
        full.stop();
        service.dispose();
        rows.add(<String, Object?>{
          'scope': name,
          'scopeCells': graph.cells.length,
          'cone': 'whole scope',
          'coneCells': graph.cells.length,
          'nodes': layout.nodes.length,
          'graphMs': graphWatch.elapsedMilliseconds,
          'walkMs': 0,
          'layoutMs': full.elapsedMilliseconds,
        });
        // Emitting bench progress to stdout is the point of this job.
        // ignore: avoid_print
        print('cone[$name]: ${rows.last}');
      }

      final outDir = Directory('build/perf')..createSync(recursive: true);
      final sink = File(
        '${outDir.path}/cone_layout.jsonl',
      ).openWrite(mode: FileMode.append);
      for (final row in rows) {
        sink.writeln(jsonEncode(row));
      }
      await sink.flush();
      await sink.close();
    },
    timeout: const Timeout(Duration(hours: 2)),
    skip: runBenchmarks ? false : 'set --dart-define=RUN_BENCHMARKS=true',
  );
}

NetlistModel _load(String name) {
  for (final kind in const <String>['generated', 'captured']) {
    final file = File(
      'test/fixtures/netlist/$name/$kind/$name.netlist.json.gz',
    );
    if (file.existsSync()) {
      return const StreamingYosysJsonReader().parse(
        utf8.decode(gzip.decode(file.readAsBytesSync())),
      );
    }
  }
  throw StateError('no netlist fixture named $name');
}
