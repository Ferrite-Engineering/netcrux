// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Static guard: every committed netlist has
/// its golden companion, and every malformed case has its expected-error
/// companion — so a parser regression cannot ship without a snapshot to diff
/// against. Mirrors WaveCrux's `captured_fixture_companion_test`. Also guards
/// against the corpus silently emptying into a no-op green.
void main() {
  const roots = <String>[
    'test/fixtures/netlist',
    'verification/fixtures/netlist',
  ];

  /// All `generated/` and `captured/` directories across the present roots.
  List<Directory> generatedDirs() {
    final dirs = <Directory>[];
    for (final rootPath in roots) {
      final root = Directory(rootPath);
      if (!root.existsSync()) continue;
      for (final design in root.listSync().whereType<Directory>()) {
        for (final tier in <String>['generated', 'captured']) {
          final dir = Directory(p.join(design.path, tier));
          if (dir.existsSync()) dirs.add(dir);
        }
      }
    }
    return dirs;
  }

  test('the committed corpus is non-empty', () {
    final designs = generatedDirs()
        .where((d) => p.basename(p.dirname(d.path)) != 'malformed')
        .toList();
    expect(
      designs,
      isNotEmpty,
      reason: 'no committed netlist designs found — the corpus emptied out',
    );
  });

  test('every *.netlist.json[.gz] has a *.expected_netlist.json golden', () {
    final orphans = <String>[];
    for (final gen in generatedDirs()) {
      for (final file in gen.listSync().whereType<File>()) {
        final name = p.basename(file.path);
        if (!name.endsWith('.netlist.json') &&
            !name.endsWith('.netlist.json.gz')) {
          continue;
        }
        final base = name
            .replaceFirst(RegExp(r'\.netlist\.json\.gz$'), '')
            .replaceFirst(RegExp(r'\.netlist\.json$'), '');
        final golden = File(p.join(gen.path, '$base.expected_netlist.json'));
        if (!golden.existsSync()) orphans.add(p.relative(file.path));
      }
    }
    expect(
      orphans,
      isEmpty,
      reason:
          'netlist fixtures missing an expected_netlist.json golden '
          '(run the generator):\n${orphans.join('\n')}',
    );
  });

  test('every malformed *.json has a *.expected_error.json companion', () {
    final orphans = <String>[];
    for (final gen in generatedDirs()) {
      if (p.basename(p.dirname(gen.path)) != 'malformed') continue;
      for (final file in gen.listSync().whereType<File>()) {
        final name = p.basename(file.path);
        if (!name.endsWith('.json') || name.endsWith('.expected_error.json')) {
          continue;
        }
        final base = name.substring(0, name.length - '.json'.length);
        final companion = File(p.join(gen.path, '$base.expected_error.json'));
        if (!companion.existsSync()) orphans.add(p.relative(file.path));
      }
    }
    expect(
      orphans,
      isEmpty,
      reason:
          'malformed fixtures missing an expected_error.json companion:\n'
          '${orphans.join('\n')}',
    );
  });
}
