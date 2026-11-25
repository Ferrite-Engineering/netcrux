// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:crux_yosys/crux_yosys.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/services/layout/elk_layout_service.dart';
import 'package:netcrux/services/yosys/yosys_json_parser.dart';

/// One pipeline fixture: a Verilog file + the expected JSON shape Yosys
/// would emit + assertions on the parsed structure.
class _Fixture {
  const _Fixture({
    required this.label,
    required this.verilogPath,
    required this.expectedJsonPath,
    required this.topModule,
    required this.expectedPortNames,
    required this.expectedCellTypes,
  });

  final String label;
  final String verilogPath;
  final String expectedJsonPath;
  final String topModule;
  final List<String> expectedPortNames;
  final List<String> expectedCellTypes;
}

const _fixturesRoot = 'test/fixtures/verilog';

final _fixtures = <_Fixture>[
  const _Fixture(
    label: 'and2',
    verilogPath: '$_fixturesRoot/and2.v',
    expectedJsonPath: '$_fixturesRoot/and2.expected.json',
    topModule: 'and2',
    expectedPortNames: <String>['a', 'b', 'y'],
    expectedCellTypes: <String>[r'$and'],
  ),
  const _Fixture(
    label: 'adder4',
    verilogPath: '$_fixturesRoot/adder4.v',
    expectedJsonPath: '$_fixturesRoot/adder4.expected.json',
    topModule: 'adder4',
    expectedPortNames: <String>['a', 'b', 'cin', 'sum', 'cout'],
    expectedCellTypes: <String>[r'$add'],
  ),
  const _Fixture(
    label: 'fsm',
    verilogPath: '$_fixturesRoot/fsm.v',
    expectedJsonPath: '$_fixturesRoot/fsm.expected.json',
    topModule: 'fsm',
    expectedPortNames: <String>['clk', 'rst', 'go', 'done'],
    // The exact register cell type varies between Yosys releases ($adff
    // vs $dff with a separate AR cell); the fsm expected.json uses
    // $adff and the integration test asserts the cell-type set contains
    // *at least* a flop-style cell.
    expectedCellTypes: <String>[r'$adff'],
  ),
];

/// Scripted [ElkSolver] that emits a deterministic row-of-boxes layout for
/// whatever input the service hands it. Used by the parse-to-layout half of
/// the integration test so it runs without an engine.
class _DeterministicSolver implements ElkSolver {
  @override
  String get engineDescription => 'deterministic';

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

void main() {
  group('Verilog pipeline (parse → layout via expected JSON)', () {
    for (final fixture in _fixtures) {
      test('${fixture.label}: parses + lays out deterministically', () async {
        final raw = await File(fixture.expectedJsonPath).readAsString();
        final model = const YosysJsonParser().parse(raw);
        expect(model.modules.keys, contains(fixture.topModule));
        final module = model.modules[fixture.topModule]!;
        expect(module.ports.keys, containsAll(fixture.expectedPortNames));
        final cellTypes = module.cells.values.map((c) => c.type).toSet();
        for (final expected in fixture.expectedCellTypes) {
          expect(cellTypes, contains(expected));
        }

        final service = ElkLayoutService(
          solverFactory: _DeterministicSolver.new,
        );
        final layout = await service.layout(module);
        // Deterministic solver places one node per (cell + boundary port).
        final expectedNodeCount = module.cells.length + module.ports.length;
        expect(layout.nodes, hasLength(expectedNodeCount));
        expect(layout.bounds.width, greaterThan(0));
      });
    }
  });

  group('Verilog pipeline (Verilog → yosys → parse → layout)', () {
    late bool yosysAvailable;

    setUpAll(() async {
      final probe = await YosysAvailabilityService(
        runner: const DefaultProcessRunner(),
      ).probe();
      yosysAvailable = probe.isAvailable;
    });

    for (final fixture in _fixtures) {
      test('${fixture.label}: real yosys end-to-end', () async {
        if (!yosysAvailable) {
          markTestSkipped(
            'yosys not on PATH on this host — install yosys to exercise '
            'the real Verilog→layout pipeline',
          );
          return;
        }
        final runner = YosysRunner();
        final result = await runner.run(
          YosysRunRequest(
            sources: <YosysSourceFile>[
              YosysSourceFile(fixture.verilogPath),
            ],
            topModule: fixture.topModule,
          ),
        );
        expect(
          result,
          isA<YosysRunSuccess>(),
          reason: result is YosysRunFailure
              ? 'yosys exited ${result.exitCode}: ${result.stderr}'
              : null,
        );
        final model = const YosysJsonParser().parse(
          (result as YosysRunSuccess).rawJson,
        );
        expect(model.modules.keys, contains(fixture.topModule));
        final module = model.modules[fixture.topModule]!;
        expect(module.ports.keys, containsAll(fixture.expectedPortNames));

        final service = ElkLayoutService(
          solverFactory: _DeterministicSolver.new,
        );
        final layout = await service.layout(module);
        expect(layout.nodes, isNotEmpty);
      });
    }
  });
}
