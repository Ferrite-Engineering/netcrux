// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_yosys/crux_yosys.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/services/yosys/yosys_json_parser.dart';

/// One VHDL fixture: a VHDL file + the elaboration top unit + the
/// port names the parsed model should expose. The cell shape is
/// intentionally NOT asserted — Yosys+GHDL chooses how to lower a
/// behavioural VHDL block into its own cell library, and different
/// builds of the plugin can produce structurally equivalent but
/// non-identical netlists. Tests assert on the user-visible shape.
class _Fixture {
  const _Fixture({
    required this.label,
    required this.vhdlPath,
    required this.topUnit,
    required this.expectedPortNames,
  });

  final String label;
  final String vhdlPath;
  final String topUnit;
  final List<String> expectedPortNames;
}

const _fixturesRoot = 'test/fixtures/vhdl';

final _fixtures = <_Fixture>[
  const _Fixture(
    label: 'and2 (VHDL)',
    vhdlPath: '$_fixturesRoot/and2.vhd',
    topUnit: 'and2',
    expectedPortNames: <String>['a', 'b', 'y'],
  ),
  const _Fixture(
    label: 'adder4 (VHDL)',
    vhdlPath: '$_fixturesRoot/adder4.vhd',
    topUnit: 'adder4',
    expectedPortNames: <String>['a', 'b', 'sum'],
  ),
  const _Fixture(
    label: 'fsm (VHDL)',
    vhdlPath: '$_fixturesRoot/fsm.vhd',
    topUnit: 'fsm',
    expectedPortNames: <String>['clk', 'rst_n', 'go', 'busy'],
  ),
];

void main() {
  group('VHDL pipeline (VHDL → yosys+ghdl → parse)', () {
    late bool yosysAvailable;
    late bool ghdlAvailable;

    setUpAll(() async {
      // Yosys must be on PATH.
      final yosysProbe = await YosysAvailabilityService(
        runner: const DefaultProcessRunner(),
      ).probe();
      yosysAvailable = yosysProbe.isAvailable;
      if (!yosysAvailable) {
        ghdlAvailable = false;
        return;
      }
      // VHDL is lowered by a standalone `ghdl --synth --out=verilog` run
      // before Yosys reads the result, so `ghdl` on PATH is the whole
      // requirement. Skipping here keeps CI output clean on hosts without
      // GHDL.
      final ghdlProbe = await Process.run(
        Platform.isWindows ? 'where' : 'which',
        <String>['ghdl'],
      );
      ghdlAvailable = ghdlProbe.exitCode == 0;
    });

    for (final fixture in _fixtures) {
      test('${fixture.label}: real yosys+ghdl end-to-end', () async {
        if (!yosysAvailable) {
          markTestSkipped(
            'yosys not on PATH on this host — install yosys to exercise '
            'the VHDL elaboration pipeline',
          );
          return;
        }
        if (!ghdlAvailable) {
          markTestSkipped(
            'ghdl not on PATH on this host — install GHDL to exercise the '
            'VHDL elaboration pipeline',
          );
          return;
        }
        final runner = YosysRunner();
        final result = await runner.run(
          YosysRunRequest(
            sources: <YosysSourceFile>[YosysSourceFile.vhdl(fixture.vhdlPath)],
            topModule: fixture.topUnit,
            vhdlTopUnit: fixture.topUnit,
          ),
        );
        expect(
          result,
          isA<YosysRunSuccess>(),
          reason: result is YosysRunFailure
              ? 'yosys+ghdl exited ${result.exitCode}: ${result.stderr}'
              : null,
        );
        final model = const YosysJsonParser().parse(
          (result as YosysRunSuccess).rawJson,
        );
        expect(model.modules.keys, contains(fixture.topUnit));
        final module = model.modules[fixture.topUnit]!;
        expect(module.ports.keys, containsAll(fixture.expectedPortNames));
      });
    }
  });
}
