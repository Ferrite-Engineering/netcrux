// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Generates `test/fixtures/verilog/large_chain.expected.json` — a
// 32-cell chain of inverters used by the round-trip property test
// scaffolding (`test/property/netlist_round_trip_test.dart`).
//
// The fixture is deliberately hand-crafted Yosys-shaped JSON rather
// than the output of a real yosys run so the property tests work in
// any environment.  Re-run this script when the schema evolves:
//
//     dart run tool/generate_large_chain_fixture.dart
//
// The committed JSON is the authoritative input to the test; the
// generator exists so reviewers can see how the fixture was produced
// and so future expansions stay deterministic.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

void main() {
  const chainLength = 32;
  final cells = <String, Object?>{};
  final netnames = <String, Object?>{};
  // Bit ids: 2 = primary input, 3..(2+chainLength) are the chain
  // intermediate nets; the last (2+chainLength) is the primary output.
  // Internal nets get names `n0`, `n1`, … for readability.
  for (var i = 0; i < chainLength; i++) {
    final inBit = 2 + i;
    final outBit = 3 + i;
    cells['u_inv_$i'] = <String, Object?>{
      'hide_name': 0,
      'type': r'$not',
      'parameters': <String, Object?>{
        'A_WIDTH': '1',
        'A_SIGNED': '0',
        'Y_WIDTH': '1',
      },
      'attributes': <String, Object?>{},
      'port_directions': <String, Object?>{
        'A': 'input',
        'Y': 'output',
      },
      'connections': <String, Object?>{
        'A': <Object?>[inBit],
        'Y': <Object?>[outBit],
      },
    };
    if (i > 0) {
      netnames['n${i - 1}'] = <String, Object?>{
        'hide_name': 0,
        'bits': <Object?>[inBit],
        'attributes': <String, Object?>{},
      };
    }
  }

  final ports = <String, Object?>{
    'din': <String, Object?>{
      'direction': 'input',
      'bits': <Object?>[2],
    },
    'dout': <String, Object?>{
      'direction': 'output',
      'bits': <Object?>[2 + chainLength],
    },
  };
  netnames['din'] = <String, Object?>{
    'hide_name': 0,
    'bits': <Object?>[2],
    'attributes': <String, Object?>{},
  };
  netnames['dout'] = <String, Object?>{
    'hide_name': 0,
    'bits': <Object?>[2 + chainLength],
    'attributes': <String, Object?>{},
  };

  final doc = <String, Object?>{
    'creator': 'Yosys (hand-crafted fixture — large_chain $chainLength cells)',
    'modules': <String, Object?>{
      'large_chain': <String, Object?>{
        'attributes': <String, Object?>{'top': '1'},
        'ports': ports,
        'cells': cells,
        'netnames': netnames,
      },
    },
  };

  const encoder = JsonEncoder.withIndent('  ');
  final out = encoder.convert(doc);
  final path = p.join(
    Directory.current.path,
    'test',
    'fixtures',
    'verilog',
    'large_chain.expected.json',
  );
  File(path).writeAsStringSync('$out\n');
  // This is a command-line generator; stdout is its output channel, not a
  // debugging leftover.
  // ignore: avoid_print
  print('Wrote $path ($chainLength cells)');
}
