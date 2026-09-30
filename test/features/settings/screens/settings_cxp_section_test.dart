// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The Settings → CXP Cross-Probe section must match the WaveCrux canonical
// layout: (1) Enable CXP server, (2) CXP port, (3) Request attention on
// cross-probe, (4) Broadcast selection automatically, (5) CXP Status — in that
// order — and the attention / broadcast toggles must be bound to
// `AppSettings.requestAttentionOnCrossProbe` /
// `AppSettings.broadcastSelectionOnCrossProbe` respectively.

import 'package:crux_settings/crux_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/app_settings.dart';
import 'package:netcrux/features/remote/providers/cxp_server_provider.dart';
import 'package:netcrux/features/settings/providers/app_settings_provider.dart';
import 'package:netcrux/features/settings/screens/settings_screen.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/remote/cxp/netcrux_cxp_server.dart';
import 'package:netcrux/services/settings/netcrux_settings_codec.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A CXP host that reports "stopped" without touching sockets, the manifest
/// writer, or path_provider — so the status line renders deterministically.
class _NullCxpServerHost extends CxpServerHost {
  @override
  Future<NetcruxCxpServer?> build() async => null;
}

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  Locale locale = const Locale('en'),
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
      cxpServerHostProvider.overrideWith(_NullCxpServerHost.new),
      cxpPeersProvider.overrideWith(
        (ref) => Stream<List<CxpPeerEntry>>.value(const <CxpPeerEntry>[]),
      ),
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

AppSettings _settings(ProviderContainer c) =>
    c.read(appSettingsProvider).value ?? const AppSettings.defaults();

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('renders all canonical rows in order', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pump(tester);
    final l10n = await L10N.delegate.load(const Locale('en'));

    await _openCxpSection(tester, l10n);

    // Each canonical row is present exactly once in the detail pane.
    final enable = find.text(l10n.settingsCxpEnabledLabel);
    final port = find.text(l10n.settingsCxpPortDescription);
    final attention = find.text(l10n.settingsRequestAttentionOnCrossProbeLabel);
    final broadcast = find.text(
      l10n.settingsBroadcastSelectionOnCrossProbeLabel,
    );
    final status = find.text(l10n.settingsCxpStatus);
    expect(enable, findsOneWidget);
    expect(port, findsOneWidget);
    expect(attention, findsOneWidget);
    expect(broadcast, findsOneWidget);
    expect(status, findsOneWidget);

    // Server is stopped (null host) → the status shows "Stopped".
    expect(find.text(l10n.settingsCxpStatusStopped), findsOneWidget);

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

  testWidgets('the attention toggle is bound to the setting', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = await _pump(tester);
    final l10n = await L10N.delegate.load(const Locale('en'));

    await _openCxpSection(tester, l10n);

    final before = _settings(container).requestAttentionOnCrossProbe;
    // The suite-shared CruxCxpSettingsControls owns the switch keys now.
    final toggle = find.byKey(const ValueKey('cxpSettingsAttention'));
    expect(toggle, findsOneWidget);

    await tester.tap(toggle);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(_settings(container).requestAttentionOnCrossProbe, !before);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the broadcast-selection toggle is bound to the setting', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = await _pump(tester);
    final l10n = await L10N.delegate.load(const Locale('en'));

    await _openCxpSection(tester, l10n);

    // Default is ON.
    final before = _settings(container).broadcastSelectionOnCrossProbe;
    expect(before, isTrue);
    // The suite-shared CruxCxpSettingsControls owns the switch keys now.
    final toggle = find.byKey(const ValueKey('cxpSettingsBroadcast'));
    expect(toggle, findsOneWidget);

    await tester.tap(toggle);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(_settings(container).broadcastSelectionOnCrossProbe, !before);
    expect(tester.takeException(), isNull);
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
