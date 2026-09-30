// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_settings/crux_settings.dart';
import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/app_settings.dart';
import 'package:netcrux/domain/models/workspace/netcrux_tab_payload.dart';
import 'package:netcrux/features/settings/providers/app_settings_provider.dart';
import 'package:netcrux/services/settings/netcrux_settings_codec.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_codec.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_notifier.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/telemetry_test_overrides.dart';
import '../../helpers/wait_for.dart';

/// `NetcruxWorkspaceNotifier.shouldRestoreOnLaunch` — the launch gate in front
/// of `WorkspaceService.load`.
///
/// The shipped defect: `restoreTabsOnLaunch = false` restored the tabs anyway,
/// because nothing consulted the preference. The gate has to run *before* the
/// load (closing restored tabs after the fact has already paid for the load
/// and already emitted a scope reconcile), and declining has to leave the
/// document on disk so flipping the preference back on brings the session
/// back.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('netcrux_restore_gate_test_');
  });

  tearDown(() => bestEffortDeleteTempDir(tmp));

  // Captured by value: a fire-and-forget auto-save still in flight when a test
  // ends must not land in the next test's freshly-created temp directory.
  WorkspaceService<NetcruxTabPayload> makeWorkspaceService() {
    final dir = tmp;
    return WorkspaceService<NetcruxTabPayload>(
      codec: const NetcruxWorkspaceCodec(),
      directoryFactory: () async => dir,
      logger: (_) {},
    );
  }

  /// Builds a container whose workspace notifier is backed by [tmp] and whose
  /// settings service is [settings] (omit to leave the production provider in
  /// place, which has no platform channel under test).
  ProviderContainer makeContainer({SettingsService<AppSettings>? settings}) {
    return ProviderContainer(
      overrides: [
        ...netcruxTelemetryTestOverrides(),
        if (settings != null)
          settingsServiceProvider.overrideWithValue(settings),
        netcruxWorkspaceProvider.overrideWith(
          () => NetcruxWorkspaceNotifier(
            service: makeWorkspaceService(),
            autoSaveDebounce: Duration.zero,
          ),
        ),
      ],
    );
  }

  Future<SettingsService<AppSettings>> settingsService({
    required bool restoreTabs,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final service = SettingsService<AppSettings>(
      const NetcruxSettingsCodec(),
      prefsOverride: prefs,
    );
    await service.save(
      const AppSettings.defaults().copyWith(
        core: const CoreSettings.defaults().copyWith(
          restoreTabsOnLaunch: restoreTabs,
        ),
      ),
    );
    return service;
  }

  /// Persists a one-tab workspace to [tmp] and returns the file.
  Future<File> seedPersistedWorkspace() async {
    final container = makeContainer(
      settings: await settingsService(restoreTabs: true),
    );
    await container.read(netcruxWorkspaceProvider.future);
    await container
        .read(netcruxWorkspaceProvider.notifier)
        .openTab(
          displayName: 'cpu',
          payload: const NetcruxTabPayload(sourceFiles: ['/d/cpu.v']),
        );
    await container.read(netcruxWorkspaceProvider.notifier).flushPendingSave();
    container.dispose();
    final file = File('${tmp.path}/workspace.json');
    expect(file.existsSync(), isTrue);
    return file;
  }

  test('restores the persisted tabs when the preference is on', () async {
    await seedPersistedWorkspace();

    final container = makeContainer(
      settings: await settingsService(restoreTabs: true),
    );
    addTearDown(container.dispose);

    final ws = await container.read(netcruxWorkspaceProvider.future);
    expect(ws.tabs, hasLength(1));
    expect(ws.tabs.single.payload.sourceFiles, ['/d/cpu.v']);
  });

  test('declines the restore when the preference is off', () async {
    await seedPersistedWorkspace();

    final container = makeContainer(
      settings: await settingsService(restoreTabs: false),
    );
    addTearDown(container.dispose);

    final ws = await container.read(netcruxWorkspaceProvider.future);
    expect(ws.tabs, isEmpty);
    expect(ws.panes, hasLength(1));
  });

  test('declining leaves the document on disk, so it can come back', () async {
    final file = await seedPersistedWorkspace();
    final before = file.readAsStringSync();

    final declined = makeContainer(
      settings: await settingsService(restoreTabs: false),
    );
    expect(
      (await declined.read(netcruxWorkspaceProvider.future)).tabs,
      isEmpty,
    );
    declined.dispose();

    expect(file.existsSync(), isTrue);
    expect(file.readAsStringSync(), before);

    // Preference flipped back on: the session that was there returns.
    final restored = makeContainer(
      settings: await settingsService(restoreTabs: true),
    );
    addTearDown(restored.dispose);
    final ws = await restored.read(netcruxWorkspaceProvider.future);
    expect(ws.tabs, hasLength(1));
    expect(ws.tabs.single.payload.sourceFiles, ['/d/cpu.v']);
  });

  test(
    'an unreadable settings store defaults to restoring, and resolves',
    () async {
      // A settings load that throws — no platform channel under a widget
      // test, a plugin that has not registered yet — must not cost the user
      // their session, and must not hang the launch. Awaiting an async
      // *provider* here instead of the service would leave this future
      // pending across every Riverpod retry and the app would never render.
      await seedPersistedWorkspace();

      final container = makeContainer(
        settings: const SettingsService<AppSettings>(_ThrowingSettingsCodec()),
      );
      addTearDown(container.dispose);

      final ws = await container
          .read(netcruxWorkspaceProvider.future)
          .timeout(const Duration(seconds: 5));
      expect(ws.tabs, hasLength(1));
    },
  );
}

/// Settings codec whose load always fails, standing in for an unavailable
/// preferences backend.
class _ThrowingSettingsCodec implements SettingsCodec<AppSettings> {
  const _ThrowingSettingsCodec();

  @override
  Future<AppSettings> load(SharedPreferences prefs) async {
    throw StateError('settings backend unavailable');
  }

  @override
  Future<void> save(SharedPreferences prefs, AppSettings settings) async {}
}
