// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Times the parse of a Yosys JSON netlist the way the app does it and reports
// the peak memory of the process: for measuring NetCrux on a design of a size
// no checked-in fixture reaches (see tool/gen_gate_netlist.py).
//
//   dart run tool/bench_netlist_parse.dart [--black-boxes] [--as-string] FILE
//   dart compile exe tool/bench_netlist_parse.dart -o bench && ./bench FILE
//
// By default the file is parsed on a worker isolate straight from the disk in
// chunks (`parseNetlistFileOnIsolate`), as File > Open Netlist JSON does.
// `--black-boxes` also gives black-box pins a direction, as a project that
// draws missing modules as black boxes does. `--as-string` reads the whole
// file into one string first and parses that, which is how the app read a
// netlist before it read files in chunks; it fails past 2 GiB and is only
// here to compare.
//
// Prints one JSON object: parse seconds, module and cell counts, and the
// process's peak resident set size in bytes.

import 'dart:convert';
import 'dart:io';

import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/services/yosys/isolate_netlist_parser.dart';

Future<void> main(List<String> args) async {
  final blackBoxes = args.contains('--black-boxes');
  final asString = args.contains('--as-string');
  final files = args.where((a) => !a.startsWith('--')).toList();
  if (files.length != 1) {
    stderr.writeln(
      'usage: bench_netlist_parse [--black-boxes] [--as-string] FILE',
    );
    exit(64);
  }
  final path = files.single;
  final bytes = File(path).lengthSync();
  final clock = Stopwatch()..start();
  final NetlistModel? model;
  if (asString) {
    final text = File(path).readAsStringSync();
    final read = clock.elapsedMilliseconds;
    stderr.writeln('read ${text.length} chars in $read ms');
    model = blackBoxes
        ? (await parseNetlistWithBlackBoxesOnIsolate(text))?.model
        : await parseNetlistOnIsolate(text);
  } else {
    model = blackBoxes
        ? (await parseNetlistFileWithBlackBoxesOnIsolate(path))?.model
        : await parseNetlistFileOnIsolate(path);
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
      'file': path,
      'bytes': bytes,
      'mode': asString ? 'string' : 'chunked',
      'blackBoxes': blackBoxes,
      'parseSeconds': clock.elapsedMilliseconds / 1000,
      'modules': model.modules.length,
      'cells': cells,
      'nets': nets,
      'peakRssBytes': ProcessInfo.maxRss,
    }),
  );
}
