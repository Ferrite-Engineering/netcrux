// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Static guard: every integration-test boot seeds EULA acceptance first.
//
// `CruxEulaGate` covers the app with a modal barrier until the agreement is
// accepted, and the barrier swallows every gesture. An integration test that
// boots without seeding acceptance has every tap miss, and because the
// integration suites run weekly the failure surfaces up to a week late,
// behind whatever else broke that week.
//
// The scanner is `crux_eula`'s `cruxAuditEulaSeededBoots`. A `bootstrap(`
// call counts as seeded when, earlier in the same function or in a `setUp`,
// the file calls NetCrux's seed helper `acceptEulaForTest` or names
// `kCruxEulaAcceptedVersionKey`; a boot whose arguments say
// `acceptEula: false` is the agreement's own test. `bootNetcrux` seeds on the
// caller's behalf (integration_test/helpers/app_driver.dart), which is why it
// is not listed as a boot call of its own.

import 'dart:io';

import 'package:crux_eula/crux_eula_guards.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every integration-test boot seeds EULA acceptance first', () {
    final root = Directory('integration_test');
    expect(
      root.existsSync(),
      isTrue,
      reason: 'integration_test/ must exist; run from the repository root',
    );
    final sources = <CruxEulaGuardSource>[
      for (final entity in root.listSync(recursive: true))
        if (entity is File && entity.path.endsWith('.dart'))
          CruxEulaGuardSource(
            path: entity.path.replaceAll(r'\', '/'),
            source: entity.readAsStringSync(),
          ),
    ];
    expect(sources, isNotEmpty, reason: 'no integration tests were found');

    final findings = cruxAuditEulaSeededBoots(
      sources: sources,
      seedCalls: const <String>{'acceptEulaForTest'},
    );
    expect(findings, isEmpty, reason: findings.join('\n'));
  });
}
