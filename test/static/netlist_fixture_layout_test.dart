// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../support/os_detritus.dart';

/// Static guard: no loose fixture files at a
/// `<design>/` root — every `.v` / `.json` / `.json.gz` must live in
/// `generated/` or `captured/`. Mirrors WaveCrux's `fixture_dir_layout_test`.
/// Keeps the corpus self-describing so a new stress design or captured core
/// can't ship dumped at the unqualified root.
void main() {
  const roots = <String>[
    'test/fixtures/netlist',
    'verification/fixtures/netlist',
  ];

  test('every netlist fixture lives under generated/ or captured/', () {
    final violations = <String>[];
    for (final rootPath in roots) {
      final root = Directory(rootPath);
      if (!root.existsSync()) continue;
      for (final design in root.listSync().whereType<Directory>()) {
        // `helpers/` holds the README + regeneration docs, not fixtures.
        if (p.basename(design.path) == 'helpers') continue;
        for (final entity in design.listSync()) {
          final name = p.basename(entity.path);
          if (entity is Directory) {
            if (name != 'generated' && name != 'captured') {
              violations.add(
                '${p.relative(entity.path)}: only generated/ or captured/ '
                'subdirs are allowed under a design',
              );
            }
            continue;
          }
          // A loose file directly under <design>/ — README is the only
          // allowed non-fixture, plus the detritus an OS writes when someone
          // browses the corpus. Any other dotfile is a stray and is reported.
          if (name == 'README.md' || isOsDetritus(name)) continue;
          violations.add(
            '${p.relative(entity.path)}: loose fixture at the design root '
            '(move it into generated/ or captured/)',
          );
        }
      }
    }
    expect(
      violations,
      isEmpty,
      reason:
          'netlist fixtures must live in generated/ or captured/:\n'
          '${violations.join('\n')}',
    );
  });
}
