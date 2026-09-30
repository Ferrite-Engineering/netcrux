// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/netlist/module.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/services/layout/elk_layout_service.dart';
import 'package:netcrux/services/layout/layout_disk_cache_vm.dart';
import 'package:path/path.dart' as p;

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

/// Minimal scripted host: simulates the JS engine by returning the
/// caller-specified layout JSON / error string when the service probes
/// `__elk_result` / `__elk_error`.
class _ScriptedHost implements ElkJsHost {
  _ScriptedHost({this.layoutJson, this.errorMessage});

  final String? layoutJson;
  final String? errorMessage;

  final List<String> evaluatedScripts = <String>[];
  int pendingJobs = 0;
  bool disposed = false;
  bool _layoutCalled = false;

  @override
  String evaluate(String code) {
    evaluatedScripts.add(code);
    if (code.contains('__elkInstance')) {
      _layoutCalled = true;
      return '';
    }
    if (code.contains('"pending"')) {
      // First probe reports pending; after one job tick, we say done.
      if (_layoutCalled && pendingJobs >= 1) return 'done';
      return 'pending';
    }
    if (code.contains('__elk_error')) {
      return errorMessage ?? '';
    }
    if (code.contains('__elk_result')) {
      return layoutJson ?? '';
    }
    return '';
  }

  @override
  int executePendingJob() {
    pendingJobs++;
    return 0;
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
        // breaking — ~halves the QuickJS solve on a dense register-heavy core.
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
    test('layout returns a NetlistLayout when elkjs reports success', () async {
      final host = _ScriptedHost(
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
      final service = ElkLayoutService(
        hostFactory: () => host,
        assetLoader: (key) async => '// fake elk bundle',
      );
      final model = NetlistModel.fromJson(_andJson);
      final layout = await service.layout(model.modules['and2']!);
      expect(layout.bounds.width, 200);
      expect(layout.nodes, hasLength(1));
      expect(layout.nodes.first.id, 'u_and');
      // The service wrote the input + layout call to the host.
      expect(
        host.evaluatedScripts.any((s) => s.contains('__elk_input')),
        isTrue,
      );
    });

    test('layout surfaces elk-reported errors as LayoutException', () async {
      final host = _ScriptedHost(errorMessage: 'invalid layout input');
      final service = ElkLayoutService(
        hostFactory: () => host,
        assetLoader: (key) async => '// fake elk bundle',
      );
      final model = NetlistModel.fromJson(_andJson);
      expect(
        () => service.layout(model.modules['and2']!),
        throwsA(
          isA<LayoutException>().having(
            (e) => e.message,
            'message',
            contains('elkjs rejected'),
          ),
        ),
      );
    });

    test('layout treats an asset-load failure as LayoutException', () async {
      final host = _ScriptedHost();
      final service = ElkLayoutService(
        hostFactory: () => host,
        assetLoader: (key) async => throw const FormatException('no asset'),
      );
      final model = NetlistModel.fromJson(_andJson);
      expect(
        () => service.layout(model.modules['and2']!),
        throwsA(
          isA<LayoutException>().having(
            (e) => e.message,
            'message',
            contains('initialize'),
          ),
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
      final service = ElkLayoutService(
        hostFactory: _ScriptedHost.new,
        assetLoader: (key) async => '// fake',
      );
      expect(await service.layoutTop(NetlistModel.fromJson(noTopJson)), isNull);
    });

    test('dispose tears down the host and resets initialization', () async {
      final host = _ScriptedHost(
        layoutJson: '{"id":"root","x":0,"y":0,"width":1,"height":1}',
      );
      final service = ElkLayoutService(
        hostFactory: () => host,
        assetLoader: (key) async => '// fake',
      );
      final model = NetlistModel.fromJson(_andJson);
      await service.layout(model.modules['and2']!);
      service.dispose();
      expect(host.disposed, isTrue);
    });
  });

  group('ElkLayoutService — isolate offload (production path)', () {
    // No injected hostFactory → production path → the elkjs solve runs on a
    // dedicated background isolate. Drives real flutter_js + the committed
    // elk bundle, so it proves the offload end-to-end (init handshake, the
    // benign "Binding not initialized" non-fatal worker error is tolerated,
    // result marshalled back, warm reuse).
    test(
      'lays out a real design on a background isolate + reuses it warm',
      () async {
        final module = NetlistModel.fromJson(_andJson).modules['and2']!;
        final service = ElkLayoutService(
          assetLoader: (_) async =>
              File('assets/elk/elk.bundled.js').readAsStringSync(),
        );
        addTearDown(service.dispose);

        try {
          final first = await service.layout(module);
          // and2 = 1 cell (u_and) + 3 boundary ports → 4 nodes, all positioned.
          expect(first.nodes, hasLength(4));
          // A second layout reuses the warm worker isolate (no re-spawn/re-init).
          final second = await service.layout(module);
          expect(second.nodes, hasLength(4));
        } on LayoutException catch (e) {
          // The production path drives flutter_js (QuickJS) on a background
          // isolate, which needs the libquickjs_c_bridge_plugin native library.
          // Plain `flutter test` (the CI unit-test VM) doesn't build/ship plugin
          // natives, so the isolate can't load it. Skip rather than fail — the
          // offload is exercised where the native lib is present (a full app
          // build / local dev), mirroring other native-lib-gated suites.
          if (e.message.contains('Failed to load dynamic library')) {
            markTestSkipped(
              'flutter_js (QuickJS) native library unavailable in this '
              'environment; isolate-offload path skipped.',
            );
            return;
          }
          rethrow;
        }
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test('cancelInFlightLayout abandons a running solve', () async {
      final service = ElkLayoutService(
        assetLoader: (_) async =>
            File('assets/elk/elk.bundled.js').readAsStringSync(),
      );
      addTearDown(service.dispose);
      // Warm the worker on a tiny module so the cancel races a real solve,
      // not the init handshake; skip where no engine can start.
      try {
        await service.layout(NetlistModel.fromJson(_andJson).modules['and2']!);
      } on LayoutException catch (e) {
        if (e.message.contains('Failed to load dynamic library')) {
          markTestSkipped(
            'flutter_js native library unavailable in this environment; '
            'cancellation skipped.',
          );
          return;
        }
        rethrow;
      }
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
      // The next call starts a fresh worker and lays out normally.
      final next = await service.layout(
        NetlistModel.fromJson(_chainJson(3)).modules['chain']!,
      );
      expect(next.nodes, hasLength(5));
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  group('ElkLayoutService — layout cache', () {
    Module andModule() => NetlistModel.fromJson(_andJson).modules['and2']!;
    int solves(_ScriptedHost host) =>
        host.evaluatedScripts.where((s) => s.contains('__elk_input =')).length;

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
        final host = _ScriptedHost(layoutJson: _kLayoutJson);
        final service = ElkLayoutService(
          hostFactory: () => host,
          assetLoader: (_) async => '// fake',
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
      final host = _ScriptedHost(layoutJson: _kLayoutJson);
      final service = ElkLayoutService(
        hostFactory: () => host,
        assetLoader: (_) async => '// fake',
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
      final host = _ScriptedHost(layoutJson: _kLayoutJson);
      final service = ElkLayoutService(
        hostFactory: () => host,
        assetLoader: (_) async => '// fake',
      );
      await service.layout(distinctModule(1));
      expect(service.memCacheBytes, greaterThan(0));
      service.dispose();
      expect(service.memCacheLength, 0);
      expect(service.memCacheBytes, 0);
    });

    test('memory cache: re-laying the same module does not re-solve', () async {
      final host = _ScriptedHost(layoutJson: _kLayoutJson);
      final service = ElkLayoutService(
        hostFactory: () => host,
        assetLoader: (_) async => '// fake',
      );
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
        final host1 = _ScriptedHost(layoutJson: _kLayoutJson);
        final s1 = ElkLayoutService(
          hostFactory: () => host1,
          assetLoader: (_) async => '// fake',
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
        final host2 = _ScriptedHost(layoutJson: _kLayoutJson);
        final s2 = ElkLayoutService(
          hostFactory: () => host2,
          assetLoader: (_) async => '// fake',
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

  group('layoutTimeoutFor', () {
    test('is two minutes for anything under a thousand elements', () {
      expect(layoutTimeoutFor(elementCount: 0), const Duration(minutes: 2));
      expect(layoutTimeoutFor(elementCount: 999), const Duration(minutes: 2));
    });

    test('adds a minute per thousand elements', () {
      expect(layoutTimeoutFor(elementCount: 1000), const Duration(minutes: 3));
      expect(layoutTimeoutFor(elementCount: 5600), const Duration(minutes: 7));
    });

    test('caps at twenty minutes', () {
      expect(
        layoutTimeoutFor(elementCount: 100000),
        const Duration(minutes: 20),
      );
    });
  });

  group('elkElementCount', () {
    test('counts nodes plus edges of an ELK input', () {
      final input = buildElkInput(
        NetlistModel.fromJson(_andJson).modules['and2']!,
      );
      // and2: one cell plus three boundary ports, joined by three edges.
      expect(elkElementCount(input), 7);
      expect(
        elkElementCount(input),
        (input['children']! as List).length + (input['edges']! as List).length,
      );
    });

    test('tolerates an input without the lists', () {
      expect(elkElementCount(const <String, Object?>{}), 0);
    });
  });

  group('LayoutException', () {
    test('toString includes message and cause when present', () {
      const a = LayoutException('boom');
      expect(a.toString(), contains('boom'));
      const b = LayoutException('with cause', cause: 'inner');
      expect(b.toString(), allOf(contains('with cause'), contains('inner')));
    });
  });
}

/// A minimal elkjs result JSON the scripted host returns — a root with one
/// positioned child, so `NetlistLayout.fromJson` yields a non-empty layout.
const String _kLayoutJson =
    '{"id":"root","x":0,"y":0,"width":100,'
    '"height":100,"children":[{"id":"u_and","x":10,"y":10,"width":80,'
    '"height":32}],"edges":[]}';

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
