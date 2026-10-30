// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/app_settings.dart';
import 'package:netcrux/domain/models/custom_cell_symbol/cell_symbol_geometry.dart';
import 'package:netcrux/domain/models/layout/bounding_box.dart';
import 'package:netcrux/domain/models/layout/edge_route.dart';
import 'package:netcrux/domain/models/layout/netlist_layout.dart';
import 'package:netcrux/domain/models/layout/node_position.dart';
import 'package:netcrux/domain/models/netlist/hierarchy_node.dart';
import 'package:netcrux/domain/models/schematic/laid_out_graph.dart';
import 'package:netcrux/domain/models/schematic/scope_layout_gate.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/domain/models/trace/cone_view.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/project/providers/current_laid_out_graph_provider.dart';
import 'package:netcrux/features/project/providers/loaded_netlist_provider.dart';
import 'package:netcrux/features/project/providers/scope_layout_gate_provider.dart';
import 'package:netcrux/features/settings/providers/app_settings_provider.dart';
import 'package:netcrux/features/viewer/providers/cone_view_notifier.dart';
import 'package:netcrux/features/viewer/providers/layout_approval_notifier.dart';
import 'package:netcrux/services/layout/elk_layout_service.dart';
import 'package:netcrux/services/layout/elk_layout_service_provider.dart';
import 'package:netcrux/services/yosys/chunked_yosys_json_reader.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lays every node out in a row and counts the layouts it was asked for: a
/// scope the guard holds back must reach it zero times.
class _CountingLayoutService extends ElkLayoutService {
  int calls = 0;
  ElkSubgraph? lastOnly;

  @override
  Future<NetlistLayout> layout(
    Module module, {
    CellSymbolGeometries symbols = CellSymbolGeometries.none,
    ElkSubgraph? only,
  }) async {
    calls++;
    lastOnly = only;
    return NetlistLayout(
      nodes: <NodePosition>[
        for (final (i, name) in module.cells.keys.indexed)
          if (only == null || only.cellIds.contains(name))
            NodePosition(
              id: name,
              bounds: BoundingBox(x: i * 100.0, y: 0, width: 80, height: 40),
            ),
      ],
      edges: const <EdgeRoute>[],
      bounds: const BoundingBox(x: 0, y: 0, width: 400, height: 40),
    );
  }
}

NetlistModel? _injectedNetlist;

class _StubLoadedNetlist extends LoadedNetlist {
  @override
  Future<NetlistModel?> build() async => _injectedNetlist;
}

int _injectedLimit = kDefaultLayoutCellLimit;

class _StubSettings extends AppSettingsNotifier {
  @override
  Future<AppSettings> build() async =>
      const AppSettings.defaults().copyWith(layoutCellLimit: _injectedLimit);
}

NetlistModel _loadFixture(String name) {
  final raw = File(
    'test/fixtures/verilog/$name.expected.json',
  ).readAsStringSync();
  return NetlistModel.fromJson(jsonDecode(raw) as Map<String, Object?>);
}

/// A model whose only module holds [cells] inverters wired in a chain, the
/// shape of a flat post-synthesis scope.
NetlistModel _flatChain(int cells) {
  const directions = <String, PortDirection>{
    'A': PortDirection.input,
    'Y': PortDirection.output,
  };
  return NetlistModel(
    creator: 'test',
    modules: <String, Module>{
      'flat': Module(
        name: 'flat',
        attributes: const <String, String>{'top': '1'},
        ports: const <String, Port>{},
        cells: <String, Cell>{
          for (var i = 0; i < cells; i++)
            'u$i': Cell(
              name: 'u$i',
              type: r'$not',
              parameters: const <String, String>{},
              attributes: const <String, String>{},
              portDirections: directions,
              connections: <String, List<BitRef>>{
                'A': <BitRef>[NetBit(i + 2)],
                'Y': <BitRef>[NetBit(i + 3)],
              },
            ),
        },
        nets: <String, Net>{
          for (var i = 0; i < cells; i++)
            'n$i': Net(
              name: 'n$i',
              bits: <BitRef>[NetBit(i + 3)],
              attributes: const <String, String>{},
            ),
        },
      ),
    },
  );
}

/// A container over [model] with the layout limit at [limit] and a counting
/// layout service, the shape of one tab.
({ProviderContainer container, _CountingLayoutService service}) _tab(
  NetlistModel model, {
  required int limit,
}) {
  _injectedNetlist = model;
  _injectedLimit = limit;
  final service = _CountingLayoutService();
  final container = ProviderContainer(
    overrides: <Override>[
      elkLayoutServiceProvider.overrideWithValue(service),
      loadedNetlistProvider.overrideWith(_StubLoadedNetlist.new),
      appSettingsProvider.overrideWith(_StubSettings.new),
    ],
  );
  addTearDown(container.dispose);
  // Read once so the settings finish loading before the first decision.
  container.listen(appSettingsProvider, (_, _) {});
  container.read(hierarchyTreeProvider.notifier).setModel(model);
  return (container: container, service: service);
}

Future<LaidOutGraph> _laidOut(ProviderContainer container) async {
  final sub = container.listen<AsyncValue<LaidOutGraph>>(
    currentLaidOutGraphProvider,
    (previous, next) {},
  );
  addTearDown(sub.close);
  return await container.read(currentLaidOutGraphProvider.future);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('scopeLayoutGateProvider', () {
    late NetlistModel chain;
    setUp(() => chain = _loadFixture('large_chain'));

    Future<ProviderContainer> open({required int limit}) async {
      final tab = _tab(chain, limit: limit);
      await tab.container.read(appSettingsProvider.future);
      await tab.container.read(loadedNetlistProvider.future);
      return tab.container;
    }

    test('counts the cells of the selected scope', () async {
      final container = await open(limit: 10);
      final gate = container.read(scopeLayoutGateProvider);
      expect(gate.cellCount, 32);
      expect(gate.limit, 10);
      expect(gate.deferred, isTrue);
    });

    test('a scope under the limit is not deferred', () async {
      final container = await open(limit: 32);
      expect(container.read(scopeLayoutGateProvider).deferred, isFalse);
    });

    test('a limit of zero never defers', () async {
      final container = await open(limit: 0);
      expect(container.read(scopeLayoutGateProvider).deferred, isFalse);
    });

    test('no model is nothing to hold back', () async {
      final tab = _tab(chain, limit: 10);
      _injectedNetlist = null;
      tab.container.invalidate(loadedNetlistProvider);
      await tab.container.read(appSettingsProvider.future);
      expect(tab.container.read(scopeLayoutGateProvider).deferred, isFalse);
      expect(tab.container.read(scopeLayoutGateProvider).cellCount, 0);
    });

    test('approving the scope lifts the hold', () async {
      final container = await open(limit: 10);
      final scope = container.read(hierarchyTreeProvider).selected!;
      container.read(layoutApprovalProvider.notifier).approve(scope);
      expect(container.read(scopeLayoutGateProvider).approved, isTrue);
      expect(container.read(scopeLayoutGateProvider).deferred, isFalse);
    });

    test('a cone view of the scope is never held back', () async {
      final container = await open(limit: 10);
      final scope = container.read(hierarchyTreeProvider).selected!;
      container
          .read(coneViewProvider.notifier)
          .show(
            ConeViewRequest(
              scope: scope,
              root: const SelectedElement.cell(cellId: 'u_inv_10'),
            ),
          );
      expect(container.read(scopeLayoutGateProvider).inCone, isTrue);
      expect(container.read(scopeLayoutGateProvider).deferred, isFalse);
      container.read(coneViewProvider.notifier).exit();
      expect(container.read(scopeLayoutGateProvider).deferred, isTrue);
    });

    test('a change of the limit applies to the scope on show', () async {
      final container = await open(limit: 10);
      expect(container.read(scopeLayoutGateProvider).deferred, isTrue);
      await container.read(appSettingsProvider.notifier).setLayoutCellLimit(0);
      expect(container.read(scopeLayoutGateProvider).deferred, isFalse);
    });
  });

  group('currentLaidOutGraphProvider under the layout limit', () {
    late NetlistModel chain;
    late ProviderContainer container;
    late _CountingLayoutService service;
    setUp(() => chain = _loadFixture('large_chain'));

    Future<void> open({required int limit}) async {
      final tab = _tab(chain, limit: limit);
      container = tab.container;
      service = tab.service;
      await container.read(appSettingsProvider.future);
      await container.read(loadedNetlistProvider.future);
    }

    test('a scope over the limit is not laid out', () async {
      await open(limit: 10);
      final result = await _laidOut(container);
      expect(result, LaidOutGraph.empty);
      expect(service.calls, 0);
    });

    test('lays out a scope at the limit', () async {
      await open(limit: 32);
      final result = await _laidOut(container);
      expect(result.graph.cells, hasLength(32));
      expect(service.calls, 1);
    });

    test('lays the scope out once the user asks', () async {
      await open(limit: 10);
      expect(await _laidOut(container), LaidOutGraph.empty);
      final scope = container.read(hierarchyTreeProvider).selected!;
      container.read(layoutApprovalProvider.notifier).approve(scope);
      final result = await _laidOut(container);
      expect(result.graph.cells, hasLength(32));
      expect(result.cone, isNull);
      expect(service.calls, 1);
    });

    test('a cone view lays out the cone and nothing more', () async {
      await open(limit: 10);
      final scope = container.read(hierarchyTreeProvider).selected!;
      container
          .read(coneViewProvider.notifier)
          .show(
            ConeViewRequest(
              scope: scope,
              root: const SelectedElement.cell(cellId: 'u_inv_10'),
            ),
          );
      final result = await _laidOut(container);
      expect(result.graph.cells, hasLength(3));
      expect(result.cone?.scopeCellCount, 32);
      expect(service.calls, 1);
      expect(service.lastOnly?.cellIds, hasLength(3));
    });

    test('leaving the cone view returns to the held-back scope', () async {
      await open(limit: 10);
      final scope = container.read(hierarchyTreeProvider).selected!;
      container
          .read(coneViewProvider.notifier)
          .show(
            ConeViewRequest(
              scope: scope,
              root: const SelectedElement.cell(cellId: 'u_inv_10'),
            ),
          );
      expect((await _laidOut(container)).graph.cells, hasLength(3));
      container.read(coneViewProvider.notifier).exit();
      expect(await _laidOut(container), LaidOutGraph.empty);
      expect(service.calls, 1);
    });
  });

  group('a flat scope of 844,208 cells', () {
    // The size of the flat scope of a one-million-gate design. Opening it
    // must cost nothing: no schematic graph, no layout input, no layout.
    const cells = 844208;
    late NetlistModel model;
    setUpAll(() => model = _flatChain(cells));

    test('is held back at the default limit without laying out', () async {
      final tab = _tab(model, limit: kDefaultLayoutCellLimit);
      final container = tab.container;
      await container.read(appSettingsProvider.future);
      await container.read(loadedNetlistProvider.future);
      final clock = Stopwatch()..start();
      final gate = container.read(scopeLayoutGateProvider);
      final result = await _laidOut(container);
      clock.stop();
      expect(gate.cellCount, cells);
      expect(gate.deferred, isTrue);
      expect(result, LaidOutGraph.empty);
      expect(tab.service.calls, 0);
      // The decision reads one number; building the graph of this scope
      // takes seconds, so this bound has a wide margin on both sides.
      expect(clock.elapsed, lessThan(const Duration(seconds: 3)));
      // About 105 GiB: the figure the canvas shows beside "Lay out anyway".
      expect(gate.estimatedBytes, greaterThan(100 * 1024 * 1024 * 1024));
    });

    test('lays out a cone of it without laying out the scope', () async {
      final tab = _tab(model, limit: kDefaultLayoutCellLimit);
      final container = tab.container;
      await container.read(appSettingsProvider.future);
      await container.read(loadedNetlistProvider.future);
      final scope = container.read(hierarchyTreeProvider).selected!;
      container
          .read(coneViewProvider.notifier)
          .show(
            ConeViewRequest(
              scope: scope,
              root: const SelectedElement.cell(cellId: 'u400000'),
              depth: 3,
            ),
          );
      final result = await _laidOut(container);
      expect(result.graph.cells, hasLength(4));
      expect(result.cone?.scopeCellCount, cells);
      expect(tab.service.calls, 1);
      expect(tab.service.lastOnly?.cellIds, hasLength(4));
    });
  });

  // The same checks on a netlist written by tool/gen_gate_netlist.py (see
  // tool/bench_netlist_parse.dart), read the way File > Open Netlist JSON
  // reads it. Registered only when NETCRUX_BIG_NETLIST names the document,
  // since the files are hundreds of megabytes and are not in the repository.
  final bigPath = Platform.environment['NETCRUX_BIG_NETLIST'];
  if (bigPath != null) {
    group('the generated netlist $bigPath', () {
      test('opens its flat scope without laying it out', () async {
        final model = ChunkedYosysJsonReader.parseFile(bigPath);
        final tab = _tab(model, limit: kDefaultLayoutCellLimit);
        final container = tab.container;
        await container.read(appSettingsProvider.future);
        await container.read(loadedNetlistProvider.future);
        container.read(hierarchyTreeProvider.notifier).selectByPath(
          const <String>['u_core'],
        );
        final scope = container.read(hierarchyTreeProvider).selected!;
        expect(scope.path, const <String>['u_core']);
        final clock = Stopwatch()..start();
        final gate = container.read(scopeLayoutGateProvider);
        final result = await _laidOut(container);
        clock.stop();
        // The figures are the point of running against a real file.
        // ignore: avoid_print
        print(
          'flat scope: ${gate.cellCount} cells, held back: ${gate.deferred}, '
          'decided in ${clock.elapsedMilliseconds} ms, '
          'estimate ${gate.estimatedBytes >> 30} GiB',
        );
        expect(gate.deferred, isTrue);
        expect(result, LaidOutGraph.empty);
        expect(tab.service.calls, 0);
        expect(clock.elapsed, lessThan(const Duration(seconds: 3)));
      });
    });
  }
}
