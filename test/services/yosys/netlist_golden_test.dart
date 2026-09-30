// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/services/yosys/netlist_golden.dart';
import 'package:netcrux/services/yosys/streaming_yosys_json_reader.dart';
import 'package:path/path.dart' as p;

/// Yosys-free golden sweep over the committed netlist stress ladder.
///
/// For every committed `<design>/generated/<design>.netlist.json[.gz]`, parse
/// it with the production [StreamingYosysJsonReader], recompute the
/// [NetlistGolden], and assert it equals the committed
/// `<design>.expected_netlist.json`. A parser regression is caught by diff,
/// not by eye — and without ever spawning Yosys.
///
/// Refresh the goldens after changing a design or the generator:
///   REGENERATE=1 flutter test test/services/yosys/netlist_golden_test.dart
void main() {
  final regenerate = Platform.environment['REGENERATE'] == '1';
  final corpusRoot = Directory('test/fixtures/netlist');
  final designs = _discoverDesigns(corpusRoot);

  test('the committed netlist corpus is non-empty', () {
    // Guards against the corpus silently emptying out into a no-op green.
    expect(
      designs,
      isNotEmpty,
      reason: 'no committed netlist designs found under ${corpusRoot.path}',
    );
    expect(designs.map((d) => d.name), contains('chain_10k'));
  });

  for (final design in designs) {
    test('${design.name}: parsed golden matches the committed snapshot', () {
      final raw = _readNetlist(design.netlistFile);
      final model = const StreamingYosysJsonReader().parse(raw);
      final golden = NetlistGolden.compute(model, source: '${design.name}.v');
      final encoded = '${const JsonEncoder.withIndent('  ').convert(golden)}\n';

      if (regenerate) {
        design.goldenFile.writeAsStringSync(encoded);
        return;
      }
      expect(
        design.goldenFile.existsSync(),
        isTrue,
        reason:
            'missing ${design.goldenFile.path} — run '
            'REGENERATE=1 flutter test '
            'test/services/yosys/netlist_golden_test.dart',
      );
      expect(
        encoded,
        // Normalize CRLF→LF: the committed golden is LF, but git may check it
        // out as CRLF on Windows. The encoder always emits LF, so compare on
        // LF terms rather than failing on line endings alone.
        design.goldenFile.readAsStringSync().replaceAll('\r\n', '\n'),
        reason:
            '${design.name} golden drifted — a parser regression, or run '
            'REGENERATE=1 if the change is intentional',
      );
    });
  }

  test('chain_10k has exactly 10000 cells (explicit count, not just hash)', () {
    final design = designs.firstWhere((d) => d.name == 'chain_10k');
    final model = const StreamingYosysJsonReader().parse(
      _readNetlist(design.netlistFile),
    );
    final module = model.modules['chain_10k']!;
    expect(module.cells.length, 10000);
  });
}

class _DesignFixture {
  _DesignFixture(this.name, this.netlistFile, this.goldenFile);
  final String name;
  final File netlistFile;
  final File goldenFile;
}

List<_DesignFixture> _discoverDesigns(Directory root) {
  if (!root.existsSync()) return const <_DesignFixture>[];
  final designs = <_DesignFixture>[];
  for (final entity in root.listSync().whereType<Directory>()) {
    final name = p.basename(entity.path);
    if (name == 'malformed' || name == 'helpers') continue;
    // A design's netlist lives under generated/ (synthetic) or captured/
    // (real elaborated cores).
    for (final tier in <String>['generated', 'captured']) {
      final dir = Directory(p.join(entity.path, tier));
      if (!dir.existsSync()) continue;
      final plain = File(p.join(dir.path, '$name.netlist.json'));
      final gz = File(p.join(dir.path, '$name.netlist.json.gz'));
      final netlist = plain.existsSync()
          ? plain
          : (gz.existsSync() ? gz : null);
      if (netlist == null) continue; // e.g. mesh_1m (manifest only)
      designs.add(
        _DesignFixture(
          name,
          netlist,
          File(p.join(dir.path, '$name.expected_netlist.json')),
        ),
      );
    }
  }
  designs.sort((a, b) => a.name.compareTo(b.name));
  return designs;
}

String _readNetlist(File file) {
  if (file.path.endsWith('.gz')) {
    return utf8.decode(GZipCodec().decode(file.readAsBytesSync()));
  }
  return file.readAsStringSync();
}
