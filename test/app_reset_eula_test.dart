// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_eula/crux_eula.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/app.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// `--reset-eula` puts the installation back to "never accepted" so the
/// licence agreement is presented again. Exercised through the real
/// `NetcruxEulaStorage` over mocked `SharedPreferences`, so the test proves
/// the product store and the suite-fixed key agree, not just that a fake was
/// called.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  Future<String?> storedAcceptance() async =>
      (await SharedPreferences.getInstance()).getString(
        kCruxEulaAcceptedVersionKey,
      );

  Future<void> accept() async {
    await (await SharedPreferences.getInstance()).setString(
      kCruxEulaAcceptedVersionKey,
      kCruxEulaVersion,
    );
  }

  test('--reset-eula forgets a recorded acceptance', () async {
    await accept();

    await resetEulaIfRequested(const ['--reset-eula', 'top.v']);

    expect(await storedAcceptance(), isNull);
  });

  test('without the flag the acceptance is kept', () async {
    await accept();

    await resetEulaIfRequested(const ['--reset-telemetry-consent', 'top.v']);

    expect(await storedAcceptance(), kCruxEulaVersion);
  });

  test('--reset-eula on an installation that never accepted is a no-op', () {
    expect(resetEulaIfRequested(const ['--reset-eula']), completes);
  });
}
