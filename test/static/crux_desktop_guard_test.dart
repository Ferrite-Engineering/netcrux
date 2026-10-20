// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Static guard: no raw Material pattern the Crux Desktop layer replaces.
//
// Dialogs open through `showCruxDialog`, transient feedback goes through the
// Crux toast helpers, a visible overflow is `CruxOverflowMenu`, settings that
// apply at once are `CruxSwitch` and form rows are `CruxFormRow`. The scanner
// is `crux_guards`' `cruxAuditCruxDesktop` over this repository's `lib/`.
//
// `crux_desktop_allow_list.txt` names the sites that cannot move yet and why,
// with exact counts. It only shrinks: a site that moves must lower or remove
// its entry, and a new site is a finding.

import 'dart:io';

import 'package:crux_guards/crux_guards.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no raw Material pattern the Crux Desktop layer replaces', () {
    final root = Directory('lib');
    expect(
      root.existsSync(),
      isTrue,
      reason: 'lib/ must exist; run from the repository root',
    );
    final sources = <CruxGuardSource>[
      for (final entity in root.listSync(recursive: true))
        if (entity is File &&
            entity.path.endsWith('.dart') &&
            !entity.path.endsWith('.g.dart') &&
            !entity.path.endsWith('.freezed.dart'))
          CruxGuardSource(
            path: entity.path.replaceAll(r'\', '/'),
            source: entity.readAsStringSync(),
          ),
    ];
    final allowFile = File('test/static/crux_desktop_allow_list.txt');
    final allowances = cruxParseDesktopAllowList(
      allowFile.existsSync() ? allowFile.readAsStringSync() : '',
    );

    final result = cruxAuditCruxDesktop(
      sources: sources,
      allowances: allowances,
    );

    expect(
      result.filesScanned,
      greaterThan(100),
      reason: 'the source walk collected implausibly few files',
    );
    expect(
      result.isClean,
      isTrue,
      reason:
          'a raw Material dialog, snackbar, switch, checkbox tile or "more '
          'vert" icon is back, or an allow-list entry is stale:\n'
          '${result.describe()}',
    );
  });
}
