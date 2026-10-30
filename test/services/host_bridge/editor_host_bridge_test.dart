// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:ui' show Brightness, Color;

import 'package:crux_settings/crux_settings.dart';
import 'package:crux_theme/crux_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/theme/editor_host_theme_synthesizer.dart';
import 'package:netcrux/domain/enums/editor_host_kind.dart';
import 'package:netcrux/domain/models/app_settings.dart';
import 'package:netcrux/domain/models/source_location.dart';
import 'package:netcrux/features/settings/providers/app_settings_provider.dart';
import 'package:netcrux/netcrux_color_theme_bootstrap.dart';
import 'package:netcrux/services/host_bridge/editor_host_providers.dart';
import 'package:netcrux/services/host_bridge/host_bridge_messages.dart';
import 'package:netcrux/services/host_bridge/host_netlist_request_provider.dart';
import 'package:netcrux/services/settings/netcrux_settings_codec.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_host_bridge_transport.dart';

Map<String, Object?> _open(String text) => <String, Object?>{
  'type': kHostBridgeFrameType,
  'protocol': 1,
  'kind': kHostBridgeOpenNetlistKind,
  'name': 'top.json',
  'text': text,
};

Map<String, Object?> _theme(String appearance, Map<String, String> tokens) =>
    <String, Object?>{
      'type': kHostBridgeFrameType,
      'protocol': 1,
      'kind': kHostBridgeThemeTokensKind,
      'appearance': appearance,
      'tokens': tokens,
    };

Future<({ProviderContainer container, FakeHostBridgeTransport channel})> _boot({
  FakeHostBridgeTransport? channel,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final fake = channel ?? FakeHostBridgeTransport();
  final container = ProviderContainer(
    overrides: [
      settingsServiceProvider.overrideWithValue(
        SettingsService<AppSettings>(
          const NetcruxSettingsCodec(),
          prefsOverride: prefs,
        ),
      ),
      netcruxCruxColorThemeOverride,
      hostBridgeChannelProvider.overrideWithValue(fake),
    ],
  );
  addTearDown(container.dispose);
  bindEditorHostTheme(container);
  await container.read(appSettingsProvider.future);
  return (container: container, channel: fake);
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  test('announces ready once its listener is installed', () async {
    final (:container, :channel) = await _boot();
    container.read(editorHostBridgeProvider);
    expect(channel.posted, <Map<String, Object?>>[hostBridgeReadyFrame()]);
  });

  test('installs nothing and says nothing without an editor host', () async {
    final (:container, :channel) = await _boot(
      channel: FakeHostBridgeTransport(hostKind: EditorHostKind.none),
    );
    container.read(editorHostBridgeProvider);
    channel.receive(_open('{"modules":{}}'));
    await _settle();
    expect(channel.posted, isEmpty);
    expect(container.read(hostNetlistRequestProvider), isNull);
  });

  test('queues a netlist for the workspace', () async {
    final (:container, :channel) = await _boot();
    container.read(editorHostBridgeProvider);
    channel.receive(_open('{"modules":{}}'));
    await _settle();
    final request = container.read(hostNetlistRequestProvider);
    expect(request?.netlist.name, 'top.json');
    expect(request?.netlist.text, '{"modules":{}}');
    container.read(hostNetlistRequestProvider.notifier).clear();
    expect(container.read(hostNetlistRequestProvider), isNull);
  });

  test('the same netlist sent twice notifies twice', () async {
    final (:container, :channel) = await _boot();
    container.read(editorHostBridgeProvider);
    final seen = <int>[];
    container.listen(
      hostNetlistRequestProvider,
      (_, next) => seen.add(next?.sequence ?? -1),
    );
    channel
      ..receive(_open('{"modules":{}}'))
      ..receive(_open('{"modules":{}}'));
    await _settle();
    expect(seen, <int>[1, 2]);
  });

  test('ignores a frame it cannot read', () async {
    final (:container, :channel) = await _boot();
    container.read(editorHostBridgeProvider);
    channel
      ..receive(<String, Object?>{'type': 'crux.netcrux'})
      ..receive(<String, Object?>{'kind': 'open_netlist'})
      ..receive(_open(''));
    await _settle();
    expect(container.read(hostNetlistRequestProvider), isNull);
  });

  group('theme', () {
    test('the editor colors replace the theme for the session only', () async {
      final (:container, :channel) = await _boot();
      container.read(editorHostBridgeProvider);
      channel.receive(
        _theme('light', <String, String>{'editor.background': '#fafafa'}),
      );
      await _settle();
      final theme = container.read(cruxColorThemeProvider);
      expect(theme.id, kEditorHostThemeId);
      expect(
        theme.color(chromeCategoryId, ChromeTokens.scaffoldBackground),
        const Color(0xFFFAFAFA),
      );
      // The persisted preset is untouched, so the standalone app comes back
      // exactly as the user left it.
      final settings = container.read(appSettingsProvider).requireValue;
      expect(settings.core.activeThemeName, isNot(kEditorHostThemeId));
      expect(settings.core.themeOverrides, isEmpty);
    });

    test('survives the settings notifier rebuilding the theme', () async {
      final (:container, :channel) = await _boot();
      container.read(editorHostBridgeProvider);
      channel.receive(_theme('dark', const <String, String>{}));
      await _settle();
      container.invalidate(appSettingsProvider);
      await container.read(appSettingsProvider.future);
      expect(container.read(cruxColorThemeProvider).id, kEditorHostThemeId);
    });

    test('follows a later change of the editor theme', () async {
      final (:container, :channel) = await _boot();
      container.read(editorHostBridgeProvider);
      channel.receive(_theme('dark', const <String, String>{}));
      await _settle();
      channel.receive(_theme('light', const <String, String>{}));
      await _settle();
      expect(
        container.read(cruxColorThemeProvider).brightness,
        Brightness.light,
      );
    });
  });

  group('outbound', () {
    test('openSource posts the file, line and column', () async {
      final (:container, :channel) = await _boot();
      container
          .read(editorHostBridgeProvider)
          .openSource(
            const SourceLocation(filePath: 'rtl/top.v', line: 14, column: 5),
          );
      expect(
        channel.posted.last,
        hostBridgeOpenSourceFrame(file: 'rtl/top.v', line: 14, column: 5),
      );
    });

    test('reportStatus posts the phase and the counts', () async {
      final (:container, :channel) = await _boot();
      container
          .read(editorHostBridgeProvider)
          .reportStatus(HostBridgeStatusPhase.loaded, modules: 3, cells: 40);
      expect(
        channel.posted.last,
        hostBridgeStatusFrame(
          HostBridgeStatusPhase.loaded,
          modules: 3,
          cells: 40,
        ),
      );
    });

    test('nothing is posted when the seam is absent', () async {
      final (:container, :channel) = await _boot(
        channel: FakeHostBridgeTransport(canPost: false),
      );
      container
          .read(editorHostBridgeProvider)
          .openSource(const SourceLocation(filePath: 'a.v', line: 1));
      expect(channel.posted, isEmpty);
    });
  });
}
