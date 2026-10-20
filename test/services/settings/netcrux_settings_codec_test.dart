// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_settings/crux_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/enums/yosys_path_mode.dart';
import 'package:netcrux/domain/models/app_settings.dart';
import 'package:netcrux/domain/models/panel_layout_state.dart';
import 'package:netcrux/services/settings/netcrux_settings_codec.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SharedPreferences prefs;
  const codec = NetcruxSettingsCodec();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
  });

  group('NetcruxSettingsCodec', () {
    test('load returns defaults when prefs are empty', () async {
      final settings = await codec.load(prefs);
      expect(settings, const AppSettings.defaults());
    });

    test('round-trips recent files lists', () async {
      const seeded = AppSettings(
        core: CoreSettings.defaults(),
        recentProjectPaths: ['/a/demo.netcrux', '/b/other.netcrux'],
        recentSourceFilePaths: ['/c/top.v', '/d/cpu.sv'],
        recentWorkspacePaths: ['/e/team.netcrux-workspace'],
        yosysPathMode: YosysPathMode.autoDetect,
        yosysCustomPath: '',
      );
      await codec.save(prefs, seeded);
      final loaded = await codec.load(prefs);
      expect(loaded.recentProjectPaths, seeded.recentProjectPaths);
      expect(loaded.recentSourceFilePaths, seeded.recentSourceFilePaths);
      expect(loaded.recentWorkspacePaths, seeded.recentWorkspacePaths);
    });

    test('round-trips the restore-tabs-on-launch flag', () async {
      // The flag lives on CoreSettings, so this asserts the delegation to
      // CoreSettingsCodec still carries it — and that the suite-shared key
      // `settings.restoreTabsOnLaunch` is the one written, which is the key a
      // user reaches with `defaults write`.
      final seeded = const AppSettings.defaults().copyWith(
        core: const CoreSettings.defaults().copyWith(
          restoreTabsOnLaunch: false,
        ),
      );
      await codec.save(prefs, seeded);
      expect(prefs.getBool('settings.restoreTabsOnLaunch'), isFalse);
      expect((await codec.load(prefs)).restoreTabsOnLaunch, isFalse);

      await codec.save(
        prefs,
        seeded.copyWith(
          core: const CoreSettings.defaults().copyWith(
            restoreTabsOnLaunch: true,
          ),
        ),
      );
      expect((await codec.load(prefs)).restoreTabsOnLaunch, isTrue);
    });

    test('restore-tabs-on-launch defaults to on', () async {
      expect((await codec.load(prefs)).restoreTabsOnLaunch, isTrue);
    });

    test('round-trips the automatic update-check flag', () async {
      final seeded = const AppSettings.defaults().copyWith(
        autoCheckForUpdates: false,
      );
      await codec.save(prefs, seeded);
      expect((await codec.load(prefs)).autoCheckForUpdates, isFalse);

      await codec.save(prefs, seeded.copyWith(autoCheckForUpdates: true));
      expect((await codec.load(prefs)).autoCheckForUpdates, isTrue);
    });

    test('a missing update-check key loads as enabled', () async {
      // Forward/backward compatibility: a preferences file written by a build
      // predating the setting must not silently disable the update check.
      await prefs.remove('netcrux.autoCheckForUpdates');
      expect((await codec.load(prefs)).autoCheckForUpdates, isTrue);
    });

    test('round-trips Yosys path knobs', () async {
      final seeded = const AppSettings.defaults().copyWith(
        yosysPathMode: YosysPathMode.custom,
        yosysCustomPath: '/opt/yosys/bin/yosys',
      );
      await codec.save(prefs, seeded);
      final loaded = await codec.load(prefs);
      expect(loaded.yosysPathMode, YosysPathMode.custom);
      expect(loaded.yosysCustomPath, '/opt/yosys/bin/yosys');
    });

    test('unknown yosys mode names fall back to autoDetect', () async {
      await prefs.setString('netcrux.yosysPathMode', 'futureMode');
      final loaded = await codec.load(prefs);
      expect(loaded.yosysPathMode, YosysPathMode.autoDetect);
    });

    test('round-trips composed CoreSettings fields', () async {
      final seeded = const AppSettings.defaults().copyWith(
        core: const CoreSettings.defaults().copyWith(
          activeThemeName: 'solarized-dark',
          autoSaveIntervalSeconds: 120,
        ),
      );
      await codec.save(prefs, seeded);
      final loaded = await codec.load(prefs);
      expect(loaded.core.activeThemeName, 'solarized-dark');
      expect(loaded.core.autoSaveIntervalSeconds, 120);
    });

    test('round-trips the CXP editor command', () async {
      final seeded = const AppSettings.defaults().copyWith(
        cxpEditorCommand: 'subl {file}:{line}',
      );
      await codec.save(prefs, seeded);
      final loaded = await codec.load(prefs);
      expect(loaded.cxpEditorCommand, 'subl {file}:{line}');
    });

    test('the CXP editor command defaults when prefs are empty', () async {
      final loaded = await codec.load(prefs);
      expect(loaded.cxpEditorCommand, AppSettings.defaultCxpEditorCommand);
    });

    // The four CXP settings belong to the shared lifecycle's codec. Writing
    // them here too would overwrite a choice it saved with whatever an
    // AppSettings snapshot last held.
    test('never reads or writes the four shared CXP keys', () async {
      const keys = <String>[
        'netcrux.cxpServerEnabled',
        'netcrux.cxpServerPort',
        'netcrux.requestAttentionOnCrossProbe',
        'netcrux.broadcastSelectionOnCrossProbe',
      ];
      await prefs.setBool('netcrux.cxpServerEnabled', false);
      await prefs.setInt('netcrux.cxpServerPort', 64321);
      await prefs.setBool('netcrux.requestAttentionOnCrossProbe', false);
      await prefs.setBool('netcrux.broadcastSelectionOnCrossProbe', false);

      await codec.save(prefs, await codec.load(prefs));

      expect(prefs.getBool(keys[0]), isFalse);
      expect(prefs.getInt(keys[1]), 64321);
      expect(prefs.getBool(keys[2]), isFalse);
      expect(prefs.getBool(keys[3]), isFalse);

      await prefs.clear();
      await codec.save(prefs, const AppSettings.defaults());
      for (final key in keys) {
        expect(prefs.containsKey(key), isFalse, reason: '$key written');
      }
    });

    test(
      'trims recent lists to AppSettings.recentPathsLimit on load',
      () async {
        final tooMany = List<String>.generate(
          AppSettings.recentPathsLimit + 4,
          (i) => '/path/$i.netcrux',
        );
        await prefs.setStringList('netcrux.recentProjectPaths', tooMany);
        final loaded = await codec.load(prefs);
        expect(loaded.recentProjectPaths.length, AppSettings.recentPathsLimit);
        expect(loaded.recentProjectPaths.first, tooMany.first);
      },
    );

    test('panel layout defaults when prefs are empty', () async {
      final loaded = await codec.load(prefs);
      expect(loaded.panelLayout, const PanelLayoutState());
    });

    test('round-trips panel-layout visibility and sizes', () async {
      final seeded = const AppSettings.defaults().copyWith(
        panelLayout: const PanelLayoutState(
          hierarchyTreeVisible: false,
          inspectorVisible: true,
          diagnosticsVisible: true,
          hierarchyTreeWidth: 280,
          inspectorWidth: 320,
          diagnosticsHeight: 220,
        ),
      );
      await codec.save(prefs, seeded);
      final loaded = await codec.load(prefs);
      expect(loaded.panelLayout, seeded.panelLayout);
    });

    test(
      'null panel sizes are removed, not persisted as stale values',
      () async {
        // Save a sized layout, then save one with null sizes — the keys must
        // be cleared so the reload falls back to "use the panes default".
        await codec.save(
          prefs,
          const AppSettings.defaults().copyWith(
            panelLayout: const PanelLayoutState(hierarchyTreeWidth: 280),
          ),
        );
        await codec.save(
          prefs,
          const AppSettings.defaults().copyWith(
            panelLayout: const PanelLayoutState(),
          ),
        );
        final loaded = await codec.load(prefs);
        expect(loaded.panelLayout.hierarchyTreeWidth, isNull);
      },
    );
  });
}
