// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Deterministic generator for the `design_seed` netlist fixture — the small
// HIERARCHICAL Yosys-shaped JSON the integration-test design-seed helper
// (`integration_test/helpers/app_driver.dart` → `seedDesignIntoNewTab`)
// injects through `YosysJsonParser`, bypassing Yosys entirely.
//
// The stress-ladder generator (`tool/generate_netlist_fixtures.dart`) emits
// only flat single-module designs; this one exists because the seeded-design
// journeys (hierarchy navigation, push-in/pop-out, selection + inspector)
// need real module nesting: `top` → `u_cpu` (module `cpu`) → `u_alu`
// (module `alu`), with primitive-cell siblings at each level that must NOT
// appear as hierarchy children.
//
// Emits, byte-identical on every run:
//   * test/fixtures/netlist/design_seed/generated/design_seed.v
//       — informational RTL equivalent (never parsed by tests)
//   * test/fixtures/netlist/design_seed/generated/design_seed.netlist.json
//       — the canonical Yosys-shaped JSON (golden-swept like every other
//         design under test/fixtures/netlist/)
//   * integration_test/fixtures/design_seed_netlist.dart
//       — the same JSON as a Dart const, because integration tests execute
//         inside the launched app process where the package root is not a
//         reliable working directory. A sync test
//         (test/fixtures/design_seed_fixture_sync_test.dart) pins the const
//         to the committed JSON so the two can never drift.
//
// Usage:
//   dart run tool/generate_design_seed_fixture.dart
//
// After changing the design, refresh the parser golden with:
//   REGENERATE=1 flutter test test/services/yosys/netlist_golden_test.dart

import 'dart:convert';
import 'dart:io';

Map<String, Object?> _port(String direction, List<int> bits) =>
    <String, Object?>{'direction': direction, 'bits': bits};

Map<String, Object?> _cell({
  required String type,
  Map<String, String> parameters = const {},
  required Map<String, String> portDirections,
  required Map<String, List<int>> connections,
}) => <String, Object?>{
  'hide_name': 0,
  'type': type,
  'parameters': parameters,
  'attributes': <String, String>{},
  'port_directions': portDirections,
  'connections': connections,
};

Map<String, Object?> _net(List<int> bits) => <String, Object?>{
  'hide_name': 0,
  'bits': bits,
  'attributes': <String, String>{},
};

/// The fixture document. Key order is committed-stable: modules in
/// top-down hierarchy order, members in declaration order.
Map<String, Object?> buildDesignSeedJson() => <String, Object?>{
  'creator': 'netcrux tool/generate_design_seed_fixture.dart',
  'modules': <String, Object?>{
    'top': <String, Object?>{
      'attributes': <String, String>{
        'top': '00000000000000000000000000000001',
        'src': 'design_seed.v:5',
      },
      'ports': <String, Object?>{
        'clk': _port('input', [2]),
        'rst': _port('input', [3]),
        'dout': _port('output', [5]),
      },
      'cells': <String, Object?>{
        // Submodule instance — a hierarchy child.
        'u_cpu': _cell(
          type: 'cpu',
          portDirections: {'CLK': 'input', 'RST': 'input', 'DOUT': 'output'},
          connections: {
            'CLK': [2],
            'RST': [3],
            'DOUT': [4],
          },
        ),
        // Primitive sibling — must NOT appear as a hierarchy child.
        'dma_reg': _cell(
          type: r'$dff',
          parameters: {'WIDTH': '1', 'CLK_POLARITY': '1'},
          portDirections: {'CLK': 'input', 'D': 'input', 'Q': 'output'},
          connections: {
            'CLK': [2],
            'D': [4],
            'Q': [5],
          },
        ),
      },
      'netnames': <String, Object?>{
        'clk': _net([2]),
        'rst': _net([3]),
        'cpu_dout': _net([4]),
        'dout': _net([5]),
      },
    },
    'cpu': <String, Object?>{
      'attributes': <String, String>{'src': 'design_seed.v:20'},
      'ports': <String, Object?>{
        'CLK': _port('input', [2]),
        'RST': _port('input', [3]),
        'DOUT': _port('output', [6]),
      },
      'cells': <String, Object?>{
        'u_alu': _cell(
          type: 'alu',
          portDirections: {'A': 'input', 'B': 'input', 'Y': 'output'},
          connections: {
            'A': [5],
            'B': [5],
            'Y': [6],
          },
        ),
        'pc_reg': _cell(
          type: r'$dff',
          parameters: {'WIDTH': '1', 'CLK_POLARITY': '1'},
          portDirections: {'CLK': 'input', 'D': 'input', 'Q': 'output'},
          connections: {
            'CLK': [2],
            'D': [6],
            'Q': [5],
          },
        ),
      },
      'netnames': <String, Object?>{
        'pc_q': _net([5]),
        'alu_y': _net([6]),
      },
    },
    'alu': <String, Object?>{
      'attributes': <String, String>{'src': 'design_seed.v:35'},
      'ports': <String, Object?>{
        'A': _port('input', [2]),
        'B': _port('input', [3]),
        'Y': _port('output', [4]),
      },
      'cells': <String, Object?>{
        'xor0': _cell(
          type: r'$xor',
          parameters: {'A_WIDTH': '1', 'B_WIDTH': '1', 'Y_WIDTH': '1'},
          portDirections: {'A': 'input', 'B': 'input', 'Y': 'output'},
          connections: {
            'A': [2],
            'B': [3],
            'Y': [4],
          },
        ),
      },
      'netnames': <String, Object?>{
        'y': _net([4]),
      },
    },
  },
};

const String _informationalVerilog = '''
// Informational RTL equivalent of design_seed.netlist.json — never parsed
// by tests. Regenerate everything with:
//   dart run tool/generate_design_seed_fixture.dart

module top(input clk, input rst, output dout);
  wire cpu_dout;
  cpu u_cpu(.CLK(clk), .RST(rst), .DOUT(cpu_dout));
  reg dma_reg_q;
  always @(posedge clk) dma_reg_q <= cpu_dout;
  assign dout = dma_reg_q;
endmodule

module cpu(input CLK, input RST, output DOUT);
  wire pc_q, alu_y;
  alu u_alu(.A(pc_q), .B(pc_q), .Y(alu_y));
  reg pc_reg_q;
  always @(posedge CLK) pc_reg_q <= alu_y;
  assign DOUT = alu_y;
endmodule

module alu(input A, input B, output Y);
  assign Y = A ^ B;
endmodule
''';

void _writeIfChanged(File file, String content) {
  file.parent.createSync(recursive: true);
  if (file.existsSync() && file.readAsStringSync() == content) {
    stdout.writeln('  unchanged ${file.path}');
    return;
  }
  file.writeAsStringSync(content);
  stdout.writeln('  wrote     ${file.path}');
}

void main() {
  final json =
      '${const JsonEncoder.withIndent('  ').convert(buildDesignSeedJson())}\n';

  const generatedDir = 'test/fixtures/netlist/design_seed/generated';
  _writeIfChanged(File('$generatedDir/design_seed.v'), _informationalVerilog);
  _writeIfChanged(File('$generatedDir/design_seed.netlist.json'), json);

  final dartConst =
      '''
// GENERATED by tool/generate_design_seed_fixture.dart — do not edit.
//
// Mirror of test/fixtures/netlist/design_seed/generated/design_seed.netlist.json
// as a Dart const, importable from integration tests (which run inside the
// launched app process, where the package root is not a reliable working
// directory). test/fixtures/design_seed_fixture_sync_test.dart pins this
// const to the committed JSON file.

/// Yosys-shaped netlist JSON for the hierarchical `design_seed` fixture:
/// `top` → `u_cpu` (module `cpu`) → `u_alu` (module `alu`), with primitive
/// siblings (`dma_reg`, `pc_reg`, `xor0`) that are not hierarchy children.
const String designSeedNetlistJson = r\'\'\'
$json\'\'\';
''';
  _writeIfChanged(
    File('integration_test/fixtures/design_seed_netlist.dart'),
    dartConst,
  );
}
