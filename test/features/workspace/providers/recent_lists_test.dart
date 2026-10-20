// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_settings/crux_settings.dart';
import 'package:crux_workspace/crux_workspace.dart' show CruxRecentOpenResult;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/app_settings.dart';
import 'package:netcrux/features/settings/providers/app_settings_provider.dart';
import 'package:netcrux/features/workspace/providers/recent_lists.dart';
import 'package:netcrux/services/settings/netcrux_settings_codec.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The three Recent lists live inside `AppSettings` under string-list keys an
/// earlier release wrote. The ordering, the cap and the removal rules are the
/// shared list's; what is pinned here is that NetCrux's store reads the old
/// keys as they are and saves through the settings.
void main() {
  late SharedPreferences prefs;

  Future<ProviderContainer> boot(Map<String, Object> saved) async {
    SharedPreferences.setMockInitialValues(saved);
    prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        settingsServiceProvider.overrideWithValue(
          SettingsService<AppSettings>(
            const NetcruxSettingsCodec(),
            prefsOverride: prefs,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<void> restored(ProviderContainer c) async {
    await c.read(recentProjects.provider.notifier).restored;
    await c.read(recentSources.provider.notifier).restored;
    await c.read(recentWorkspaces.provider.notifier).restored;
  }

  test('a list saved by an earlier release is read as it is', () async {
    final c = await boot(<String, Object>{
      'netcrux.recentProjectPaths': <String>['/p/b.netcrux', '/p/a.netcrux'],
      'netcrux.recentSourceFilePaths': <String>['/s/top.v'],
      'netcrux.recentWorkspacePaths': <String>['/w/team.netcrux-workspace'],
    });

    await restored(c);

    expect(c.read(recentProjects.provider), ['/p/b.netcrux', '/p/a.netcrux']);
    expect(c.read(recentSources.provider), ['/s/top.v']);
    expect(c.read(recentWorkspaces.provider), ['/w/team.netcrux-workspace']);
  });

  test('an open is saved through the settings, under the same key', () async {
    final c = await boot(<String, Object>{
      'netcrux.recentProjectPaths': <String>['/p/old.netcrux'],
    });
    await restored(c);

    c.read(recentProjects.provider.notifier).markOpened('/p/new.netcrux');
    await pumpEventQueue();

    expect(c.read(recentProjects.provider), [
      '/p/new.netcrux',
      '/p/old.netcrux',
    ]);
    expect(c.read(appSettingsProvider).value!.recentProjectPaths, [
      '/p/new.netcrux',
      '/p/old.netcrux',
    ]);
    expect(prefs.getStringList('netcrux.recentProjectPaths'), [
      '/p/new.netcrux',
      '/p/old.netcrux',
    ]);
  });

  test('the lists are independent of one another', () async {
    final c = await boot(<String, Object>{});
    await restored(c);

    c.read(recentSources.provider.notifier).markOpened('/s/top.v');
    await pumpEventQueue();

    expect(prefs.getStringList('netcrux.recentSourceFilePaths'), ['/s/top.v']);
    expect(prefs.getStringList('netcrux.recentProjectPaths'), isEmpty);
    expect(prefs.getStringList('netcrux.recentWorkspacePaths'), isEmpty);
  });

  test('a re-opened entry moves to the front and the list is capped', () async {
    final c = await boot(<String, Object>{});
    await restored(c);
    final notifier = c.read(recentProjects.provider.notifier);

    for (var i = 0; i < AppSettings.recentPathsLimit + 4; i++) {
      notifier.markOpened('/p/$i.netcrux');
    }
    notifier.markOpened('/p/${AppSettings.recentPathsLimit + 1}.netcrux');
    await pumpEventQueue();

    final list = c.read(recentProjects.provider);
    expect(list, hasLength(AppSettings.recentPathsLimit));
    expect(list.first, '/p/${AppSettings.recentPathsLimit + 1}.netcrux');
    expect(list.toSet(), hasLength(list.length), reason: 'no duplicates');
  });

  test('remove and clear are saved', () async {
    final c = await boot(<String, Object>{
      'netcrux.recentProjectPaths': <String>['/p/b.netcrux', '/p/a.netcrux'],
    });
    await restored(c);
    final notifier = c.read(recentProjects.provider.notifier)
      ..remove('/p/b.netcrux');
    await pumpEventQueue();
    expect(prefs.getStringList('netcrux.recentProjectPaths'), ['/p/a.netcrux']);

    notifier.clear();
    await pumpEventQueue();
    expect(prefs.getStringList('netcrux.recentProjectPaths'), isEmpty);
    expect(c.read(appSettingsProvider).value!.recentProjectPaths, isEmpty);
  });

  test(
    'an entry that does not open is dropped, one that opens moves up',
    () async {
      final c = await boot(<String, Object>{
        'netcrux.recentProjectPaths': <String>[
          '/p/gone.netcrux',
          '/p/ok.netcrux',
        ],
      });
      await restored(c);
      final notifier = c.read(recentProjects.provider.notifier);

      final gone = await notifier.open('/p/gone.netcrux', (_) async => false);
      final ok = await notifier.open('/p/ok.netcrux', (_) async => true);

      expect(gone, CruxRecentOpenResult.removed);
      expect(ok, CruxRecentOpenResult.opened);
      expect(c.read(recentProjects.provider), ['/p/ok.netcrux']);
    },
  );
}
