// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/telemetry/netcrux_telemetry_strings.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

const _locales = <Locale>[
  Locale('en'),
  Locale('zh', 'CN'),
  Locale('zh'),
  Locale('ja'),
  Locale('ko'),
];

void main() {
  group('NetcruxTelemetryStrings', () {
    for (final locale in _locales) {
      test('settingsInstallationIdNone is localized for $locale', () async {
        final l10n = await L10N.delegate.load(locale);
        final strings = NetcruxTelemetryStrings(l10n);

        expect(
          strings.settingsInstallationIdNone,
          l10n.settingsTelemetryInstallationIdNone,
        );
        expect(strings.settingsInstallationIdNone, isNotEmpty);
      });
    }

    test('English text names the condition under which the id is created', () {
      return L10N.delegate.load(const Locale('en')).then((l10n) {
        expect(
          NetcruxTelemetryStrings(l10n).settingsInstallationIdNone,
          'No installation ID. One is created only when usage statistics are '
          'turned on.',
        );
      });
    });
  });
}
