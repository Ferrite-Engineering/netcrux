// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/custom_cell_symbol/cell_symbol_geometry.dart';
import 'package:netcrux/domain/models/custom_cell_symbol/port_anchor.dart';
import 'package:netcrux/domain/models/layout/bounding_box.dart';
import 'package:netcrux/domain/models/layout/edge_route.dart';
import 'package:netcrux/domain/models/layout/netlist_layout.dart';
import 'package:netcrux/domain/models/layout/node_position.dart';
import 'package:netcrux/domain/models/netlist/hierarchy_node.dart';
import 'package:netcrux/domain/models/netlist/module.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/schematic/laid_out_graph.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/project/providers/current_laid_out_graph_provider.dart';
import 'package:netcrux/features/project/providers/loaded_netlist_provider.dart';
import 'package:netcrux/services/custom_cell_symbols/cell_symbol_geometry_provider.dart';
import 'package:netcrux/services/layout/elk_layout_service.dart';
import 'package:netcrux/services/layout/elk_layout_service_provider.dart';

/// Scripted [ElkJsHost] that pretends elkjs ran successfully and
/// emits a deterministic row-of-boxes layout for whatever input the
/// service stashed. Mirrors the pipeline integration tests so
/// the laid-out-graph pipeline can be exercised without QuickJS.
class _DeterministicHost implements ElkJsHost {
  Map<String, Object?>? _lastInput;

  @override
  String evaluate(String code) {
    if (code.contains('__elkInstance')) return '';
    if (code.contains('"pending"')) return 'done';
    if (code.contains('__elk_error')) return '';
    if (code.contains('__elk_input = ')) {
      final eq = code.indexOf('= ');
      if (eq != -1) {
        final tail = code.substring(eq + 2).trimRight();
        final json = tail.replaceAll(RegExp(r';\s*$'), '');
        try {
          final decoded = jsonDecode(json);
          if (decoded is Map<String, Object?>) _lastInput = decoded;
        } on FormatException {
          _lastInput = null;
        }
      }
      return '';
    }
    if (code.contains('__elk_result')) {
      final input = _lastInput;
      if (input == null) return '';
      final children =
          (input['children'] as List<Object?>?) ?? const <Object?>[];
      final nodes = <Map<String, Object?>>[
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
        'children': nodes,
        'edges': <Map<String, Object?>>[],
      });
    }
    return '';
  }

  @override
  int executePendingJob() => 0;

  @override
  void dispose() {}
}

NetlistModel _loadFixture(String name) {
  final raw = File(
    'test/fixtures/verilog/$name.expected.json',
  ).readAsStringSync();
  return NetlistModel.fromJson(jsonDecode(raw) as Map<String, Object?>);
}

/// Tracks the static netlist injected through [_container]. Used by
/// [_StubLoadedNetlist] inside the override because Riverpod's
/// override-with constructs the notifier without arguments.
NetlistModel? _injectedNetlist;

ProviderContainer _container({NetlistModel? netlist}) {
  _injectedNetlist = netlist;
  return ProviderContainer(
    overrides: <Override>[
      elkLayoutServiceProvider.overrideWith(
        (ref) {
          final service = ElkLayoutService(
            hostFactory: _DeterministicHost.new,
            assetLoader: (_) async => '// deterministic test host',
          );
          ref.onDispose(service.dispose);
          return service;
        },
      ),
      // Replace LoadedNetlist with a stub that yields the supplied
      // model from build() directly. Without this, the default
      // notifier's async path would resolve to null and overwrite
      // any setModel() the test made synchronously.
      loadedNetlistProvider.overrideWith(_StubLoadedNetlist.new),
    ],
  );
}

/// Lays every node out in a row and remembers the symbols it was given.
class _RecordingLayoutService extends ElkLayoutService {
  CellSymbolGeometries lastSymbols = CellSymbolGeometries.none;

  @override
  Future<NetlistLayout> layout(
    Module module, {
    CellSymbolGeometries symbols = CellSymbolGeometries.none,
  }) async {
    lastSymbols = symbols;
    return NetlistLayout(
      nodes: <NodePosition>[
        for (final (i, name) in module.cells.keys.indexed)
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

class _StubLoadedNetlist extends LoadedNetlist {
  @override
  Future<NetlistModel?> build() async => _injectedNetlist;
}

class _ThrowingLoadedNetlist extends LoadedNetlist {
  @override
  Future<NetlistModel?> build() async {
    throw const LoadedNetlistException(
      'Yosys is not available: not found on PATH',
    );
  }
}

void main() {
  group('currentLaidOutGraphProvider', () {
    test('returns LaidOutGraph.empty when no model is loaded', () async {
      final container = _container();
      addTearDown(container.dispose);
      // Keep the auto-dispose provider alive while we await its
      // future — without an active listener the provider would
      // dispose mid-build and emit "disposed during loading state".
      final sub = container.listen<AsyncValue<LaidOutGraph>>(
        currentLaidOutGraphProvider,
        (previous, next) {},
      );
      addTearDown(sub.close);
      final result = await container.read(currentLaidOutGraphProvider.future);
      expect(result, LaidOutGraph.empty);
    });

    test('returns LaidOutGraph.empty when a model is loaded but no scope '
        'is selected', () async {
      final model = _loadFixture('and2');
      final container = _container(netlist: model);
      addTearDown(container.dispose);
      // Don't promote a selection — leave HierarchyTreeNotifier in
      // its initial empty state.
      // Keep the auto-dispose provider alive while we await its
      // future — without an active listener the provider would
      // dispose mid-build and emit "disposed during loading state".
      final sub = container.listen<AsyncValue<LaidOutGraph>>(
        currentLaidOutGraphProvider,
        (previous, next) {},
      );
      addTearDown(sub.close);
      final result = await container.read(currentLaidOutGraphProvider.future);
      expect(result, LaidOutGraph.empty);
    });

    test('builds + lays out the top scope of the and2 fixture', () async {
      final model = _loadFixture('and2');
      final container = _container(netlist: model);
      addTearDown(container.dispose);
      final tree = container.read(hierarchyTreeProvider.notifier)
        ..setModel(model);
      expect(tree, isNotNull);
      // Keep the auto-dispose provider alive while we await its
      // future — without an active listener the provider would
      // dispose mid-build and emit "disposed during loading state".
      final sub = container.listen<AsyncValue<LaidOutGraph>>(
        currentLaidOutGraphProvider,
        (previous, next) {},
      );
      addTearDown(sub.close);
      final result = await container.read(currentLaidOutGraphProvider.future);
      expect(result.isEmpty, isFalse);
      expect(result.graph.moduleName, 'and2');
      expect(result.graph.cells, hasLength(1));
      // The deterministic host places one node per (cell + boundary
      // port) — one cell + three boundary ports.
      expect(result.layout.nodes, hasLength(4));
    });

    test('lays a symbol-bearing cell out in its symbol and lists the pins '
        'its anchors name', () async {
      final model = _loadFixture('and2');
      final cell = model.topModule!.cells.values.single;
      final container = ProviderContainer(
        overrides: <Override>[
          elkLayoutServiceProvider.overrideWith((ref) {
            final service = _RecordingLayoutService();
            ref.onDispose(service.dispose);
            return service;
          }),
          loadedNetlistProvider.overrideWith(_StubLoadedNetlist.new),
          cellSymbolGeometriesProvider.overrideWithValue(
            CellSymbolGeometries(<String, CellSymbolGeometry>{
              cell.type: const CellSymbolGeometry(
                aspect: 2,
                anchors: <String, PortAnchor>{
                  'A': PortAnchor(x: 0, y: 0.5, side: PortAnchorSide.left),
                  // Names no pin of the cell: no label, no guess.
                  'Z': PortAnchor(x: 1, y: 0.5, side: PortAnchorSide.right),
                },
              ),
            }),
          ),
        ],
      );
      _injectedNetlist = model;
      addTearDown(container.dispose);
      container.read(hierarchyTreeProvider.notifier).setModel(model);
      final sub = container.listen<AsyncValue<LaidOutGraph>>(
        currentLaidOutGraphProvider,
        (previous, next) {},
      );
      addTearDown(sub.close);
      final result = await container.read(currentLaidOutGraphProvider.future);
      expect(result.symbolCells, <String, Set<String>>{
        cell.name: <String>{'A'},
      });
      final service =
          container.read(elkLayoutServiceProvider) as _RecordingLayoutService;
      expect(service.lastSymbols[cell.type]?.aspect, 2);
    });

    test('propagates LoadedNetlistException so the schematic surfaces '
        'the elaboration error instead of an empty graph', () async {
      // Override loadedNetlistProvider with a stub that throws the
      // same exception the real pipeline emits when yosys is missing.
      // Without the rethrow, currentLaidOutGraphProvider would
      // silently return LaidOutGraph.empty and the canvas would
      // paint blank.
      final container = ProviderContainer(
        overrides: <Override>[
          elkLayoutServiceProvider.overrideWith(
            (ref) {
              final service = ElkLayoutService(
                hostFactory: _DeterministicHost.new,
                assetLoader: (_) async => '// deterministic test host',
              );
              ref.onDispose(service.dispose);
              return service;
            },
          ),
          loadedNetlistProvider.overrideWith(_ThrowingLoadedNetlist.new),
        ],
      );
      addTearDown(container.dispose);
      // Listen to both providers so they stay alive long enough for
      // the rebuild cascade to settle.
      final loadedSub = container.listen<AsyncValue<NetlistModel?>>(
        loadedNetlistProvider,
        (previous, next) {},
      );
      addTearDown(loadedSub.close);
      final sub = container.listen<AsyncValue<LaidOutGraph>>(
        currentLaidOutGraphProvider,
        (previous, next) {},
      );
      addTearDown(sub.close);
      // Pump the event loop until both providers have settled. The
      // throwing build() resolves on the next microtask; the laid-out
      // graph rebuild follows synchronously thereafter.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      final asyncValue = container.read(currentLaidOutGraphProvider);
      expect(asyncValue.hasError, isTrue);
      expect(
        asyncValue.error,
        isA<LoadedNetlistException>().having(
          (e) => e.message,
          'message',
          contains('Yosys'),
        ),
      );
    });

    test('returns empty when the selected scope cannot resolve', () async {
      final model = _loadFixture('and2');
      final container = _container(netlist: model);
      addTearDown(container.dispose);
      // Force-select a node that doesn't resolve in this model.
      final notifier = container.read(hierarchyTreeProvider.notifier)
        ..setModel(model)
        ..selectScope(
          const HierarchyNode(path: <String>[], moduleName: 'gone'),
        );
      expect(notifier, isNotNull);
      // Keep the auto-dispose provider alive while we await its
      // future — without an active listener the provider would
      // dispose mid-build and emit "disposed during loading state".
      final sub = container.listen<AsyncValue<LaidOutGraph>>(
        currentLaidOutGraphProvider,
        (previous, next) {},
      );
      addTearDown(sub.close);
      final result = await container.read(currentLaidOutGraphProvider.future);
      expect(result, LaidOutGraph.empty);
    });
  });
}
