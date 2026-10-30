// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Builds the reference model for a gate-level netlist the way the Yosys route
// of the app does, so a test (or `tool/compare_netlist_readers.dart`) can
// compare the native reader against it: Liberty cells become black-box stub
// modules read first, then the sources, then `hierarchy` without `-check`,
// `proc`, `write_json`, the JSON read back by the production chunked reader,
// and the black-box pin inference the app runs after it.

import 'dart:io';

import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/services/liberty/liberty_library.dart';
import 'package:netcrux/services/liberty/liberty_stub_writer.dart';
import 'package:netcrux/services/yosys/black_box_port_inference.dart';
import 'package:netcrux/services/yosys/chunked_yosys_json_reader.dart';

/// The path of a `yosys` binary, or `null` when none is installed.
String? findYosys() {
  final result = Process.runSync('which', <String>['yosys']);
  if (result.exitCode != 0) return null;
  final path = (result.stdout as String).trim();
  return path.isEmpty ? null : path;
}

/// Runs Yosys over [sources] and returns the model the app would show.
///
/// [libertyLibraries] are written as black-box stubs and read before the
/// sources. [cellModelFiles] are read as ordinary Verilog before the sources
/// (they should carry `(* blackbox *)` so they stay stubs). Throws a
/// [StateError] with Yosys's stderr when it fails. The working files go
/// under [scratch], which must exist.
({NetlistModel model, BlackBoxReport report}) yosysReferenceModel({
  required List<String> sources,
  required Directory scratch,
  List<LibertyLibrary> libertyLibraries = const <LibertyLibrary>[],
  List<String> cellModelFiles = const <String>[],
  String top = '',
}) {
  final yosys = findYosys();
  if (yosys == null) throw StateError('yosys is not installed');
  final reads = <String>[];
  if (libertyLibraries.isNotEmpty) {
    final stub = File('${scratch.path}/liberty_stubs.v')
      ..writeAsStringSync(writeLibertyStubs(libertyLibraries).verilog);
    reads.add('read_verilog "${stub.path}"');
  }
  for (final path in [...cellModelFiles, ...sources]) {
    reads.add('read_verilog "$path"');
  }
  final json = '${scratch.path}/reference.json';
  final script = <String>[
    ...reads,
    if (top.isEmpty) 'hierarchy -auto-top' else 'hierarchy -top $top',
    'proc',
    'write_json "$json"',
  ].join('; ');
  final result = Process.runSync(yosys, <String>['-q', '-p', script]);
  if (result.exitCode != 0) {
    throw StateError('yosys failed: ${result.stderr}');
  }
  final model = ChunkedYosysJsonReader.parseFile(json);
  return inferBlackBoxPorts(model);
}
