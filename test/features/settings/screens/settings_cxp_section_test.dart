// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The Settings → CXP Cross-Probe section is the suite-shared
// `CruxCxpSettingsSection`, bound to the shared lifecycle: (1) Enable CXP
// server, (2) CXP port, (3) Request attention on cross-probe, (4) Broadcast
// selection automatically, (5) CXP Status, in that order. The four settings are
// saved by the shared notifier under NetCrux's own `netcrux.*` keys, and an
// unrelated settings save must never overwrite them.

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

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  Locale locale = const Locale('en'),
  CruxCxpSettings launch = const CruxCxpSettings(enabled: true, port: 54323),
  CruxCxpServerStatus status = (running: false, port: null, problem: null),
}) async {
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
      cruxCxpLaunchSettingsProvider.overrideWithValue(launch),
      // The status line renders deterministically, with no socket, manifest
      // writer or path_provider behind it.
      cruxCxpRuntimeProvider.overrideWith((_) async => null),
      cruxCxpServerStatusProvider.overrideWithValue(status),
      cruxCxpPeersProvider.overrideWithValue(const []),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: const SettingsScreen(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return container;
}

Future<void> _openCxpSection(WidgetTester tester, L10N l10n) async {
  await tester.tap(find.text(l10n.settingsCxpSectionTitle).first);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

CruxCxpStrings _strings(Locale locale) =>
    CruxCxpStrings.forLocale(locale, product: 'NetCrux');

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('renders all canonical rows in order', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pump(tester);
    final l10n = await L10N.delegate.load(const Locale('en'));
    final strings = _strings(const Locale('en'));

    await _openCxpSection(tester, l10n);

    // Each canonical row is present exactly once in the detail pane.
    final enable = find.text(strings.enableLabel);
    final port = find.text(strings.portHelp);
    final attention = find.text(strings.attentionLabel);
    final broadcast = find.text(strings.broadcastLabel);
    final status = find.text(strings.statusLabel);
    expect(enable, findsOneWidget);
    expect(port, findsOneWidget);
    expect(attention, findsOneWidget);
    expect(broadcast, findsOneWidget);
    expect(status, findsOneWidget);

    // The server is not running: the status shows "Stopped".
    expect(find.text(strings.statusStopped), findsOneWidget);

    // Order top-to-bottom: enable → port → attention → broadcast → status.
    final dy = <double>[
      tester.getTopLeft(enable).dy,
      tester.getTopLeft(port).dy,
      tester.getTopLeft(attention).dy,
      tester.getTopLeft(broadcast).dy,
      tester.getTopLeft(status).dy,
    ];
    final sorted = <double>[...dy]..sort();
    expect(dy, sorted, reason: 'rows must render in canonical order');
  });

  testWidgets('the status line names the port and the connected peers', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pump(
      tester,
      status: (running: true, port: 54323, problem: null),
    );
    final l10n = await L10N.delegate.load(const Locale('en'));

    await _openCxpSection(tester, l10n);

    expect(
      find.text('Running on port 54323, 0 peers connected'),
      findsOneWidget,
    );
  });

  testWidgets('the attention toggle is bound to the shared setting', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = await _pump(tester);
    final l10n = await L10N.delegate.load(const Locale('en'));

    await _openCxpSection(tester, l10n);

    final before = container.read(cruxCxpSettingsProvider).requestAttention;
    final toggle = find.byKey(const ValueKey('cxpSettingsAttention'));
    expect(toggle, findsOneWidget);

    await tester.tap(toggle);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      container.read(cruxCxpSettingsProvider).requestAttention,
      !before,
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('netcrux.requestAttentionOnCrossProbe'), !before);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the broadcast-selection toggle is bound to the shared setting', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = await _pump(tester);
    final l10n = await L10N.delegate.load(const Locale('en'));

    await _openCxpSection(tester, l10n);

    // Default is ON.
    final before = container.read(cruxCxpSettingsProvider).broadcastSelection;
    expect(before, isTrue);
    final toggle = find.byKey(const ValueKey('cxpSettingsBroadcast'));
    expect(toggle, findsOneWidget);

    await tester.tap(toggle);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      container.read(cruxCxpSettingsProvider).broadcastSelection,
      !before,
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('netcrux.broadcastSelectionOnCrossProbe'), !before);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an unrelated settings save leaves the CXP choices alone', (
    tester,
  ) async {
    // The product codec used to write all four CXP keys on every save, from
    // its own copy of them, undoing whatever the shared notifier had saved.
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = await _pump(tester);
    final l10n = await L10N.delegate.load(const Locale('en'));
    await _openCxpSection(tester, l10n);

    await tester.tap(find.byKey(const ValueKey('cxpSettingsBroadcast')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('netcrux.broadcastSelectionOnCrossProbe'), isFalse);

    await container
        .read(appSettingsProvider.notifier)
        .setAutoCheckForUpdates(enabled: false);

    expect(prefs.getBool('netcrux.autoCheckForUpdates'), isFalse);
    expect(prefs.getBool('netcrux.broadcastSelectionOnCrossProbe'), isFalse);
    expect(container.read(cruxCxpSettingsProvider).broadcastSelection, isFalse);
  });

  // The section is five stacked rows of label + control, and the labels are
  // the longest strings in Settings — the kind that wrap to two lines in CJK
  // and push a switch off its row. Additive: the assertions above pin the
  // canonical *order* in en and stay en-only, since order is what they test.
  for (final locale in L10N.supportedLocales) {
    testWidgets('opens without exceptions in ${locale.toLanguageTag()}', (
      tester,
    ) async {
      await _pump(tester, locale: locale);
      final l10n = await L10N.delegate.load(locale);
      await _openCxpSection(tester, l10n);

      expect(tester.takeException(), isNull);
      expect(find.text(l10n.settingsCxpSectionTitle), findsWidgets);
    });
  }
}
