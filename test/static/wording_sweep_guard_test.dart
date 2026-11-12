// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Wording canon for the labels the 2026-11 suite audit found worded
// differently across the four products (D44, D51, D52). The Reset Workspace
// confirmation uses the suite wording; "Cross-Probe Selection…" is hyphenated
// and capitalised like the other Title Case cross-probe labels; "license" is
// the spelling in every English string.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _locales = ['en', 'zh_CN', 'zh', 'ja', 'ko'];

Map<String, dynamic> _load(String locale) {
  final file = File('lib/l10n/app_$locale.arb');
  if (!file.existsSync()) {
    throw StateError('missing ${file.path}');
  }
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

void main() {
  final arbs = {for (final l in _locales) l: _load(l)};
  final en = arbs['en']!;

  for (final locale in _locales) {
    test('$locale: Cross-Probe Selection ends in an ellipsis', () {
      expect(
        (arbs[locale]!['actionCrossProbeSelection'] as String).endsWith('…'),
        isTrue,
      );
    });

    test('$locale: the Reset Workspace title asks a question', () {
      final title = arbs[locale]!['workspaceResetWorkspaceTitle'] as String;
      expect(title.endsWith('?') || title.endsWith('？'), isTrue, reason: title);
    });
  }

  test('en: Cross-Probe Selection… is hyphenated and capitalised', () {
    expect(en['actionCrossProbeSelection'], 'Cross-Probe Selection…');
  });

  test('en: the Reset Workspace confirm is the suite wording', () {
    expect(en['workspaceResetWorkspaceTitle'], 'Reset workspace?');
    expect(
      en['workspaceResetWorkspaceConfirm'],
      'All open tabs will be closed. The auto-saved workspace will be '
      'replaced with an empty workspace. This cannot be undone.',
    );
  });

  test('en: the About issue button reads as the Help menu item does', () {
    expect(en['actionSubmitIssue'], 'Submit Issue…');
  });

  test('en: no user-visible string spells "licence"', () {
    final offenders = <String>[
      for (final e in en.entries)
        if (!e.key.startsWith('@') &&
            e.value is String &&
            (e.value as String).toLowerCase().contains('licence'))
          e.key,
    ];
    expect(offenders, isEmpty);
  });
}
