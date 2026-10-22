// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/services/layout/elk_layout_service.dart';
import 'package:netcrux/services/layout/layout_engine_selection.dart';
import 'package:netcrux/services/layout/native_elk_solver.dart';

import '../../helpers/elk_ffi_library_gate.dart';

const _andJson = <String, Object?>{
  'creator': 'Yosys test',
  'modules': <String, Object?>{
    'and2': <String, Object?>{
      'attributes': <String, Object?>{'top': '1'},
      'ports': <String, Object?>{
        'a': <String, Object?>{
          'direction': 'input',
          'bits': <Object>[2],
        },
        'b': <String, Object?>{
          'direction': 'input',
          'bits': <Object>[3],
        },
        'y': <String, Object?>{
          'direction': 'output',
          'bits': <Object>[4],
        },
      },
      'cells': <String, Object?>{
        'u_and': <String, Object?>{
          'hide_name': 0,
          'type': r'$and',
          'parameters': <String, Object?>{},
          'attributes': <String, Object?>{},
          'port_directions': <String, Object?>{
            'A': 'input',
            'B': 'input',
            'Y': 'output',
          },
          'connections': <String, Object?>{
            'A': <Object>[2],
            'B': <Object>[3],
            'Y': <Object>[4],
          },
        },
      },
      'netnames': <String, Object?>{},
    },
  },
};

/// A register `u_q` whose output feeds back to its own input through an
/// inverter `u_n`, with a second input `EN` tied to a constant: the feedback
/// edge is reversed by cycle breaking, and `EN` has no edge at all, the two
/// cases where a FREE port can land on the wrong face.
const _feedbackJson = <String, Object?>{
  'creator': 'Yosys test',
  'modules': <String, Object?>{
    'loop': <String, Object?>{
      'attributes': <String, Object?>{'top': '1'},
      'ports': <String, Object?>{
        'q': <String, Object?>{
          'direction': 'output',
          'bits': <Object>[2],
        },
      },
      'cells': <String, Object?>{
        'u_q': <String, Object?>{
          'hide_name': 0,
          'type': r'$dffe',
          'parameters': <String, Object?>{},
          'attributes': <String, Object?>{},
          'port_directions': <String, Object?>{
            'D': 'input',
            'EN': 'input',
            'Q': 'output',
          },
          'connections': <String, Object?>{
            'D': <Object>[3],
            'EN': <Object>['1'],
            'Q': <Object>[2],
          },
        },
        'u_n': <String, Object?>{
          'hide_name': 0,
          'type': r'$not',
          'parameters': <String, Object?>{},
          'attributes': <String, Object?>{},
          'port_directions': <String, Object?>{'A': 'input', 'Y': 'output'},
          'connections': <String, Object?>{
            'A': <Object>[2],
            'Y': <Object>[3],
          },
        },
      },
      'netnames': <String, Object?>{},
    },
  },
};

/// The ELK input NetCrux builds for module [name] of the Yosys [json].
String _elkInputJson(Map<String, Object?> json, String name) =>
    jsonEncode(buildElkInput(NetlistModel.fromJson(json).modules[name]!));

/// [n] cells in one feedback loop, with the large-scope options a real
/// scope of that size gets: every depth-first walk in the layered pipeline
/// goes [n] nodes deep.
String _loopInput(int n) {
  final children = <Map<String, Object?>>[
    for (var i = 0; i < n; i++)
      <String, Object?>{
        'id': 'c$i',
        'width': 80,
        'height': 52,
        'ports': <Map<String, Object?>>[
          <String, Object?>{
            'id': 'c$i:A',
            'width': 4,
            'height': 4,
            'layoutOptions': <String, Object?>{'elk.port.side': 'WEST'},
          },
          <String, Object?>{
            'id': 'c$i:Y',
            'width': 4,
            'height': 4,
            'layoutOptions': <String, Object?>{'elk.port.side': 'EAST'},
          },
        ],
        'layoutOptions': <String, Object?>{
          'elk.portConstraints': 'FIXED_SIDE',
        },
      },
  ];
  final edges = <Map<String, Object?>>[
    for (var i = 0; i < n; i++)
      <String, Object?>{
        'id': 'e$i',
        'sources': <String>['c$i:Y'],
        'targets': <String>['c${(i + 1) % n}:A'],
      },
  ];
  return jsonEncode(<String, Object?>{
    'id': 'root',
    'layoutOptions': <String, Object?>{
      'elk.algorithm': 'layered',
      'elk.direction': 'RIGHT',
      'elk.layered.thoroughness': '1',
      'elk.layered.cycleBreaking.strategy': 'DEPTH_FIRST',
    },
    'children': children,
    'edges': edges,
  });
}

void main() {
  group('selectLayoutSolver', () {
    test('defaults to the native engine', () {
      expect(selectLayoutSolver(requested: null), LayoutSolverKind.native);
      expect(selectLayoutSolver(requested: ''), LayoutSolverKind.native);
      expect(selectLayoutSolver(requested: 'native'), LayoutSolverKind.native);
      expect(selectLayoutSolver(requested: 'v8'), LayoutSolverKind.native);
    });

    test('every elkjs spelling keeps elkjs', () {
      for (final value in <String>[
        'elkjs',
        ' ElkJS ',
        'jsc',
        'javascriptcore',
        'quickjs',
      ]) {
        expect(
          selectLayoutSolver(requested: value),
          LayoutSolverKind.elkjs,
          reason: value,
        );
      }
    });
  });

  group('NativeElkSolver', () {
    test('reports the vendored engine version', () {
      if (!requireElkFfiLibrary()) return;
      final solver = NativeElkSolver.open();
      addTearDown(solver.dispose);
      expect(solver.engineDescription, startsWith('native (elkrs '));
    });

    test('lays out a module through the service seam', () async {
      if (!requireElkFfiLibrary()) return;
      final service = ElkLayoutService(
        solverFactory: NativeElkSolver.open,
        assetLoader: (_) async => throw StateError('elkjs must not load'),
      );
      addTearDown(service.dispose);
      final layout = await service.layout(
        NetlistModel.fromJson(_andJson).modules['and2']!,
      );
      // and2: one cell plus three boundary ports, every node placed.
      expect(layout.nodes, hasLength(4));
      expect(layout.edges, hasLength(3));
      expect(layout.bounds.width, greaterThan(0));
      for (final node in layout.nodes) {
        expect(node.bounds.width, greaterThan(0), reason: node.id);
      }
    });

    test('honours FIXED_SIDE: inputs on the west face, outputs east', () async {
      if (!requireElkFfiLibrary()) return;
      final service = ElkLayoutService(
        solverFactory: NativeElkSolver.open,
        assetLoader: (_) async => throw StateError('elkjs must not load'),
      );
      addTearDown(service.dispose);
      final layout = await service.layout(
        NetlistModel.fromJson(_feedbackJson).modules['loop']!,
      );
      const inputs = <String>{'u_q:D', 'u_q:EN', 'u_n:A'};
      const outputs = <String>{'u_q:Q', 'u_n:Y'};
      for (final id in <String>['u_q', 'u_n']) {
        final node = layout.findNode(id)!;
        for (final port in node.ports.entries) {
          final centre = port.value.x + port.value.width / 2;
          if (inputs.contains(port.key)) {
            expect(centre, lessThan(node.bounds.width / 2), reason: port.key);
          } else {
            expect(outputs, contains(port.key));
            expect(
              centre,
              greaterThan(node.bounds.width / 2),
              reason: port.key,
            );
          }
        }
      }
    });

    test("surfaces the engine's rejection as a LayoutException", () {
      if (!requireElkFfiLibrary()) return;
      final solver = NativeElkSolver.open();
      addTearDown(solver.dispose);
      expect(
        () => solver.solve('{"id": "root", "children": ['),
        throwsA(
          isA<LayoutException>().having(
            (e) => e.message,
            'message',
            contains('rejected'),
          ),
        ),
      );
    });

    // Ten thousand cells in one feedback loop: every depth-first walk in
    // the layered pipeline goes ten thousand nodes deep. The engine walks
    // with explicit stacks, so this lays out on the layout thread's default
    // stack, with the large-scope options a real scope of this size gets.
    test('lays out a ten-thousand-cell loop on the default stack', () {
      if (!requireElkFfiLibrary()) return;
      final solver = NativeElkSolver.open();
      addTearDown(solver.dispose);
      const n = 10000;
      final result =
          jsonDecode(solver.solve(_loopInput(n))) as Map<String, Object?>;
      expect(result['children'], hasLength(n));
      expect(result['edges'], hasLength(n));
    });

    test(
      'a job gives the same bytes as solve, reporting phases in order',
      () async {
        if (!requireElkFfiLibrary()) return;
        final solver = NativeElkSolver.open();
        addTearDown(solver.dispose);
        for (final input in <String>[
          _elkInputJson(_feedbackJson, 'loop'),
          // One component, long enough that polls land in several phases.
          _loopInput(3000),
        ]) {
          final seen = <LayoutProgress>[];
          final viaJob = await driveElkSolveJob(
            solver.start(input),
            onProgress: seen.add,
          );
          expect(viaJob, solver.solve(input));
          // Polling sees the latest report, so phases may be skipped, but
          // never revisited, and the share done only grows.
          expect(seen, isNotEmpty);
          for (var i = 1; i < seen.length; i++) {
            expect(
              seen[i].phase.index,
              greaterThanOrEqualTo(seen[i - 1].phase.index),
            );
            expect(
              seen[i].fraction,
              greaterThanOrEqualTo(seen[i - 1].fraction!),
            );
          }
          expect(seen.last.phase, LayoutPhase.edgeRouting);
          expect(seen.last.fraction, lessThan(1));
        }
      },
    );

    test('a cancelled job stops with LayoutCancelledException', () async {
      if (!requireElkFfiLibrary()) return;
      final solver = NativeElkSolver.open();
      addTearDown(solver.dispose);
      final job = solver.start(_loopInput(20000));
      final cancelledAt = Stopwatch()..start();
      job.cancel();
      await expectLater(
        driveElkSolveJob(job),
        throwsA(isA<LayoutCancelledException>()),
      );
      // A twenty-thousand-cell loop takes seconds to lay out; the cancel
      // lands at the engine's next check.
      expect(cancelledAt.elapsed, lessThan(const Duration(seconds: 2)));
    });

    test('round-trips a large document without corrupting UTF-8', () {
      if (!requireElkFfiLibrary()) return;
      final solver = NativeElkSolver.open();
      addTearDown(solver.dispose);
      // A node id with a non-ASCII name must survive the byte buffers on
      // both sides of the ABI.
      final result = solver.solve(
        '{"id":"root","layoutOptions":{"elk.algorithm":"layered"},'
        '"children":[{"id":"ünïcode·node","width":30,"height":30}]}',
      );
      expect(result, contains('ünïcode·node'));
    });
  });
}
