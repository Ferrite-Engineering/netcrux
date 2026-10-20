// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_settings/crux_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/app_settings.dart';
import 'package:netcrux/domain/models/panel_layout_state.dart';
import 'package:netcrux/features/settings/providers/app_settings_provider.dart';
import 'package:netcrux/services/settings/netcrux_settings_codec.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _makeContainer() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: [
      settingsServiceProvider.overrideWithValue(
        SettingsService<AppSettings>(
          const NetcruxSettingsCodec(),
          prefsOverride: prefs,
        ),
      ),
    ],
  );
}

void main() {
  group('AppSettingsNotifier', () {
    test('loads defaults from an empty SharedPreferences', () async {
      final container = await _makeContainer();
      addTearDown(container.dispose);
      final settings = await container.read(appSettingsProvider.future);
      expect(settings, const AppSettings.defaults());
    });

    // The ordering, cap and removal rules are the shared Recent list's (see
    // recent_lists_test.dart); the notifier only stores what it is handed.
    test('the recent-list setters replace each list and persist it', () async {
      final container = await _makeContainer();
      addTearDown(container.dispose);
      final notifier = container.read(appSettingsProvider.notifier);

      await container.read(appSettingsProvider.future);
      await notifier.setRecentProjectPaths(['/p/b.netcrux', '/p/a.netcrux']);
      await notifier.setRecentSourceFilePaths(['top.v']);
      await notifier.setRecentWorkspacePaths(['/w/team.netcrux-workspace']);

      final state = container.read(appSettingsProvider).value!;
      expect(state.recentProjectPaths, ['/p/b.netcrux', '/p/a.netcrux']);
      expect(state.recentSourceFilePaths, ['top.v']);
      expect(state.recentWorkspacePaths, ['/w/team.netcrux-workspace']);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('netcrux.recentProjectPaths'), [
        '/p/b.netcrux',
        '/p/a.netcrux',
      ]);

      await notifier.setRecentProjectPaths(const []);
      expect(
        container.read(appSettingsProvider).value!.recentProjectPaths,
        isEmpty,
      );
    });

    test('updatePanelLayout persists the new layout', () async {
      final container = await _makeContainer();
      addTearDown(container.dispose);
      final notifier = container.read(appSettingsProvider.notifier);

      await container.read(appSettingsProvider.future);
      await notifier.updatePanelLayout(
        const PanelLayoutState(inspectorVisible: true),
      );

      final state = container.read(appSettingsProvider).value!;
      expect(state.panelLayout.inspectorVisible, isTrue);
    });

    test(
      'an unrelated change keeps the CXP keys a shared save wrote',
      () async {
        final container = await _makeContainer();
        addTearDown(container.dispose);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('netcrux.cxpServerEnabled', false);
        await prefs.setInt('netcrux.cxpServerPort', 60001);
        await prefs.setBool('netcrux.requestAttentionOnCrossProbe', false);
        await prefs.setBool('netcrux.broadcastSelectionOnCrossProbe', false);
        final notifier = container.read(appSettingsProvider.notifier);

        await container.read(appSettingsProvider.future);
        await notifier.setAutoCheckForUpdates(enabled: false);

        expect(prefs.getBool('netcrux.cxpServerEnabled'), isFalse);
        expect(prefs.getInt('netcrux.cxpServerPort'), 60001);
        expect(prefs.getBool('netcrux.requestAttentionOnCrossProbe'), isFalse);
        expect(
          prefs.getBool('netcrux.broadcastSelectionOnCrossProbe'),
          isFalse,
        );
      },
    );
  });
}
