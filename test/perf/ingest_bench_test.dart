// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/services/yosys/streaming_yosys_json_reader.dart';
import 'package:path/path.dart' as p;

/// Ingestion benchmark. Measures parse
/// wall-time + peak RSS for each committed design tier, plus the on-demand
/// 1M-cell mesh when present, and appends one JSON row per run to
/// `build/perf/ingest.jsonl` (gitignored). No hard assertion —
/// the numbers are *recorded*, not gated: wall-clock time and RSS vary too
/// much across machines to assert on a shared runner.
///
/// Gated behind `--dart-define=RUN_BENCHMARKS=true` so the default
/// `flutter test` never pays the cost; the perf CI job sets the define.
void main() {
  const runBenchmarks = bool.fromEnvironment('RUN_BENCHMARKS');

  test(
    'ingest bench — parse time + peak RSS per design tier',
    () async {
      const reader = StreamingYosysJsonReader();
      final rows = <Map<String, Object?>>[];

      for (final netlist in _benchNetlists()) {
        final raw = _readNetlist(netlist);
        final stopwatch = Stopwatch()..start();
        final model = reader.parse(raw);
        stopwatch.stop();
        final cells = model.modules.values.fold<int>(
          0,
          (sum, m) => sum + m.cells.length,
        );
        rows.add(<String, Object?>{
          'design': p.basename(netlist.path),
          'cells': cells,
          'parseMs': stopwatch.elapsedMilliseconds,
          'peakRssBytes': ProcessInfo.maxRss,
        });
        // Emitting bench progress to stdout is the point of this job.
        // ignore: avoid_print
        print('ingest: ${rows.last}');
      }

      final outDir = Directory('build/perf')..createSync(recursive: true);
      final out = File(p.join(outDir.path, 'ingest.jsonl'));
      final sink = out.openWrite(mode: FileMode.append);
      for (final row in rows) {
        sink.writeln(jsonEncode(row));
      }
      await sink.flush();
      await sink.close();
    },
    skip: runBenchmarks ? false : 'set --dart-define=RUN_BENCHMARKS=true',
  );
}

/// Every committed `*.netlist.json[.gz]` plus the on-demand mesh_1m netlist
/// if it has been built into `build/perf/`.
List<File> _benchNetlists() {
  final files = <File>[];
  final root = Directory('test/fixtures/netlist');
  if (root.existsSync()) {
    for (final dir in root.listSync().whereType<Directory>()) {
      final name = p.basename(dir.path);
      if (name == 'malformed' || name == 'helpers') continue;
      final gen = Directory(p.join(dir.path, 'generated'));
      if (!gen.existsSync()) continue;
      final plain = File(p.join(gen.path, '$name.netlist.json'));
      final gz = File(p.join(gen.path, '$name.netlist.json.gz'));
      if (plain.existsSync()) {
        files.add(plain);
      } else if (gz.existsSync()) {
        files.add(gz);
      }
    }
  }
  final mesh = File('build/perf/mesh_1m.json');
  if (mesh.existsSync()) files.add(mesh);
  files.sort((a, b) => a.path.compareTo(b.path));
  return files;
}

String _readNetlist(File file) {
  if (file.path.endsWith('.gz')) {
    return utf8.decode(GZipCodec().decode(file.readAsBytesSync()));
  }
  return file.readAsStringSync();
}
