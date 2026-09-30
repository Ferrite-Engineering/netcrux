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

    test('recordRecentProject prepends and dedupes', () async {
      final container = await _makeContainer();
      addTearDown(container.dispose);
      final notifier = container.read(appSettingsProvider.notifier);

      await container.read(appSettingsProvider.future);
      await notifier.recordRecentProject('/p/a.netcrux');
      await notifier.recordRecentProject('/p/b.netcrux');
      await notifier.recordRecentProject('/p/a.netcrux');

      final state = container.read(appSettingsProvider).value!;
      expect(state.recentProjectPaths, ['/p/a.netcrux', '/p/b.netcrux']);
    });

    test('recordRecentSourceFiles preserves order across calls', () async {
      final container = await _makeContainer();
      addTearDown(container.dispose);
      final notifier = container.read(appSettingsProvider.notifier);

      await container.read(appSettingsProvider.future);
      await notifier.recordRecentSourceFiles(['top.v', 'cpu.sv']);
      await notifier.recordRecentSourceFiles(['top.v', 'mem.v']);

      final state = container.read(appSettingsProvider).value!;
      expect(state.recentSourceFilePaths, ['top.v', 'mem.v', 'cpu.sv']);
    });

    test('clearRecentFiles empties both lists', () async {
      final container = await _makeContainer();
      addTearDown(container.dispose);
      final notifier = container.read(appSettingsProvider.notifier);

      await container.read(appSettingsProvider.future);
      await notifier.recordRecentProject('/p/a.netcrux');
      await notifier.recordRecentSourceFiles(['/s/a.v']);
      await notifier.clearRecentFiles();

      final state = container.read(appSettingsProvider).value!;
      expect(state.recentProjectPaths, isEmpty);
      expect(state.recentSourceFilePaths, isEmpty);
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

    test('mutations enforce recentPathsLimit', () async {
      final container = await _makeContainer();
      addTearDown(container.dispose);
      final notifier = container.read(appSettingsProvider.notifier);

      await container.read(appSettingsProvider.future);
      for (var i = 0; i < AppSettings.recentPathsLimit + 4; i++) {
        await notifier.recordRecentProject('/p/$i.netcrux');
      }
      final state = container.read(appSettingsProvider).value!;
      expect(state.recentProjectPaths.length, AppSettings.recentPathsLimit);
      // The newest insertion sits at the top.
      expect(
        state.recentProjectPaths.first,
        '/p/${AppSettings.recentPathsLimit + 3}.netcrux',
      );
    });
  });
}
