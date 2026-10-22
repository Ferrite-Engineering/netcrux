// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The partial layout a cone view asks for: the ELK input of part of a scope
// and the caches it does and does not touch.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/netlist/module.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/schematic/schematic_graph.dart';
import 'package:netcrux/services/layout/elk_layout_service.dart';
import 'package:netcrux/services/schematic/net_edge_enumeration.dart';
import 'package:netcrux/services/yosys/streaming_yosys_json_reader.dart';

NetlistModel _fixture(String name) => NetlistModel.fromJson(
  jsonDecode(
        File('test/fixtures/verilog/$name.expected.json').readAsStringSync(),
      )
      as Map<String, Object?>,
);

Module _capturedModule(String fixture, String module) {
  final bytes = File('test/fixtures/netlist/$fixture').readAsBytesSync();
  return const StreamingYosysJsonReader()
      .parse(utf8.decode(gzip.decode(bytes)))
      .modules[module]!;
}

ElkSubgraph _everything(Module module) => ElkSubgraph(
  cellIds: module.cells.keys.toSet(),
  boundaryPortIds: <String>{for (final p in module.ports.keys) 'port:$p'},
  edgeIds: <String>{
    for (final group in enumerateNetEdges(module))
      for (final edge in group.edges) edge.id,
  },
);

List<String> _ids(Map<String, Object?> input, String key) => <String>[
  for (final item
      in (input[key]! as List<Object?>).cast<Map<String, Object?>>())
    item['id']! as String,
];

/// Lays every node out in a row and counts its solves.
class _CountingSolver implements ElkSolver {
  int solves = 0;

  @override
  String get engineDescription => 'counting';

  @override
  String solve(String inputJson) {
    solves++;
    final input = jsonDecode(inputJson) as Map<String, Object?>;
    final children = (input['children']! as List<Object?>)
        .cast<Map<String, Object?>>();
    return jsonEncode(<String, Object?>{
      'id': 'root',
      'x': 0,
      'y': 0,
      'width': 100.0 * children.length,
      'height': 40,
      'children': <Map<String, Object?>>[
        for (final (i, c) in children.indexed)
          <String, Object?>{
            'id': c['id'],
            'x': 100.0 * i,
            'y': 0,
            'width': 80,
            'height': 40,
          },
      ],
      'edges': <Object?>[],
    });
  }

  @override
  void dispose() {}
}

class _RecordingDiskCache implements LayoutDiskCache {
  final Map<String, String> entries = <String, String>{};
  int reads = 0;

  @override
  Future<String?> read(String key) async {
    reads++;
    return entries[key];
  }

  @override
  Future<void> write(String key, String value) async => entries[key] = value;
}

void main() {
  group('buildElkInput with a sub-graph', () {
    test('naming every element is the whole scope, byte for byte', () {
      final module = _fixture('adder4').topModule!;
      expect(
        jsonEncode(buildElkInput(module, only: _everything(module))),
        jsonEncode(buildElkInput(module)),
      );
    });

    test('keeps only what it names, under the scope ids', () {
      final module = _fixture('large_chain').topModule!;
      final whole = buildElkInput(module);
      final edges = enumerateNetEdges(module);
      // The wire u_inv_9:Y -> u_inv_10:A, found in the scope's own edges.
      final link = edges
          .expand((g) => g.edges)
          .firstWhere((e) => e.targetPortId == 'u_inv_10:A');
      final part = buildElkInput(
        module,
        only: ElkSubgraph(
          cellIds: const <String>{'u_inv_9', 'u_inv_10'},
          boundaryPortIds: const <String>{},
          edgeIds: <String>{link.id},
        ),
      );
      expect(_ids(part, 'children'), <String>['u_inv_9', 'u_inv_10']);
      expect(_ids(part, 'edges'), <String>[link.id]);
      expect(_ids(whole, 'edges'), contains(link.id));
      // The kept cells are built exactly as in the whole scope.
      final wholeNode = (whole['children']! as List<Object?>)
          .cast<Map<String, Object?>>()
          .firstWhere((c) => c['id'] == 'u_inv_9');
      final partNode = (part['children']! as List<Object?>)
          .cast<Map<String, Object?>>()
          .first;
      expect(jsonEncode(partNode), jsonEncode(wholeNode));
    });

    test('a net too wide for the scope stays unrouted in the part', () {
      // picorv32's clock reaches every register: far past the routing cap.
      final module = _capturedModule(
        'picorv32/captured/picorv32.netlist.json.gz',
        'picorv32',
      );
      final wide = enumerateNetEdges(
        module,
      ).firstWhere((g) => g.edges.length > highFanoutEdgeCap);
      final few = wide.edges.take(3).toList();
      final part = buildElkInput(
        module,
        only: ElkSubgraph(
          cellIds: <String>{
            for (final e in few) ...<String>[
              ?cellIdOfPinId(e.sourcePortId),
              ?cellIdOfPinId(e.targetPortId),
            ],
          },
          boundaryPortIds: <String>{
            for (final e in few)
              if (e.sourcePortId.startsWith('port:')) e.sourcePortId,
          },
          edgeIds: <String>{for (final e in few) e.id},
        ),
      );
      expect(_ids(part, 'edges'), isEmpty);
    });

    test('a small part of a large scope keeps the small-scope options', () {
      final module = _capturedModule(
        'picorv32/captured/picorv32.netlist.json.gz',
        'picorv32',
      );
      final whole = buildElkInput(module)['layoutOptions']! as Map;
      expect(whole['elk.layered.thoroughness'], '1');
      final part =
          buildElkInput(
                module,
                only: ElkSubgraph(
                  cellIds: module.cells.keys.take(10).toSet(),
                  boundaryPortIds: const <String>{},
                  edgeIds: const <String>{},
                ),
              )['layoutOptions']!
              as Map;
      expect(part.containsKey('elk.layered.thoroughness'), isFalse);
    });
  });

  group('ElkLayoutService with a sub-graph', () {
    late Module module;
    late _CountingSolver solver;
    late _RecordingDiskCache disk;
    late ElkLayoutService service;

    ElkSubgraph cone(int i) => ElkSubgraph(
      cellIds: <String>{'u_inv_$i'},
      boundaryPortIds: const <String>{},
      edgeIds: const <String>{},
    );

    setUp(() {
      module = _fixture('large_chain').topModule!;
      solver = _CountingSolver();
      disk = _RecordingDiskCache();
      service = ElkLayoutService(
        solverFactory: () => solver,
        diskCache: disk,
        maxConeCacheEntries: 2,
      );
      addTearDown(service.dispose);
    });

    test('lays out only the part and never touches the disk', () async {
      final layout = await service.layout(module, only: cone(3));
      expect(layout.nodes.map((n) => n.id), <String>['u_inv_3']);
      await Future<void>.delayed(Duration.zero);
      expect(disk.entries, isEmpty);
      expect(disk.reads, 0);
      expect(service.memCacheLength, 0);
      expect(service.coneCacheLength, 1);
    });

    test('a repeated cone is served from its own cache', () async {
      await service.layout(module, only: cone(3));
      await service.layout(module, only: cone(3));
      expect(solver.solves, 1);
    });

    test('cones never push the whole scope out of either cache', () async {
      await service.layout(module);
      await Future<void>.delayed(Duration.zero);
      expect(disk.entries, hasLength(1));
      for (var i = 0; i < 10; i++) {
        await service.layout(module, only: cone(i));
      }
      expect(service.coneCacheLength, 2);
      expect(service.memCacheLength, 1);
      expect(disk.entries, hasLength(1));
      final before = solver.solves;
      await service.layout(module);
      expect(solver.solves, before, reason: 'the whole scope is still cached');
    });
  });
}
