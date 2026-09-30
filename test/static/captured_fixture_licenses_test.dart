// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Static guard: every `captured/` netlist
/// design (real RTL cores elaborated to a committed Yosys JSON) carries a
/// `PROVENANCE.md` whose license is on the suite allow-list — GPL / AGPL /
/// proprietary captures are blocked. Mirrors WaveCrux's
/// `captured_fixture_licenses_test`. Passes vacuously when no captured
/// tier exists, so a new captured core cannot ship with a forbidden license.
void main() {
  const allowedLicenses = <String>{
    'MIT',
    'BSD-2-Clause',
    'BSD-3-Clause',
    'Apache-2.0',
    'ISC',
    'CC0-1.0',
    'public-domain',
  };
  const roots = <String>[
    'test/fixtures/netlist',
    'verification/fixtures/netlist',
  ];
  final spdx = RegExp(r'\*\*License:\*\*[^\n]*?\(SPDX:\s*`([^`]+)`\)');

  List<File> capturedProvenances() {
    final files = <File>[];
    for (final rootPath in roots) {
      final root = Directory(rootPath);
      if (!root.existsSync()) continue;
      for (final design in root.listSync().whereType<Directory>()) {
        final captured = Directory(p.join(design.path, 'captured'));
        if (!captured.existsSync()) continue;
        final provenance = File(p.join(captured.path, 'PROVENANCE.md'));
        if (provenance.existsSync()) files.add(provenance);
      }
    }
    return files;
  }

  test('every captured/ design has a PROVENANCE.md', () {
    final missing = <String>[];
    for (final rootPath in roots) {
      final root = Directory(rootPath);
      if (!root.existsSync()) continue;
      for (final design in root.listSync().whereType<Directory>()) {
        final captured = Directory(p.join(design.path, 'captured'));
        if (!captured.existsSync()) continue;
        if (!File(p.join(captured.path, 'PROVENANCE.md')).existsSync()) {
          missing.add(p.relative(captured.path));
        }
      }
    }
    expect(
      missing,
      isEmpty,
      reason:
          'captured/ dirs without PROVENANCE.md:\n'
          '${missing.join('\n')}',
    );
  });

  test('every captured PROVENANCE.md license is on the allow-list', () {
    final violations = <String>[];
    for (final provenance in capturedProvenances()) {
      final body = provenance.readAsStringSync();
      final matches = spdx.allMatches(body);
      if (matches.isEmpty) {
        violations.add('${p.relative(provenance.path)}: no SPDX license found');
        continue;
      }
      for (final match in matches) {
        final license = match.group(1)!.trim();
        if (!allowedLicenses.contains(license)) {
          violations.add(
            '${p.relative(provenance.path)}: SPDX `$license` not in allow-list',
          );
        }
      }
    }
    expect(
      violations,
      isEmpty,
      reason:
          'captured fixtures with a forbidden license:\n'
          '${violations.join('\n')}',
    );
  });
}
