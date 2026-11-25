// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/netlist/module.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/netlist/port_direction.dart';
import 'package:netcrux/services/layout/elk_layout_service.dart';
import 'package:netcrux/services/layout/layout_disk_cache_vm.dart';
import 'package:path/path.dart' as p;

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

/// A flat module of [n] inverters in series: `in` → u_0 → … → u_{n-1} →
/// `out`. Large enough to keep a real engine busy for a moment, and a
/// distinct ELK input from [_andJson], so no cache short-circuits the solve.
Map<String, Object?> _chainJson(int n) {
  final cells = <String, Object?>{};
  for (var i = 0; i < n; i++) {
    cells['u_$i'] = <String, Object?>{
      'hide_name': 0,
      'type': r'$not',
      'parameters': <String, Object?>{},
      'attributes': <String, Object?>{},
      'port_directions': <String, Object?>{'A': 'input', 'Y': 'output'},
      'connections': <String, Object?>{
        'A': <Object>[2 + i],
        'Y': <Object>[3 + i],
      },
    };
  }
  return <String, Object?>{
    'creator': 'Yosys test',
    'modules': <String, Object?>{
      'chain': <String, Object?>{
        'attributes': <String, Object?>{'top': '1'},
        'ports': <String, Object?>{
          'in': <String, Object?>{
            'direction': 'input',
            'bits': <Object>[2],
          },
          'out': <String, Object?>{
            'direction': 'output',
            'bits': <Object>[2 + n],
          },
        },
        'cells': cells,
        'netnames': <String, Object?>{},
      },
    },
  };
}

/// Minimal scripted solver: returns the caller-specified layout JSON, or
/// rejects every input with [errorMessage], and records each input it was
/// asked to solve.
class _ScriptedSolver implements ElkSolver {
  _ScriptedSolver({this.layoutJson, this.errorMessage});

  final String? layoutJson;
  final String? errorMessage;

  final List<String> inputs = <String>[];
  bool disposed = false;

  @override
  String get engineDescription => 'scripted';

  @override
  String solve(String inputJson) {
    inputs.add(inputJson);
    final error = errorMessage;
    if (error != null) {
      throw LayoutException('elk rejected the layout input: $error');
    }
    return layoutJson ?? '';
  }

  @override
  void dispose() => disposed = true;
}

void main() {
  group('buildElkInput', () {
    test('creates one node per cell and one boundary node per module port', () {
      final model = NetlistModel.fromJson(_andJson);
      final input = buildElkInput(model.modules['and2']!);
      final children = input['children']! as List<Object?>;
      expect(children, hasLength(4));
      final ids = <String>[
        for (final c in children) (c! as Map<String, Object?>)['id']! as String,
      ];
      expect(ids, containsAll(<String>['port:a', 'port:b', 'port:y', 'u_and']));
    });

    test('fixes every cell port to a side: inputs west, outputs east', () {
      final model = NetlistModel.fromJson(_andJson);
      final input = buildElkInput(model.modules['and2']!);
      final cell = (input['children']! as List<Object?>)
          .cast<Map<String, Object?>>()
          .singleWhere((c) => c['id'] == 'u_and');
      expect(
        cell['layoutOptions'],
        <String, Object?>{'elk.portConstraints': 'FIXED_SIDE'},
      );
      // The importer reads `layoutOptions` or `properties`, never both.
      expect(cell.containsKey('properties'), isFalse);
      final sides = <String, Object?>{
        for (final port
            in (cell['ports']! as List<Object?>).cast<Map<String, Object?>>())
          port['id']! as String:
              (port['layoutOptions']! as Map<String, Object?>)['elk.port.side'],
      };
      expect(sides, <String, Object?>{
        'u_and:A': 'WEST',
        'u_and:B': 'WEST',
        'u_and:Y': 'EAST',
      });
    });

    test('elkPortSideFor puts a pin without a direction with the inputs', () {
      expect(elkPortSideFor(PortDirection.input), 'WEST');
      expect(elkPortSideFor(null), 'WEST');
      expect(elkPortSideFor(PortDirection.output), 'EAST');
      expect(elkPortSideFor(PortDirection.inout), 'EAST');
    });

    test('emits driver→sink edges for every shared net id', () {
      final model = NetlistModel.fromJson(_andJson);
      final input = buildElkInput(model.modules['and2']!);
      final edges = input['edges']! as List<Object?>;
      expect(edges, hasLength(3));
    });

    test('uses the layered ELK algorithm by default', () {
      final model = NetlistModel.fromJson(_andJson);
      final input = buildElkInput(model.modules['and2']!);
      final opts = input['layoutOptions']! as Map<String, Object?>;
      expect(opts['elk.algorithm'], 'layered');
      expect(opts['elk.direction'], 'RIGHT');
    });

    test(
      'large scopes get the fast layered knobs; small scopes keep defaults',
      () {
        // Small (and2 = 1 cell): full-quality defaults, no fast knobs.
        final small =
            buildElkInput(
                  NetlistModel.fromJson(_andJson).modules['and2']!,
                )['layoutOptions']!
                as Map<String, Object?>;
        expect(small.containsKey('elk.layered.thoroughness'), isFalse);
        expect(
          small.containsKey('elk.layered.cycleBreaking.strategy'),
          isFalse,
        );

        // Large (>500 cells): single crossing-min pass + depth-first cycle
        // breaking: ~halved the elkjs solve on a dense register-heavy core.
        final big =
            buildElkInput(
                  NetlistModel.fromJson(_fanoutJson(600)).modules['m']!,
                )['layoutOptions']!
                as Map<String, Object?>;
        expect(big['elk.algorithm'], 'layered');
        expect(big['elk.layered.thoroughness'], '1');
        expect(big['elk.layered.cycleBreaking.strategy'], 'DEPTH_FIRST');
      },
    );

    test('skips high-fanout global nets above the edge cap', () {
      // A net whose driver×sink product exceeds the cap (32) is a global
      // net (clock / reset fanning out to every flop) and is left
      // un-routed — point-to-point routing it exploded picorv32 to ~21 000
      // edges and a multi-screen-tall layout.
      List<Object?> edgesFor(int sinks) =>
          buildElkInput(
                NetlistModel.fromJson(_fanoutJson(sinks)).modules['m']!,
              )['edges']!
              as List<Object?>;
      // 20 sinks (≤ 32) → routed as 20 simple driver→sink edges.
      expect(edgesFor(20), hasLength(20));
      // 40 sinks (> 32) → the net is skipped entirely.
      expect(edgesFor(40), isEmpty);
    });

    test('skips constant bits when building edges', () {
      const constantJson = <String, Object?>{
        'creator': 'Yosys',
        'modules': <String, Object?>{
          'm': <String, Object?>{
            'attributes': <String, Object?>{},
            'ports': <String, Object?>{},
            'cells': <String, Object?>{
              'c': <String, Object?>{
                'hide_name': 0,
                'type': r'$dff',
                'parameters': <String, Object?>{},
                'attributes': <String, Object?>{},
                'port_directions': <String, Object?>{
                  'D': 'input',
                  'Q': 'output',
                },
                'connections': <String, Object?>{
                  'D': <Object>['0'],
                  'Q': <Object>[42],
                },
              },
            },
            'netnames': <String, Object?>{},
          },
        },
      };
      final model = NetlistModel.fromJson(constantJson);
      final input = buildElkInput(model.modules['m']!);
      final edges = input['edges']! as List<Object?>;
      expect(edges, isEmpty);
    });
  });

  group('ElkLayoutService', () {
    test('layout returns a NetlistLayout when the engine succeeds', () async {
      final solver = _ScriptedSolver(
        layoutJson: '''
{
  "id": "root",
  "x": 0, "y": 0, "width": 200, "height": 80,
  "children": [
    {"id": "u_and", "x": 50, "y": 20, "width": 80, "height": 32}
  ],
  "edges": []
}
''',
      );
      final service = ElkLayoutService(solverFactory: () => solver);
      final model = NetlistModel.fromJson(_andJson);
      final layout = await service.layout(model.modules['and2']!);
      expect(layout.bounds.width, 200);
      expect(layout.nodes, hasLength(1));
      expect(layout.nodes.first.id, 'u_and');
      // The service handed the ELK input to the engine.
      expect(solver.inputs.single, contains('"u_and"'));
    });

    test('layout surfaces engine-reported errors as LayoutException', () async {
      final solver = _ScriptedSolver(errorMessage: 'invalid layout input');
      final service = ElkLayoutService(solverFactory: () => solver);
      final model = NetlistModel.fromJson(_andJson);
      expect(
        () => service.layout(model.modules['and2']!),
        throwsA(
          isA<LayoutException>()
              .having((e) => e.message, 'message', contains('rejected'))
              .having((e) => e.kind, 'kind', LayoutFailureKind.other),
        ),
      );
    });

    test('layoutTop returns null when the model has no top module', () async {
      const noTopJson = <String, Object?>{
        'creator': 'Yosys',
        'modules': <String, Object?>{
          'm': <String, Object?>{
            'attributes': <String, Object?>{},
            'ports': <String, Object?>{},
            'cells': <String, Object?>{},
            'netnames': <String, Object?>{},
          },
        },
      };
      final service = ElkLayoutService(solverFactory: _ScriptedSolver.new);
      expect(await service.layoutTop(NetlistModel.fromJson(noTopJson)), isNull);
    });

    test('dispose tears down the solver', () async {
      final solver = _ScriptedSolver(
        layoutJson: '{"id":"root","x":0,"y":0,"width":1,"height":1}',
      );
      final service = ElkLayoutService(solverFactory: () => solver);
      final model = NetlistModel.fromJson(_andJson);
      await service.layout(model.modules['and2']!);
      service.dispose();
      expect(solver.disposed, isTrue);
    });
  });

  group('ElkLayoutService — isolate offload (production path)', () {
    // No injected solver: the production path, where the solve runs on a
    // dedicated background isolate on the native engine. Proves the offload
    // end to end (init handshake, result marshalled back, warm reuse).
    test(
      'lays out a real design on a background isolate + reuses it warm',
      () async {
        if (!requireElkFfiLibrary()) return;
        final module = NetlistModel.fromJson(_andJson).modules['and2']!;
        final service = ElkLayoutService();
        addTearDown(service.dispose);

        final first = await service.layout(module);
        // and2 = 1 cell (u_and) + 3 boundary ports → 4 nodes, all positioned.
        expect(first.nodes, hasLength(4));
        expect(service.workerEngine, startsWith('native (elkrs '));
        // A second, different layout (no cache hit) reuses the warm worker
        // isolate (no re-spawn/re-init): 3 inverters + 2 boundary ports.
        final second = await service.layout(
          NetlistModel.fromJson(_chainJson(3)).modules['chain']!,
        );
        expect(second.nodes, hasLength(5));
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test('cancelInFlightLayout abandons a running solve', () async {
      if (!requireElkFfiLibrary()) return;
      final service = ElkLayoutService();
      addTearDown(service.dispose);
      // Warm the worker on a tiny module so the cancel races a real solve,
      // not the init handshake.
      await service.layout(NetlistModel.fromJson(_andJson).modules['and2']!);
      final pending = service.layout(
        NetlistModel.fromJson(_chainJson(600)).modules['chain']!,
      );
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (!service.hasLayoutInFlight) {
        if (DateTime.now().isAfter(deadline)) {
          fail('the solve never went in flight');
        }
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      service.cancelInFlightLayout();
      await expectLater(
        pending,
        throwsA(
          isA<LayoutException>().having(
            (e) => e.message,
            'message',
            contains('cancelled'),
          ),
        ),
      );
      expect(service.hasLayoutInFlight, isFalse);
      // The next call lays out normally on the same warm worker.
      final next = await service.layout(
        NetlistModel.fromJson(_chainJson(3)).modules['chain']!,
      );
      expect(next.nodes, hasLength(5));
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  group('ElkLayoutService — layout cache', () {
    Module andModule() => NetlistModel.fromJson(_andJson).modules['and2']!;
    int solves(_ScriptedSolver solver) => solver.inputs.length;

    // Distinct modules produce distinct ELK inputs, hence distinct cache
    // keys — renaming the cell is enough to make the key differ.
    Module distinctModule(int i) {
      final json = <String, Object?>{
        'creator': 'Yosys test',
        'modules': <String, Object?>{
          'and2': <String, Object?>{
            'attributes': <String, Object?>{'top': '1'},
            'ports': <String, Object?>{
              'a': <String, Object?>{
                'direction': 'input',
                'bits': <Object>[2],
              },
              'y': <String, Object?>{
                'direction': 'output',
                'bits': <Object>[4],
              },
            },
            'cells': <String, Object?>{
              'u_and_$i': <String, Object?>{
                'hide_name': 0,
                'type': r'$and',
                'parameters': <String, Object?>{},
                'attributes': <String, Object?>{},
                'port_directions': <String, Object?>{
                  'A': 'input',
                  'Y': 'output',
                },
                'connections': <String, Object?>{
                  'A': <Object>[2],
                  'Y': <Object>[4],
                },
              },
            },
            'netnames': <String, Object?>{},
          },
        },
      };
      return NetlistModel.fromJson(json).modules['and2']!;
    }

    test(
      'memory cache: evicts least-recently-used past the entry cap',
      () async {
        final host = _ScriptedSolver(layoutJson: _kLayoutJson);
        final service = ElkLayoutService(
          solverFactory: () => host,
          maxMemCacheEntries: 2,
        );
        addTearDown(service.dispose);

        await service.layout(distinctModule(1));
        await service.layout(distinctModule(2));
        expect(service.memCacheLength, 2);

        // Touch #1 so #2 becomes the least-recently-used entry.
        await service.layout(distinctModule(1));
        expect(solves(host), 2, reason: 'the touch must be a cache hit');

        // Storing #3 evicts #2, not the freshly-touched #1.
        await service.layout(distinctModule(3));
        expect(service.memCacheLength, 2);
        await service.layout(distinctModule(1));
        expect(solves(host), 3, reason: '#1 must still be cached');
        await service.layout(distinctModule(2));
        expect(solves(host), 4, reason: '#2 must have been evicted');
      },
    );

    test('memory cache: evicts on the byte bound too', () async {
      final host = _ScriptedSolver(layoutJson: _kLayoutJson);
      final service = ElkLayoutService(
        solverFactory: () => host,
        // Smaller than a single result document, so every store evicts
        // everything except the entry just stored.
        maxMemCacheBytes: 1,
      );
      addTearDown(service.dispose);

      await service.layout(distinctModule(1));
      expect(service.memCacheLength, 1);
      expect(
        service.memCacheBytes,
        greaterThan(1),
        reason: 'an oversized single entry is retained, never self-evicted',
      );
      await service.layout(distinctModule(2));
      expect(service.memCacheLength, 1, reason: '#1 evicted by the byte bound');
      await service.layout(distinctModule(2));
      expect(solves(host), 2, reason: 'the just-stored entry is still cached');
    });

    test('memory cache: dispose resets the byte accounting', () async {
      final host = _ScriptedSolver(layoutJson: _kLayoutJson);
      final service = ElkLayoutService(solverFactory: () => host);
      await service.layout(distinctModule(1));
      expect(service.memCacheBytes, greaterThan(0));
      service.dispose();
      expect(service.memCacheLength, 0);
      expect(service.memCacheBytes, 0);
    });

    test('memory cache: re-laying the same module does not re-solve', () async {
      final host = _ScriptedSolver(layoutJson: _kLayoutJson);
      final service = ElkLayoutService(solverFactory: () => host);
      addTearDown(service.dispose);
      await service.layout(andModule());
      await service.layout(andModule());
      expect(solves(host), 1, reason: 'second call must hit the memory cache');
    });

    test(
      'disk cache: a cold service reads the persisted layout, no solve',
      () async {
        final disk = _MapDiskCache();
        // First service solves once and persists.
        final host1 = _ScriptedSolver(layoutJson: _kLayoutJson);
        final s1 = ElkLayoutService(
          solverFactory: () => host1,
          diskCache: disk,
        );
        await s1.layout(andModule());
        // The disk write is fire-and-forget — let it land.
        await Future<void>.delayed(Duration.zero);
        expect(disk.store, isNotEmpty);
        expect(solves(host1), 1);
        s1.dispose();

        // A fresh service over the same disk cache must read it back without
        // ever solving (the cross-session re-open path).
        final host2 = _ScriptedSolver(layoutJson: _kLayoutJson);
        final s2 = ElkLayoutService(
          solverFactory: () => host2,
          diskCache: disk,
        );
        addTearDown(s2.dispose);
        final fromDisk = await s2.layout(andModule());
        expect(fromDisk.nodes, isNotEmpty);
        expect(solves(host2), 0, reason: 'must be served from disk');
      },
    );

    test('FileLayoutDiskCache round-trips and prunes to maxEntries', () async {
      final tmp = Directory.systemTemp.createTempSync('elk_cache_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final cache = FileLayoutDiskCache(() async => tmp, maxEntries: 2);

      await cache.write('k1', '{"a":1}');
      expect(await cache.read('k1'), '{"a":1}');
      expect(await cache.read('missing'), isNull);

      // Over the cap → oldest pruned, count stays bounded.
      await cache.write('k2', 'v2');
      await cache.write('k3', 'v3');
      final files = Directory(p.join(tmp.path, 'layout-cache'))
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json.gz'))
          .toList();
      expect(files.length, lessThanOrEqualTo(2));
    });
  });

  group('LayoutPhase', () {
    test('maps the engine codes 1 to 5 in pipeline order, else null', () {
      expect(LayoutPhase.fromCode(0), isNull);
      expect(<LayoutPhase?>[
        for (var code = 1; code <= 5; code++) LayoutPhase.fromCode(code),
      ], LayoutPhase.values);
      expect(LayoutPhase.fromCode(6), isNull);
    });

    test('maps the elkrs phase names, else null', () {
      expect(LayoutPhase.fromName('cycle breaking'), LayoutPhase.cycleBreaking);
      expect(LayoutPhase.fromName('layering'), LayoutPhase.layering);
      expect(
        LayoutPhase.fromName('crossing minimization'),
        LayoutPhase.crossingMinimization,
      );
      expect(LayoutPhase.fromName('node placement'), LayoutPhase.nodePlacement);
      expect(LayoutPhase.fromName('edge routing'), LayoutPhase.edgeRouting);
      expect(LayoutPhase.fromName('wrapping'), isNull);
    });
  });

  group('driveElkSolveJob', () {
    test('passes each new report on once and returns the result', () async {
      final job = _ScriptedJob(<LayoutProgress?>[
        null,
        const LayoutProgress(phase: LayoutPhase.cycleBreaking, fraction: 0),
        const LayoutProgress(phase: LayoutPhase.cycleBreaking, fraction: 0),
        const LayoutProgress(phase: LayoutPhase.layering, fraction: 0.25),
        const LayoutProgress(phase: LayoutPhase.edgeRouting, fraction: 0.9),
      ]);
      final seen = <LayoutProgress>[];
      final result = await driveElkSolveJob(job, onProgress: seen.add);
      expect(result, '{"id":"root"}');
      expect(seen.map((p) => p.phase), <LayoutPhase>[
        LayoutPhase.cycleBreaking,
        LayoutPhase.layering,
        LayoutPhase.edgeRouting,
      ]);
      expect(job.finished, isTrue);
    });

    test('a cancelled job ends in LayoutCancelledException', () async {
      final job = _ScriptedJob(List<LayoutProgress?>.filled(1000, null));
      final solve = driveElkSolveJob(job);
      job.cancel();
      await expectLater(solve, throwsA(isA<LayoutCancelledException>()));
    });
  });

  group('ElkLayoutService — a solver that runs jobs', () {
    test('publishes progress while the solve runs, then clears it', () async {
      final solver = _ScriptedJobSolver(<LayoutProgress?>[
        const LayoutProgress(phase: LayoutPhase.cycleBreaking, fraction: 0),
        const LayoutProgress(
          phase: LayoutPhase.crossingMinimization,
          fraction: 0.5,
        ),
      ]);
      final service = ElkLayoutService(solverFactory: () => solver);
      addTearDown(service.dispose);
      final published = <LayoutProgress?>[];
      service.progress.addListener(() => published.add(service.progress.value));

      final layout = await service.layout(
        NetlistModel.fromJson(_andJson).modules['and2']!,
      );
      expect(layout.nodes, isNotEmpty);
      expect(published.whereType<LayoutProgress>().map((p) => p.phase), [
        LayoutPhase.cycleBreaking,
        LayoutPhase.crossingMinimization,
      ]);
      expect(service.progress.value, isNull);
      expect(service.hasLayoutInFlight, isFalse);
    });

    test('published progress never goes back to an earlier phase', () async {
      // The engine can run a phase again for a nested part of the design.
      final solver = _ScriptedJobSolver(<LayoutProgress?>[
        const LayoutProgress(phase: LayoutPhase.nodePlacement, fraction: 0.5),
        const LayoutProgress(
          phase: LayoutPhase.crossingMinimization,
          fraction: 0.2,
        ),
        const LayoutProgress(phase: LayoutPhase.nodePlacement, fraction: 0.3),
        const LayoutProgress(phase: LayoutPhase.edgeRouting, fraction: 0.4),
      ]);
      final service = ElkLayoutService(solverFactory: () => solver);
      addTearDown(service.dispose);
      final published = <LayoutProgress>[];
      service.progress.addListener(() {
        final value = service.progress.value;
        if (value != null) published.add(value);
      });

      await service.layout(NetlistModel.fromJson(_andJson).modules['and2']!);

      final phases = published.map((p) => p.phase.index).toList();
      expect(phases, orderedEquals([...phases]..sort()));
      final fractions = published.map((p) => p.fraction!).toList();
      expect(fractions, orderedEquals([...fractions]..sort()));
      expect(published.last.phase, LayoutPhase.edgeRouting);
    });

    test('monotonicLayoutProgress keeps the furthest phase and share', () {
      const placing = LayoutProgress(
        phase: LayoutPhase.nodePlacement,
        fraction: 0.6,
      );
      expect(monotonicLayoutProgress(null, placing), placing);
      // An earlier phase is dropped.
      expect(
        monotonicLayoutProgress(
          placing,
          const LayoutProgress(
            phase: LayoutPhase.crossingMinimization,
            fraction: 0.7,
          ),
        ),
        placing,
      );
      // The same phase with a smaller share keeps the share.
      expect(
        monotonicLayoutProgress(
          placing,
          const LayoutProgress(phase: LayoutPhase.nodePlacement, fraction: 0.3),
        ),
        placing,
      );
      // A later phase is taken, and its share does not drop below the last.
      expect(
        monotonicLayoutProgress(
          placing,
          const LayoutProgress(phase: LayoutPhase.edgeRouting, fraction: 0.5),
        ),
        const LayoutProgress(phase: LayoutPhase.edgeRouting, fraction: 0.6),
      );
      // An engine that reports no share is passed through.
      const unknown = LayoutProgress(phase: LayoutPhase.edgeRouting);
      expect(monotonicLayoutProgress(placing, unknown), unknown);
    });

    test('cancelInFlightLayout stops the job: LayoutCancelledException, and '
        'the next layout runs', () async {
      final solver = _ScriptedJobSolver(
        List<LayoutProgress?>.filled(
          100000,
          const LayoutProgress(phase: LayoutPhase.layering, fraction: 0.1),
        ),
      );
      final service = ElkLayoutService(solverFactory: () => solver);
      addTearDown(service.dispose);
      final pending = service.layout(
        NetlistModel.fromJson(_chainJson(4)).modules['chain']!,
      );
      while (service.progress.value == null) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      expect(service.hasLayoutInFlight, isTrue);
      service.cancelInFlightLayout();
      await expectLater(pending, throwsA(isA<LayoutCancelledException>()));
      expect(service.hasLayoutInFlight, isFalse);
      expect(service.progress.value, isNull);

      solver.script = <LayoutProgress?>[null];
      final next = await service.layout(
        NetlistModel.fromJson(_andJson).modules['and2']!,
      );
      expect(next.nodes, isNotEmpty);
    });
  });

  group('LayoutException', () {
    test('toString includes message and cause when present', () {
      const a = LayoutException('boom');
      expect(a.toString(), contains('boom'));
      const b = LayoutException('with cause', cause: 'inner');
      expect(b.toString(), allOf(contains('with cause'), contains('inner')));
    });

    test('defaults to kind other with no file', () {
      const e = LayoutException('x');
      expect(e.kind, LayoutFailureKind.other);
      expect(e.engineFile, isNull);
    });

    // netcrux#86: the worker isolate opens the engine, so an engine that
    // does not load reaches the canvas only through this message. It must
    // keep its kind and the file it names, or the canvas words it as a
    // generic failure and the file is lost.
    test('crosses the worker boundary with its kind, message and file', () {
      const failure = LayoutException(
        'the layout engine library libelk_ffi.so could not be loaded: gone',
        kind: LayoutFailureKind.engineUnavailable,
        engineFile: 'libelk_ffi.so',
      );
      final message = layoutExceptionToMessage(failure);
      expect(message['ok'], isFalse);
      final back = layoutExceptionFromMessage(message);
      expect(back.kind, LayoutFailureKind.engineUnavailable);
      expect(back.engineFile, 'libelk_ffi.so');
      expect(back.message, failure.message);
    });

    test('an engine rejection crosses as kind other with no file', () {
      final back = layoutExceptionFromMessage(
        layoutExceptionToMessage(
          const LayoutException('elk rejected the layout input: bad port'),
        ),
      );
      expect(back.kind, LayoutFailureKind.other);
      expect(back.engineFile, isNull);
      expect(back.message, 'elk rejected the layout input: bad port');
    });

    test('an error that was not a LayoutException arrives as text', () {
      final back = layoutExceptionFromMessage(<Object?, Object?>{
        'ok': false,
        'error': 'StateError: boom',
      }, prefix: 'the layout worker did not start: ');
      expect(back.kind, LayoutFailureKind.other);
      expect(back.engineFile, isNull);
      expect(back.message, 'the layout worker did not start: StateError: boom');
    });

    test('a kind this build does not know arrives as other', () {
      final back = layoutExceptionFromMessage(<Object?, Object?>{
        'ok': false,
        'error': 'x',
        'kind': 'somethingNewer',
        'engineFile': 7,
      });
      expect(back.kind, LayoutFailureKind.other);
      expect(back.engineFile, isNull);
    });
  });
}

/// A minimal result JSON the scripted solver returns: a root with one
/// positioned child, so `NetlistLayout.fromJson` yields a non-empty layout.
const String _kLayoutJson =
    '{"id":"root","x":0,"y":0,"width":100,'
    '"height":100,"children":[{"id":"u_and","x":10,"y":10,"width":80,'
    '"height":32}],"edges":[]}';

/// An [ElkSolveJob] that reports one entry of [script] per poll and is done
/// after the last one, or at the first poll after [cancel].
class _ScriptedJob implements ElkSolveJob {
  _ScriptedJob(this.script, {this.result = '{"id":"root"}'});

  final List<LayoutProgress?> script;
  final String result;
  int _polls = 0;
  bool _cancelled = false;
  bool finished = false;

  @override
  ({bool done, LayoutProgress? progress}) poll() {
    final i = _polls++;
    final progress = script.isEmpty
        ? null
        : script[i.clamp(0, script.length - 1)];
    return (done: _cancelled || i >= script.length - 1, progress: progress);
  }

  @override
  void cancel() => _cancelled = true;

  @override
  String finish() {
    finished = true;
    if (_cancelled) throw const LayoutCancelledException();
    return result;
  }
}

/// An [ElkJobSolver] whose jobs follow [script] and return [_kLayoutJson].
class _ScriptedJobSolver implements ElkJobSolver {
  _ScriptedJobSolver(this.script);

  List<LayoutProgress?> script;

  @override
  String get engineDescription => 'scripted jobs';

  @override
  String solve(String inputJson) => _kLayoutJson;

  @override
  ElkSolveJob start(String inputJson) =>
      _ScriptedJob(script, result: _kLayoutJson);

  @override
  void dispose() {}
}

/// In-memory [LayoutDiskCache] for the cache tests — stands in for the
/// on-disk store so a cold service can read back what a warm one wrote.
class _MapDiskCache implements LayoutDiskCache {
  final Map<String, String> store = <String, String>{};

  @override
  Future<String?> read(String key) async => store[key];

  @override
  Future<void> write(String key, String value) async => store[key] = value;
}

/// One module `m` with a single driver cell on net 1 fanning out to
/// [sinks] sink cells on the same net — a synthetic clock/reset-style
/// high-fanout net for the edge-cap test.
Map<String, Object?> _fanoutJson(int sinks) {
  final cells = <String, Object?>{
    'drv': <String, Object?>{
      'type': r'$buf',
      'parameters': <String, Object?>{},
      'attributes': <String, Object?>{},
      'port_directions': <String, Object?>{'Y': 'output'},
      'connections': <String, Object?>{
        'Y': <Object>[1],
      },
    },
  };
  for (var i = 0; i < sinks; i++) {
    cells['s$i'] = <String, Object?>{
      'type': r'$buf',
      'parameters': <String, Object?>{},
      'attributes': <String, Object?>{},
      'port_directions': <String, Object?>{'A': 'input'},
      'connections': <String, Object?>{
        'A': <Object>[1],
      },
    };
  }
  return <String, Object?>{
    'creator': 'test',
    'modules': <String, Object?>{
      'm': <String, Object?>{
        'attributes': <String, Object?>{'top': '1'},
        'ports': <String, Object?>{},
        'cells': cells,
        'netnames': <String, Object?>{},
      },
    },
  };
}
