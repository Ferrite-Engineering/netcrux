// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Static guard: no `labelText:` under `lib/`.
//
// The Crux Desktop theme sets `floatingLabelBehavior: never`, so an
// `InputDecoration.labelText` is shown only while its field is empty. A field
// that holds a value then shows a bare number or string with nothing saying
// what it is. A field that must stay identifiable is a `CruxFormRow` (label
// always visible, help text as the row's help, a hint for the empty field);
// a pure search or filter box uses `hintText` plus an explicit semantics
// label for its accessible name.
//
// Every occurrence of `labelText:` in a non-comment line of a `.dart` file
// under `lib/` is a finding unless pinned in [_allowed] to its file and
// trimmed line, with the reason it cannot be a form row or a hint. The list
// is empty on purpose, and an entry that matches nothing is a finding too.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `file|trimmed line` -> why the site is exempt.
const _allowed = <String, String>{};

final _labelText = RegExp(r'\blabelText\s*:');

void main() {
  test('no InputDecoration labelText under lib/', () {
    final root = Directory('lib');
    expect(
      root.existsSync(),
      isTrue,
      reason: 'lib/ must exist; run from the repository root',
    );
    var scanned = 0;
    final findings = <String>[];
    final matched = <String>{};
    for (final entity in root.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      scanned++;
      final path = entity.path.replaceAll(r'\', '/');
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final trimmed = lines[i].trim();
        if (trimmed.startsWith('//')) continue;
        if (!_labelText.hasMatch(trimmed)) continue;
        final key = '$path|$trimmed';
        if (_allowed.containsKey(key)) {
          matched.add(key);
        } else {
          findings.add('$path:${i + 1}: $trimmed');
        }
      }
    }

    // Non-vacuity: a wrong working directory would make this pass by
    // scanning nothing.
    expect(scanned, greaterThan(100), reason: 'implausibly few files scanned');
    expect(
      findings,
      isEmpty,
      reason:
          'labelText disappears once the field holds a value under the '
          'desktop theme; use a CruxFormRow (or hintText plus a semantics '
          'label for a search box):\n${findings.join('\n')}',
    );
    expect(
      _allowed.keys.where((key) => !matched.contains(key)),
      isEmpty,
      reason: 'stale allowance: it matches no line',
    );
  });
}
