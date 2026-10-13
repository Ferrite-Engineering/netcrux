// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Static guard: a ColorScheme's `outline` token never colors TEXT.
//
// `outline` is a Material 3 BORDER token — the hairline around an
// `OutlineInputBorder`, a card edge, a divider, a painter's stroke. The
// suite's UI conventions are explicit that de-emphasised text must use
// `onSurfaceVariant` instead: `outline` was never chosen against WCAG
// text-contrast minimums, only against adjacent surface colors, so using it
// to color text reads as a contrast failure. A paid accessibility re-check
// is the reason this sweep happened; this guard is what keeps a new
// violation from shipping quietly afterward.
//
// The scanner is `crux_guards`' `cruxAuditOutlineText`, shared by the four
// products: every `.outline` member access under any receiver is a finding
// unless pinned below to its file, line and trimmed text with the reason it
// is not a text color. An edit around a pinned line re-flags whatever sits
// there now instead of carrying the exemption forward, and an exemption that
// matches nothing is a finding too, so the list cannot outlive the code.
//
// Scope: this repository's `lib/`.

import 'dart:io';

import 'package:crux_guards/crux_guards.dart';
import 'package:flutter_test/flutter_test.dart';

const _exemptions = <CruxOutlineExemption>[
  CruxOutlineExemption(
    file: 'lib/features/viewer/widgets/schematic_scrollbars.dart',
    line: 253,
    expectedTrimmed: 'color: theme.colorScheme.outline,',
    reason:
        'DecoratedBox fill color for the schematic scrollbar thumb: a fill, '
        'not text.',
  ),
];

void main() {
  test('the outline token is never used to color text', () {
    final root = Directory('lib');
    expect(
      root.existsSync(),
      isTrue,
      reason: 'lib/ must exist; run from the repository root',
    );
    final sources = <CruxGuardSource>[
      for (final entity in root.listSync(recursive: true))
        if (entity is File && entity.path.endsWith('.dart'))
          CruxGuardSource(
            path: entity.path.replaceAll(r'\', '/'),
            source: entity.readAsStringSync(),
          ),
    ];

    final result = cruxAuditOutlineText(
      sources: sources,
      exemptions: _exemptions,
    );

    // Non-vacuity: a wrong working directory would make this pass by
    // scanning nothing.
    expect(
      result.filesScanned,
      greaterThan(100),
      reason: 'the source walk collected implausibly few files',
    );
    expect(
      result.isClean,
      isTrue,
      reason:
          'the outline token is used where onSurfaceVariant belongs, or an '
          'unreviewed new use needs an exemption here with its reason:\n'
          '${result.describe()}',
    );
  });
}
