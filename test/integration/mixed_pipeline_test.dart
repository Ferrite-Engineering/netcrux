// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_yosys/crux_yosys.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/services/yosys/yosys_json_parser.dart';

/// Real-yosys+ghdl integration test for the mixed Verilog + VHDL
/// fixture under `test/fixtures/mixed/`. Skipped on hosts without
/// `yosys` or `ghdl`.
void main() {
  group('Mixed-language pipeline (Verilog + VHDL → yosys+ghdl)', () {
    late bool yosysAvailable;
    late bool ghdlAvailable;

    setUpAll(() async {
      final yosysProbe = await YosysAvailabilityService(
        runner: const DefaultProcessRunner(),
      ).probe();
      yosysAvailable = yosysProbe.isAvailable;
      if (!yosysAvailable) {
        ghdlAvailable = false;
        return;
      }
      final ghdlProbe = await Process.run(
        Platform.isWindows ? 'where' : 'which',
        <String>['ghdl'],
      );
      ghdlAvailable = ghdlProbe.exitCode == 0;
    });

    test(
      'Verilog top instantiates VHDL submodule end-to-end',
      () async {
        if (!yosysAvailable) {
          markTestSkipped(
            'yosys not on PATH on this host — install yosys to exercise '
            'the mixed-language pipeline',
          );
          return;
        }
        if (!ghdlAvailable) {
          markTestSkipped(
            'ghdl not on PATH on this host — install GHDL to exercise the '
            'mixed-language pipeline',
          );
          return;
        }
        final runner = YosysRunner();
        final result = await runner.run(
          const YosysRunRequest(
            sources: <YosysSourceFile>[
              YosysSourceFile('test/fixtures/mixed/top.v'),
              YosysSourceFile.vhdl('test/fixtures/mixed/sub.vhd'),
            ],
            topModule: 'top',
            // GHDL's elaborate target is the VHDL entity (sub), not the
            // Yosys-side hierarchy top (top).
            vhdlTopUnit: 'sub',
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
        // Both the Verilog top and the VHDL submodule appear as
        // distinct modules.
        expect(model.modules.keys, contains('top'));
        expect(
          model.modules.keys,
          contains('sub'),
          reason: 'VHDL submodule should be present in the netlist',
        );
        final top = model.modules['top']!;
        expect(top.ports.keys, containsAll(<String>['din', 'dout']));
      },
    );
  });
}
