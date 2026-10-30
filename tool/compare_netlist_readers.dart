// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Reads a gate-level Verilog netlist with the native gate-level reader and
// through Yosys, and says whether the two models describe the same design.
//
//   dart run tool/compare_netlist_readers.dart [--top NAME] [--liberty LIB]...
//       [--cell-model V]... [--src exact|line|ignore] [--no-order]
//       [--keep DIR] [--reference-json FILE] FILE.v...
//
// The Yosys side runs what the app's Yosys route runs: Liberty cells as
// black-box stubs, the cell models and sources read with `read_verilog`,
// `hierarchy` without `-check`, `proc`, `write_json`, the JSON read back by
// the production reader, and the black-box pin inference. The comparison is
// by connectivity, not by bit id (see test/support/netlist_equivalence.dart):
// modules, ports, nets, cells, cell types, connected pins, declared pin
// directions and, as chosen, `src` locations and iteration order.
//
// `--reference-json` compares with a Yosys JSON document the flow already
// wrote (and the pin inference the app runs after reading it) instead of
// running Yosys, which is how the largest designs are compared when their
// Yosys run is already on disk.
//
// Exit status 0 when they match, 1 when they differ, 2 for a bad command
// line, 3 when the native reader declined the file. Needs `yosys` on PATH
// and holds both models in memory at once, so use it on designs of up to a
// few hundred thousand cells; `bench_netlist_parse.dart` measures the large
// ones.

import 'dart:io';

import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/services/liberty/liberty_parser.dart';
import 'package:netcrux/services/verilog/native_netlist_reader.dart';
import 'package:netcrux/services/yosys/black_box_port_inference.dart';
import 'package:netcrux/services/yosys/chunked_yosys_json_reader.dart';

import '../test/support/netlist_equivalence.dart';
import '../test/support/yosys_reference_model.dart';

Future<void> main(List<String> args) async {
  final liberty = <String>[];
  final models = <String>[];
  final files = <String>[];
  var top = '';
  var src = SrcComparison.exact;
  var order = true;
  String? keep;
  String? referenceJson;
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    switch (arg) {
      case '--top':
        top = _value(args, ++i, arg);
      case '--liberty':
        liberty.add(_value(args, ++i, arg));
      case '--cell-model':
        models.add(_value(args, ++i, arg));
      case '--src':
        final name = _value(args, ++i, arg);
        src = SrcComparison.values.firstWhere(
          (c) => c.name == name,
          orElse: () => _usage('unknown --src $name'),
        );
      case '--no-order':
        order = false;
      case '--keep':
        keep = _value(args, ++i, arg);
      case '--reference-json':
        referenceJson = _value(args, ++i, arg);
      default:
        if (arg.startsWith('--')) _usage('unknown option $arg');
        files.add(arg);
    }
  }
  if (files.isEmpty) _usage('no netlist given');
  if (referenceJson == null && findYosys() == null) {
    stderr.writeln('yosys is not on the PATH');
    exit(2);
  }

  final libraries = [for (final l in liberty) LibertyParser.parseFile(l)];
  final clock = Stopwatch()..start();
  final outcome = readGateLevelNetlist(
    NativeReadRequest(
      sourceFiles: files,
      libertyLibraries: libraries,
      cellModelFiles: models,
      topModule: top,
    ),
  );
  final nativeMs = clock.elapsedMilliseconds;
  if (outcome is! NativeReadSuccess) {
    final line = outcome is NativeReadFallbackOutcome
        ? outcome.diagnosticLine
        : 'cancelled';
    stderr.writeln('native reader declined: $line');
    exit(3);
  }

  clock
    ..reset()
    ..start();
  final ({NetlistModel model, BlackBoxReport report}) reference;
  if (referenceJson != null) {
    reference = inferBlackBoxPorts(
      ChunkedYosysJsonReader.parseFile(referenceJson),
    );
  } else {
    final scratch = keep == null
        ? Directory.systemTemp.createTempSync('compare_netlist_readers')
        : Directory(keep);
    scratch.createSync(recursive: true);
    reference = yosysReferenceModel(
      sources: files,
      scratch: scratch,
      libertyLibraries: libraries,
      cellModelFiles: models,
      top: top,
    );
    if (keep == null) scratch.deleteSync(recursive: true);
  }
  final yosysMs = clock.elapsedMilliseconds;
  final differences = compareNetlists(
    outcome.model,
    reference.model,
    options: EquivalenceOptions(
      src: src,
      compareOrder: order,
      maxDifferences: 60,
    ),
  );
  if (outcome.report != reference.report) {
    differences.add(
      'black-box report differs: ${outcome.report} vs ${reference.report}',
    );
  }
  final stats = outcome.stats;
  stdout.writeln(
    'native: ${stats.modules} modules, ${stats.cells} cells, '
    '${stats.nets} nets in $nativeMs ms; yosys route: $yosysMs ms',
  );
  if (differences.isEmpty) {
    stdout.writeln('The two models are equivalent.');
    return;
  }
  stdout.writeln('${differences.length} difference(s):');
  differences.forEach(stdout.writeln);
  exit(1);
}

String _value(List<String> args, int index, String flag) {
  if (index >= args.length) _usage('$flag needs a value');
  return args[index];
}

Never _usage(String problem) {
  stderr
    ..writeln(problem)
    ..writeln(
      'usage: compare_netlist_readers [--top NAME] [--liberty LIB]... '
      '[--cell-model V]... [--src exact|line|ignore] [--no-order] '
      '[--keep DIR] FILE.v...',
    );
  exit(2);
}
