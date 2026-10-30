// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Writes the ROHD netlist fixtures into the directory above this package.
//
//   dart pub get
//   dart run bin/generate.dart
//
// Each design is built, then exported through ROHD's `NetlistService` with
// source tracing on, so every module carries `rohd.src_trace` and the
// document carries the shared `files` array. The output is deterministic for
// a given ROHD commit, which is pinned in pubspec.yaml.
//
// Two edits are made to ROHD's output so the committed files do not depend on
// the machine that wrote them: the `files` entries are normalised (a path
// through `.dart_tool/..` is collapsed, and a path inside this package is
// made relative to the directory the netlists are written to) and the
// location of the pub cache is replaced by `/pub-cache`. No other byte of
// the netlist is touched.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:rohd/rohd.dart';
import 'package:rohd_hcl/rohd_hcl.dart';
import 'package:rohd_netlist_fixtures/designs.dart';

Future<void> main(List<String> args) async {
  final out = args.isEmpty
      ? Directory.current.parent
      : Directory(args.first).absolute;
  final packageRoot = Directory.current.path;
  final pubCache =
      Platform.environment['PUB_CACHE'] ??
      p.join(Platform.environment['HOME'] ?? '', '.pub-cache');

  // ROHD records a path relative to the package root it was given, here this
  // package. The fixtures are read from the directory above it, so a path
  // inside the package is rewritten relative to that directory, which is
  // where a reader looks for it first.
  String portable(String file) {
    final normal = p.normalize(file);
    if (normal.startsWith(pubCache)) {
      return '/pub-cache${normal.substring(pubCache.length)}';
    }
    if (p.isRelative(normal)) {
      return p.relative(p.join(packageRoot, normal), from: out.path);
    }
    return normal;
  }

  Future<void> emit(String file, Module Function() build) async {
    ModuleServices.instance.reset();
    SourceTracer.activate();
    final top = build();
    await top.build();
    final service = NetlistService(
      top,
      configuration: NetlistSynthesizerConfiguration(
        trace: true,
        packageRoot: packageRoot,
      ),
      packageRoot: packageRoot,
      register: false,
    );
    SourceTracer.clear();
    final document = jsonDecode(service.json) as Map<String, Object?>;
    document['files'] = [
      for (final f in document['files']! as List<Object?>) portable('$f'),
    ];
    File(
      p.join(out.path, file),
    ).writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(document)}\n',
    );
    stdout.writeln('wrote $file');
  }

  await emit(
    'sample_pipeline.json',
    () => SamplePipeline(Logic(), Logic(), Sample()),
  );
  await emit(
    'lane_reducer.json',
    () => LaneReducer(LogicArray([4], 8), Logic(width: 2)),
  );
  await emit('demo_top.json', () => DemoTop(Logic(), Logic(), Logic()));
  // A component from the ROHD Hardware Component Library, so the fixtures
  // include a design this repository did not write.
  await emit(
    'hcl_fifo.json',
    () => Fifo(
      Logic(),
      Logic(),
      writeEnable: Logic(),
      writeData: Logic(width: 8),
      readEnable: Logic(),
      depth: 4,
    ),
  );
}
