// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Dual-tree generator for the large-netlist stress ladder. Supersedes
// `tool/generate_large_chain_fixture.dart`.
//
// For each committed design it emits, under
// `test/fixtures/netlist/<design>/generated/`:
//   * `<design>.v`                       — human-readable RTL (informational)
//   * `<design>.netlist.json[.gz]`       — deterministic Yosys-shaped JSON the
//                                          parser ingests WITHOUT spawning Yosys
//   * `<design>.expected_netlist.json`   — the NetlistGolden the parser produces
//
// The netlist JSON is hand-synthesized (a chain/grid of `$_DFF_P_` flops) so
// the golden sweep runs Yosys-free in any environment. Large designs are
// gzip-compressed (dart:io `gzip`; we use `.gz` rather than `.zst` to avoid a
// native zstd dependency) and the 1M-cell mesh is NOT committed — only its
// generator manifest is, and the perf bench builds it on demand.
//
// Usage:
//   dart run tool/generate_netlist_fixtures.dart --tier committed
//   dart run tool/generate_netlist_fixtures.dart --design mesh_1m --out PATH
//
// Re-run after changing a design; then refresh the goldens with:
//   REGENERATE=1 flutter test test/services/yosys/netlist_golden_test.dart

import 'dart:convert';
import 'dart:io';

import 'package:netcrux/services/yosys/netlist_golden.dart';
import 'package:netcrux/services/yosys/streaming_yosys_json_reader.dart';
import 'package:path/path.dart' as p;

/// One design tier: a rows × cols array of `$_DFF_P_` flops. `chain_*` are a
/// single row (a linear pipeline); `grid_*` / `mesh_*` are R rows of C flops.
class _Design {
  const _Design({
    required this.name,
    required this.rows,
    required this.cols,
    required this.committed,
    required this.gzip,
  });

  final String name;
  final int rows;
  final int cols;

  /// Whether the elaborated netlist is committed (vs. manifest-only / on-demand).
  final bool committed;

  /// Whether the committed netlist JSON is gzip-compressed.
  final bool gzip;

  int get cellCount => rows * cols;
}

const _designs = <_Design>[
  _Design(name: 'chain_1k', rows: 1, cols: 1000, committed: true, gzip: false),
  _Design(name: 'chain_10k', rows: 1, cols: 10000, committed: true, gzip: true),
  _Design(
    name: 'grid_100k',
    rows: 100,
    cols: 1000,
    committed: true,
    gzip: true,
  ),
  // Several-hundred-MB ingestion-memory target — built on demand, not committed.
  _Design(
    name: 'mesh_1m',
    rows: 1000,
    cols: 1000,
    committed: false,
    gzip: true,
  ),
];

void main(List<String> args) {
  final tier = _argValue(args, '--tier');
  final designArg = _argValue(args, '--design');
  final outArg = _argValue(args, '--out');

  if (designArg == 'mesh_1m') {
    final design = _designs.firstWhere((d) => d.name == 'mesh_1m');
    final out = outArg ?? 'build/perf/mesh_1m.json';
    _writeNetlistJson(_buildDoc(design), out, gzip: out.endsWith('.gz'));
    _print('Wrote on-demand ${design.name} (${design.cellCount} cells) → $out');
    return;
  }

  if (tier != 'committed' && designArg == null) {
    _print('Usage: --tier committed  |  --design mesh_1m --out PATH');
    exitCode = 2;
    return;
  }

  _designs.where((d) => d.committed).forEach(_emitCommitted);
  _emitMeshManifest(_designs.firstWhere((d) => d.name == 'mesh_1m'));
}

void _emitCommitted(_Design design) {
  final dir = p.join(
    Directory.current.path,
    'test',
    'fixtures',
    'netlist',
    design.name,
    'generated',
  );
  Directory(dir).createSync(recursive: true);

  // 1. RTL (informational, human-readable).
  File(p.join(dir, '${design.name}.v')).writeAsStringSync(_buildRtl(design));

  // 2. Deterministic Yosys-shaped netlist JSON.
  final doc = _buildDoc(design);
  final jsonName = design.gzip
      ? '${design.name}.netlist.json.gz'
      : '${design.name}.netlist.json';
  _writeNetlistJson(doc, p.join(dir, jsonName), gzip: design.gzip);

  // 3. The golden the parser produces from that JSON.
  final model = const StreamingYosysJsonReader().parse(jsonEncode(doc));
  final golden = NetlistGolden.compute(model, source: '${design.name}.v');
  File(p.join(dir, '${design.name}.expected_netlist.json')).writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(golden)}\n',
  );
  _print(
    'Wrote ${design.name}: ${design.cellCount} cells '
    '($jsonName${design.gzip ? ', gz' : ''})',
  );
}

void _emitMeshManifest(_Design design) {
  final dir = p.join(
    Directory.current.path,
    'test',
    'fixtures',
    'netlist',
    design.name,
    'generated',
  );
  Directory(dir).createSync(recursive: true);
  final manifest = <String, Object?>{
    'design': design.name,
    'rows': design.rows,
    'cols': design.cols,
    'cellCount': design.cellCount,
    'cellType': r'$_DFF_P_',
    'committed': false,
    'build':
        'dart run tool/generate_netlist_fixtures.dart --design mesh_1m --out build/perf/mesh_1m.json',
  };
  File(p.join(dir, '${design.name}.gen.json')).writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
  );
  File(p.join(dir, 'README.md')).writeAsStringSync(
    '# ${design.name} (on-demand)\n\n'
    'A ${design.cellCount}-cell mesh — the ingestion-memory perf target. The\n'
    '~several-hundred-MB netlist is **not committed**; only the manifest\n'
    '(`${design.name}.gen.json`) is. Build it on demand:\n\n'
    '```sh\n${manifest['build']}\n```\n',
  );
  _print('Wrote ${design.name} manifest (on-demand, not committed)');
}

/// Builds a Yosys `write_json`-shaped document: a single top module with
/// `rows × cols` `$_DFF_P_` flops. Bit 2 is the shared clock; each row is a
/// `d_r → flop → … → flop → q_r` pipeline with its own data nets.
Map<String, Object?> _buildDoc(_Design design) {
  const clkBit = 2;
  final cells = <String, Object?>{};
  final netnames = <String, Object?>{
    'clk': <String, Object?>{
      'hide_name': 0,
      'bits': <Object?>[clkBit],
      'attributes': <String, Object?>{},
    },
  };
  final ports = <String, Object?>{
    'clk': <String, Object?>{
      'direction': 'input',
      'bits': <Object?>[clkBit],
    },
  };

  var nextBit = clkBit + 1;
  for (var r = 0; r < design.rows; r++) {
    // cols+1 data nets for this row: net[0]=d_r … net[cols]=q_r.
    final rowBits = <int>[for (var c = 0; c <= design.cols; c++) nextBit + c];
    nextBit += design.cols + 1;

    final dName = design.rows == 1 ? 'd' : 'd_$r';
    final qName = design.rows == 1 ? 'q' : 'q_$r';
    ports[dName] = <String, Object?>{
      'direction': 'input',
      'bits': <Object?>[rowBits.first],
    };
    ports[qName] = <String, Object?>{
      'direction': 'output',
      'bits': <Object?>[rowBits.last],
    };
    netnames[dName] = <String, Object?>{
      'hide_name': 0,
      'bits': <Object?>[rowBits.first],
      'attributes': <String, Object?>{},
    };
    netnames[qName] = <String, Object?>{
      'hide_name': 0,
      'bits': <Object?>[rowBits.last],
      'attributes': <String, Object?>{},
    };

    for (var c = 0; c < design.cols; c++) {
      cells['ff_${r}_$c'] = <String, Object?>{
        'hide_name': 0,
        'type': r'$_DFF_P_',
        'parameters': <String, Object?>{},
        'attributes': <String, Object?>{},
        'port_directions': <String, Object?>{
          'C': 'input',
          'D': 'input',
          'Q': 'output',
        },
        'connections': <String, Object?>{
          'C': <Object?>[clkBit],
          'D': <Object?>[rowBits[c]],
          'Q': <Object?>[rowBits[c + 1]],
        },
      };
      // Name the interior nets (not the row's d/q boundary nets).
      if (c > 0) {
        netnames['n_${r}_${c - 1}'] = <String, Object?>{
          'hide_name': 0,
          'bits': <Object?>[rowBits[c]],
          'attributes': <String, Object?>{},
        };
      }
    }
  }

  return <String, Object?>{
    'creator':
        'NetCrux fixture generator — ${design.name} '
        '(${design.cellCount} \$_DFF_P_ cells)',
    'modules': <String, Object?>{
      design.name: <String, Object?>{
        'attributes': <String, Object?>{'top': '1'},
        'ports': ports,
        'cells': cells,
        'netnames': netnames,
      },
    },
  };
}

String _buildRtl(_Design design) {
  final buffer = StringBuffer()
    ..writeln(
      '// ${design.name}: ${design.rows} row(s) x ${design.cols} '
      '\$_DFF_P_ flops (${design.cellCount} cells).',
    )
    ..writeln('// Generated by tool/generate_netlist_fixtures.dart.');
  final ins = <String>['clk'];
  final outs = <String>[];
  for (var r = 0; r < design.rows; r++) {
    ins.add(design.rows == 1 ? 'd' : 'd_$r');
    outs.add(design.rows == 1 ? 'q' : 'q_$r');
  }
  buffer
    ..writeln('module ${design.name}(')
    ..writeln('    input ${ins.join(', input ')},')
    ..writeln('    output ${outs.join(', output ')}')
    ..writeln(');');
  for (var r = 0; r < design.rows; r++) {
    final d = design.rows == 1 ? 'd' : 'd_$r';
    final q = design.rows == 1 ? 'q' : 'q_$r';
    buffer
      ..writeln('  reg [${design.cols - 1}:0] r$r;')
      ..writeln(
        '  always @(posedge clk) r$r <= '
        '{r$r[${design.cols - 2}:0], $d};',
      )
      ..writeln('  assign $q = r$r[${design.cols - 1}];');
  }
  buffer.writeln('endmodule');
  return buffer.toString();
}

void _writeNetlistJson(
  Map<String, Object?> doc,
  String path, {
  required bool gzip,
}) {
  Directory(p.dirname(path)).createSync(recursive: true);
  final jsonString = jsonEncode(doc);
  if (gzip) {
    final bytes = GZipCodec().encode(utf8.encode(jsonString));
    File(path).writeAsBytesSync(bytes);
  } else {
    File(path).writeAsStringSync('$jsonString\n');
  }
}

String? _argValue(List<String> args, String flag) {
  final i = args.indexOf(flag);
  if (i < 0 || i + 1 >= args.length) return null;
  return args[i + 1];
}

void _print(String message) {
  // This is a CLI generator; stdout is the intended progress channel.
  // ignore: avoid_print
  print(message);
}
