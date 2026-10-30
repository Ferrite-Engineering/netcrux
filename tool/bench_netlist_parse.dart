// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Times the parse of a netlist the way the app does it and reports the peak
// memory of the process: for measuring NetCrux on a design of a size no
// checked-in fixture reaches (see tool/gen_gate_netlist.py).
//
//   dart run tool/bench_netlist_parse.dart [--black-boxes] [--as-string] FILE
//   dart run tool/bench_netlist_parse.dart --native [--liberty LIB]...
//       [--cell-model V]... [--top NAME] FILE.v[.gz]...
//   dart compile exe tool/bench_netlist_parse.dart -o bench && ./bench FILE
//
// By default FILE is a Yosys JSON netlist, parsed on a worker isolate
// straight from the disk in chunks (`parseNetlistFileOnIsolate`), as File >
// Open Netlist JSON does. `--black-boxes` also gives black-box pins a
// direction, as a project that draws missing modules as black boxes does.
// `--as-string` reads the whole file into one string first and parses that,
// which is how the app read a netlist before it read files in chunks; it
// fails past 2 GiB and is only here to compare.
//
// `--native` reads structural Verilog with the native gate-level reader
// (`readGateLevelNetlistOnIsolate`), straight from the disk, with the
// Liberty libraries and cell model files given, and the black-box pin
// inference the app runs after it. A native read needs no Yosys.
//
// Prints one JSON object: parse seconds, module and cell counts, and the
// process's peak resident set size in bytes.

import 'dart:convert';
import 'dart:io';

import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/services/liberty/liberty_parser.dart';
import 'package:netcrux/services/verilog/native_netlist_reader.dart';
import 'package:netcrux/services/yosys/isolate_netlist_parser.dart';

Future<void> main(List<String> args) async {
  final blackBoxes = args.contains('--black-boxes');
  final asString = args.contains('--as-string');
  final native = args.contains('--native');
  final liberty = <String>[];
  final models = <String>[];
  var top = '';
  final files = <String>[];
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--liberty' && i + 1 < args.length) {
      liberty.add(args[++i]);
    } else if (arg == '--cell-model' && i + 1 < args.length) {
      models.add(args[++i]);
    } else if (arg == '--top' && i + 1 < args.length) {
      top = args[++i];
    } else if (!arg.startsWith('--')) {
      files.add(arg);
    }
  }
  if (files.isEmpty || (!native && files.length != 1)) {
    stderr.writeln(
      'usage: bench_netlist_parse [--black-boxes] [--as-string] FILE\n'
      '       bench_netlist_parse --native [--liberty LIB]... '
      '[--cell-model V]... [--top NAME] FILE.v...',
    );
    exit(64);
  }
  final bytes = files.fold<int>(0, (sum, f) => sum + File(f).lengthSync());
  final clock = Stopwatch()..start();
  final NetlistModel? model;
  if (native) {
    final libraries = [for (final l in liberty) LibertyParser.parseFile(l)];
    final loaded = clock.elapsedMilliseconds;
    final outcome = await readGateLevelNetlistOnIsolate(
      NativeReadRequest(
        sourceFiles: files,
        libertyLibraries: libraries,
        cellModelFiles: models,
        topModule: top,
      ),
    );
    stderr.writeln('liberty $loaded ms');
    if (outcome is! NativeReadSuccess) {
      final line = outcome is NativeReadFallbackOutcome
          ? outcome.diagnosticLine
          : 'cancelled';
      stderr.writeln('native reader declined: $line');
      exit(1);
    }
    model = outcome.model;
  } else if (asString) {
    final text = File(files.single).readAsStringSync();
    final read = clock.elapsedMilliseconds;
    stderr.writeln('read ${text.length} chars in $read ms');
    model = blackBoxes
        ? (await parseNetlistWithBlackBoxesOnIsolate(text))?.model
        : await parseNetlistOnIsolate(text);
  } else {
    model = blackBoxes
        ? (await parseNetlistFileWithBlackBoxesOnIsolate(files.single))?.model
        : await parseNetlistFileOnIsolate(files.single);
  }
  clock.stop();
  var cells = 0;
  var nets = 0;
  for (final module in model!.modules.values) {
    cells += module.cells.length;
    nets += module.nets.length;
  }
  stdout.writeln(
    jsonEncode(<String, Object?>{
      'file': files.join(','),
      'bytes': bytes,
      'mode': native
          ? 'native'
          : asString
          ? 'string'
          : 'chunked',
      'blackBoxes': blackBoxes,
      'parseSeconds': clock.elapsedMilliseconds / 1000,
      'modules': model.modules.length,
      'cells': cells,
      'nets': nets,
      'peakRssBytes': ProcessInfo.maxRss,
    }),
  );
}
