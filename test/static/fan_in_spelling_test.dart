// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// One spelling for fan-in and fan-out in every English label.
//
// The cone-view bar said "Fan-in" while the menus, the command palette, the
// toolbar and the context menu said "Fanin", so the same idea read two ways
// depending on where the user looked. English labels spell it "Fan-in" /
// "Fan-out" (capitalised at the start of a phrase, "fan-in" / "fan-out"
// inside one). The other four locales use their own established terms and
// are not checked here.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Matches the unhyphenated forms, in any case, as whole words.
final _unhyphenated = RegExp(r'\bfan(in|out)\b', caseSensitive: false);

void main() {
  test('English labels spell fan-in and fan-out with a hyphen', () {
    final arb =
        jsonDecode(
              File('lib/l10n/app_en.arb').readAsStringSync(),
            )
            as Map<String, dynamic>;
    final offenders = [
      for (final MapEntry(:key, :value) in arb.entries)
        if (!key.startsWith('@') &&
            value is String &&
            _unhyphenated.hasMatch(value))
          '$key: "$value"',
    ];
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('the trace and cone labels match the cone-view bar', () {
    final arb =
        jsonDecode(
              File('lib/l10n/app_en.arb').readAsStringSync(),
            )
            as Map<String, dynamic>;
    expect(arb['coneViewFanIn'], 'Fan-in');
    expect(arb['actionShowFanin'], 'Show Fan-in');
    expect(arb['actionShowFanout'], 'Show Fan-out');
    expect(arb['contextMenuTraceFanin'], 'Trace Fan-in');
    expect(arb['contextMenuTraceFanout'], 'Trace Fan-out');
    expect(
      arb['actionShowConeOfInfluenceFanin'],
      'Show Cone of Influence (Fan-in)',
    );
    expect(
      arb['actionShowConeOfInfluenceFanout'],
      'Show Cone of Influence (Fan-out)',
    );
  });
}
