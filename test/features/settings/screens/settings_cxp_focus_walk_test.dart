// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The Tab order through Settings > CXP Cross-Probe, pinned as a transcript: it
// models what NVDA reads on each stop. The section is the suite-shared one, so
// the transcript reads the same in every suite product; a change in what is
// announced is a change to review.
//
// LOCALE_SWEEP_EXEMPT: the transcript is an English golden of the Tab order;
// the section's rendering in every locale is swept by
// settings_cxp_section_test.dart.

import 'package:crux_a11y/crux_a11y_testing.dart';
import 'package:crux_cxp_ui/crux_cxp_ui.dart';
import 'package:crux_settings/crux_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/app_settings.dart';
import 'package:netcrux/features/settings/providers/app_settings_provider.dart';
import 'package:netcrux/features/settings/screens/settings_screen.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/remote/cxp/netcrux_cxp_binding.dart';
import 'package:netcrux/services/settings/netcrux_settings_codec.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _golden =
    'test/features/settings/screens/goldens/settings_cxp_section.txt';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets(
    'the CXP section is walked in the order every suite product has',
    (tester) async {
      final handle = tester.ensureSemantics();
      await tester.binding.setSurfaceSize(const Size(1000, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          settingsServiceProvider.overrideWithValue(
            SettingsService<AppSettings>(
              const NetcruxSettingsCodec(),
              prefsOverride: prefs,
            ),
          ),
          cruxCxpProductBindingProvider.overrideWithValue(kNetcruxCxpBinding),
          cruxCxpLaunchSettingsProvider.overrideWithValue(
            const CruxCxpSettings(enabled: true, port: 54323),
          ),
          cruxCxpRuntimeProvider.overrideWith((_) async => null),
          cruxCxpServerStatusProvider.overrideWithValue((
            running: true,
            port: 54323,
            problem: null,
          )),
          cruxCxpPeersProvider.overrideWithValue(const []),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: SettingsScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final l10n = await L10N.delegate.load(const Locale('en'));
      await tester.tap(find.text(l10n.settingsCxpSectionTitle).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final walk = await walkFocus(tester);

      expectCleanFocusWalk(walk, context: 'Settings > CXP Cross-Probe');
      final lines = walk.stops.map((s) => s.line).toList();
      for (final named in const <String>[
        'Enable CXP server',
        'CXP port',
        'Request attention on cross-probe',
        'Broadcast selection automatically',
      ]) {
        expect(
          lines.any((line) => line.contains(named)),
          isTrue,
          reason: '"$named" is not a named Tab stop:\n${walk.transcript}',
        );
      }
      expectFocusWalkGolden(walk, _golden);
      handle.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}
