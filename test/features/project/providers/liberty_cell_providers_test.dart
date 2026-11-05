// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The tab's cell libraries reach the schematic: the index is read through
// the stub service's cache once the design has loaded, the drawing and the
// area roll-up are derived from it, and the layout pass lays a gate-level
// scope out once, with the library's drawing.

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/custom_cell_symbol/cell_symbol_geometry.dart';
import 'package:netcrux/domain/models/layout/bounding_box.dart';
import 'package:netcrux/domain/models/layout/edge_route.dart';
import 'package:netcrux/domain/models/layout/netlist_layout.dart';
import 'package:netcrux/domain/models/layout/node_position.dart';
import 'package:netcrux/domain/models/netlist/module.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/project/netcrux_project.dart';
import 'package:netcrux/domain/models/schematic/cell_kind.dart';
import 'package:netcrux/domain/models/schematic/laid_out_graph.dart';
import 'package:netcrux/domain/models/schematic/liberty_cell_symbols.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/project/providers/current_laid_out_graph_provider.dart';
import 'package:netcrux/features/project/providers/current_project_provider.dart';
import 'package:netcrux/features/project/providers/liberty_cell_providers.dart';
import 'package:netcrux/features/project/providers/loaded_netlist_provider.dart';
import 'package:netcrux/services/layout/elk_layout_service.dart';
import 'package:netcrux/services/layout/elk_layout_service_provider.dart';
import 'package:netcrux/services/liberty/liberty_stub_service.dart';
import 'package:netcrux/services/liberty/liberty_stub_service_provider.dart';
import 'package:path/path.dart' as p;

const String _library = '''
library (gates_tt) {
  cell (NAND2) {
    area : 2.5 ;
    pg_pin (VDD) { pg_type : primary_power ; }
    pg_pin (VSS) { pg_type : primary_ground ; }
    pin (A) { direction : input ; }
    pin (B) { direction : input ; }
    pin (Y) { direction : output ; function : "!(A B)" ; }
  }
}
''';

/// `top` with two NAND2s wired to power and ground.
final NetlistModel _model = NetlistModel.fromJson(<String, Object?>{
  'creator': 'test',
  'modules': <String, Object?>{
    'top': <String, Object?>{
      'attributes': const <String, Object?>{'top': '1'},
      'ports': const <String, Object?>{
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
        for (final (name, a, y) in <(String, int, int)>[
          ('u0', 2, 3),
          ('u1', 3, 4),
        ])
          name: <String, Object?>{
            'type': 'NAND2',
            'port_directions': <String, Object?>{
              'A': 'input',
              'B': 'input',
              'Y': 'output',
              'VDD': 'inout',
              'VSS': 'inout',
            },
            'connections': <String, Object?>{
              'A': <Object>[a],
              'B': <Object>[a],
              'Y': <Object>[y],
              'VDD': <Object>[8],
              'VSS': <Object>[9],
            },
          },
      },
    },
    'NAND2': const <String, Object?>{
      'attributes': <String, Object?>{'blackbox': '1'},
    },
  },
});

class _FixedNetlist extends LoadedNetlist {
  @override
  Future<NetlistModel?> build() async => _model;
}

/// A design that fails to load, once [_FailingNetlist.release] completes.
class _FailingNetlist extends LoadedNetlist {
  _FailingNetlist(this.release);

  final Future<void> release;

  @override
  Future<NetlistModel?> build() async {
    ref.watch(currentProjectProvider);
    await release;
    throw const LoadedNetlistException(
      'Yosys is not available',
      kind: LoadedNetlistErrorKind.yosysUnavailable,
    );
  }
}

/// Lays every cell out in a row and remembers what it was asked.
class _RecordingLayout extends ElkLayoutService {
  final List<LibertyCellSymbols> calls = <LibertyCellSymbols>[];

  @override
  Future<NetlistLayout> layout(
    Module module, {
    CellSymbolGeometries symbols = CellSymbolGeometries.none,
    LibertyCellSymbols liberty = LibertyCellSymbols.none,
    ElkSubgraph? only,
  }) async {
    calls.add(liberty);
    return NetlistLayout(
      nodes: <NodePosition>[
        for (final (i, name) in module.cells.keys.indexed)
          NodePosition(
            id: name,
            bounds: BoundingBox(x: i * 100.0, y: 0, width: 80, height: 62),
          ),
      ],
      edges: const <EdgeRoute>[],
      bounds: const BoundingBox(x: 0, y: 0, width: 200, height: 62),
    );
  }
}

void main() {
  late Directory root;
  late String libPath;
  setUp(() {
    root = Directory.systemTemp.createTempSync('liberty_providers_');
    libPath = p.join(root.path, 'gates_tt.lib');
    File(libPath).writeAsStringSync(_library);
  });
  tearDown(() => root.deleteSync(recursive: true));

  ProviderContainer container({List<Override> extra = const <Override>[]}) {
    final c = ProviderContainer(
      overrides: <Override>[
        loadedNetlistProvider.overrideWith(_FixedNetlist.new),
        libertyStubServiceProvider.overrideWithValue(
          LibertyStubService(
            cacheBaseDirectory: () async => Directory(p.join(root.path, 'c')),
          ),
        ),
        ...extra,
      ],
    );
    addTearDown(c.dispose);
    c
        .read(currentProjectProvider.notifier)
        .setProject(
          NetcruxProject.create(
            sourceFiles: const <String>['top.v'],
            libertyFiles: <String>[libPath],
          ),
        );
    return c;
  }

  test("the index is the project's libraries, read after the design", () async {
    final c = container();
    final index = await c.read(libertyCellIndexProvider.future);
    expect(index.length, 1);
    expect(index['NAND2']!.library.name, 'gates_tt');
    final symbols = await c.read(libertyCellSymbolsProvider.future);
    expect(symbols['NAND2']!.kind, CellKind.nandGate);
    expect(symbols['NAND2']!.powerPins, <String>{'VDD'});
    final areas = c.read(moduleAreaRollupProvider)!;
    expect(areas.areaOf('top')!.area, 5);
    expect(areas.areaOf('top')!.partial, isFalse);
  });

  test('a project without libraries has none, and no area', () async {
    final c = container();
    c.read(currentProjectProvider.notifier).setLibertyFiles(const <String>[]);
    expect((await c.read(libertyCellIndexProvider.future)).isEmpty, isTrue);
    expect(
      await c.read(libertyCellSymbolsProvider.future),
      LibertyCellSymbols.none,
    );
    expect(c.read(moduleAreaRollupProvider), isNull);
  });

  test(
    'a library that cannot be read leaves the index empty, not failed',
    () async {
      File(libPath).writeAsStringSync('not liberty');
      final c = container();
      expect((await c.read(libertyCellIndexProvider.future)).isEmpty, isTrue);
    },
  );

  test('the layout pass draws the cells as gates and lays the scope out '
      'once, with the supply pins placed', () async {
    final layout = _RecordingLayout();
    addTearDown(layout.dispose);
    final c = container(
      extra: <Override>[elkLayoutServiceProvider.overrideWithValue(layout)],
    );
    c.read(hierarchyTreeProvider.notifier).setModel(_model);
    final sub = c.listen<AsyncValue<LaidOutGraph>>(
      currentLaidOutGraphProvider,
      (previous, next) {},
    );
    addTearDown(sub.close);
    final laidOut = await c.read(currentLaidOutGraphProvider.future);
    expect(laidOut.graph.cells.map((cell) => cell.kind), <CellKind>[
      CellKind.nandGate,
      CellKind.nandGate,
    ]);
    expect(layout.calls, hasLength(1));
    expect(layout.calls.single['NAND2']!.supplyFace('VSS'), 'SOUTH');
  });
  test(
    'a design that fails while another zone waits on it leaves the '
    'drawing and the index empty, and its failure stays in the design',
    () async {
      final release = Completer<void>();
      final c = ProviderContainer(
        overrides: <Override>[
          loadedNetlistProvider.overrideWith(
            () => _FailingNetlist(release.future),
          ),
          libertyStubServiceProvider.overrideWithValue(
            LibertyStubService(
              cacheBaseDirectory: () async => Directory(p.join(root.path, 'c')),
            ),
          ),
        ],
      );
      addTearDown(c.dispose);
      c
          .read(currentProjectProvider.notifier)
          .setProject(
            NetcruxProject.create(
              sourceFiles: const <String>['top.v'],
              libertyFiles: <String>[libPath],
            ),
          );
      // The design starts loading in this zone, and the Inspector reads the
      // libraries from another error zone, as a frame callback registered in
      // another zone does. A failure awaited across that boundary used to be
      // reported as uncaught and left both providers loading.
      c.listen(loadedNetlistProvider, (_, _) {});
      final escaped = <Object>[];
      runZonedGuarded(() {
        c
          ..listen(libertyCellSymbolsProvider, (_, _) {})
          ..listen(libertyCellIndexProvider, (_, _) {});
      }, (error, _) => escaped.add(error));
      release.complete();

      expect(
        await c.read(libertyCellSymbolsProvider.future),
        LibertyCellSymbols.none,
      );
      expect((await c.read(libertyCellIndexProvider.future)).isEmpty, isTrue);
      expect(
        c.read(loadedNetlistProvider).error,
        isA<LoadedNetlistException>(),
      );
      expect(escaped, isEmpty);
    },
  );
}
