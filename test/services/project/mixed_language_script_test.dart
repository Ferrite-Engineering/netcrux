// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_yosys/crux_yosys.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/project/netcrux_project.dart';
import 'package:netcrux/features/project/providers/loaded_netlist_provider.dart';

/// Pure-Dart assertion that the mixed Verilog + VHDL fixture under
/// `test/fixtures/mixed/` produces the right VHDL-lowering command and
/// Yosys read shape. VHDL is lowered to Verilog by a standalone
/// `ghdl --synth` step, so the Yosys script itself only reads Verilog and
/// loads no GHDL plugin. Real Yosys/ghdl aren't invoked — this runs on
/// every CI host.
void main() {
  group('Mixed Verilog + VHDL script generation', () {
    test('lowers VHDL with ghdl --synth; Yosys reads Verilog, no plugin', () {
      final project = NetcruxProject.create(
        sourceFiles: const <String>[
          'test/fixtures/mixed/top.v',
          'test/fixtures/mixed/sub.vhd',
        ],
        topModule: 'top',
      );
      final request = LoadedNetlist.buildRequest(project);

      // The standalone ghdl --synth command lowers only the VHDL source,
      // elaborating the Yosys-side top by default.
      final ghdlArgs = YosysRunner.buildGhdlSynthArguments(request);
      expect(
        ghdlArgs,
        containsAllInOrder(<String>[
          '--synth',
          '--out=verilog',
          'test/fixtures/mixed/sub.vhd',
          '-e',
          'top',
        ]),
      );

      // The Yosys script reads the original Verilog source, loads no GHDL
      // plugin, and drives the Yosys-side top via hierarchy.
      final script = YosysRunner.buildScript(
        request,
        jsonOutputPath: '/tmp/out.json',
      );
      expect(script, contains('read_verilog'));
      expect(script, contains('"test/fixtures/mixed/top.v"'));
      expect(script, isNot(contains('plugin -i ghdl')));
      expect(script, isNot(contains('read_vhdl')));
      expect(script, contains('hierarchy -check -top top'));
    });

    test('pure-VHDL project lowers via ghdl --synth over the VHDL file', () {
      final project = NetcruxProject.create(
        sourceFiles: const <String>['test/fixtures/vhdl/and2.vhd'],
        topModule: 'and2',
      );
      final request = LoadedNetlist.buildRequest(project);
      final ghdlArgs = YosysRunner.buildGhdlSynthArguments(request);
      expect(
        ghdlArgs,
        containsAllInOrder(<String>[
          '--synth',
          '--out=verilog',
          'test/fixtures/vhdl/and2.vhd',
          '-e',
          'and2',
        ]),
      );
      // No original Verilog sources → the raw script has no read command.
      final script = YosysRunner.buildScript(
        request,
        jsonOutputPath: '/tmp/out.json',
      );
      expect(script, isNot(contains('read_verilog')));
      expect(script, isNot(contains('plugin -i ghdl')));
    });
  });
}
