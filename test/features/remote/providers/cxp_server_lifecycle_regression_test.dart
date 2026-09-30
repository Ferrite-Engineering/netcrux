// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/app_settings.dart';
import 'package:netcrux/features/remote/providers/cxp_server_provider.dart';
import 'package:netcrux/features/settings/providers/app_settings_provider.dart';
import 'package:path/path.dart' as p;

/// In-memory [AppSettingsNotifier] whose value the test drives directly via
/// [put], bypassing the persistent [SettingsService]. Lets a test mutate one
/// field at a time and observe whether [CxpServerHost] rebuilds.
class _FakeAppSettings extends AppSettingsNotifier {
  _FakeAppSettings(this._value);

  AppSettings _value;

  @override
  Future<AppSettings> build() async => _value;

  void put(AppSettings next) {
    _value = next;
    state = AsyncData(next);
  }
}

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('netcrux_cxp_prov_');
  });
  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } on FileSystemException {
      // best effort
    }
  });

  // Port 0 so each server binds an ephemeral port and never collides with a
  // real running NetCrux (or another test) on the fixed 54323.
  AppSettings initialSettings() => const AppSettings.defaults().copyWith(
    cxpServerEnabled: true,
    cxpServerPort: 0,
  );

  ({ProviderContainer container, _FakeAppSettings settings}) boot(
    AppSettings initial,
  ) {
    final fake = _FakeAppSettings(initial);
    final container = ProviderContainer(
      overrides: [
        appSettingsProvider.overrideWith(() => fake),
        cxpManifestDirectoryProvider.overrideWith(
          (ref) async => p.join(tmp.path, 'peers'),
        ),
      ],
    );
    addTearDown(container.dispose);
    return (container: container, settings: fake);
  }

  int netcruxManifestCount() {
    final dir = Directory(p.join(tmp.path, 'peers'));
    if (!dir.existsSync()) return 0;
    return dir
        .listSync()
        .whereType<File>()
        .where((f) => p.basename(f.path).startsWith('netcrux-'))
        .where((f) => f.path.endsWith('.json'))
        .length;
  }

  /// Waits, bounded, for the manifest directory to hold [expected] files.
  ///
  /// The writes and deletions behind these counts are real asynchronous file
  /// operations, and the server does not await them on the caller's behalf:
  /// tearing a server down asks the writer to unpublish and returns. A single
  /// event-loop turn is usually enough and, on a loaded machine, sometimes is
  /// not — which is how this file failed once in a full local run and passed
  /// alone three times. Polling states the wait instead of assuming it.
  Future<void> expectManifestCount(int expected) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (netcruxManifestCount() != expected &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(
      netcruxManifestCount(),
      expected,
      reason: 'the manifest directory never settled at $expected file(s)',
    );
  }

  test('starting the host publishes exactly one manifest and runs', () async {
    final (:container, :settings) = boot(initialSettings());

    final server = await container.read(cxpServerHostProvider.future);
    expect(server, isNotNull);
    expect(server!.isRunning, isTrue);
    expect(server.boundPort, isNotNull);
    await expectManifestCount(1);
  });

  test(
    'an UNRELATED settings change never rebuilds the server, and repeated '
    'warm reads reuse the same instance (warm idempotency)',
    () async {
      final (:container, :settings) = boot(initialSettings());

      final server1 = await container.read(cxpServerHostProvider.future);
      expect(server1, isNotNull);
      await expectManifestCount(1);
      final peerId1 = server1!.selfIdentity!.peerId;

      // Churn a series of settings that are NOT (cxpServerEnabled,
      // cxpServerPort): the exact kind of writes (panel-layout drags,
      // broadcast toggle, recent-files) that used to tear the server down and
      // recreate it, orphaning a dialing connector on every rebuild.
      for (var i = 0; i < 5; i++) {
        final current = settings._value;
        settings.put(
          current.copyWith(
            broadcastSelectionOnCrossProbe:
                !current.broadcastSelectionOnCrossProbe,
            cxpEditorCommand: 'editor-$i {file}:{line}',
          ),
        );
        // Let the notifier's emission propagate, then WARM the host again the
        // way the schematic-mount watcher does.
        await Future<void>(() {});
        final server2 = await container.read(cxpServerHostProvider.future);
        expect(
          identical(server1, server2),
          isTrue,
          reason: 'unrelated settings churn must not rebuild the CXP server',
        );
        expect(server2!.isRunning, isTrue, reason: 'server stays up');
        expect(
          server2.selfIdentity!.peerId,
          peerId1,
          reason: 'a rebuild would mint a new peerId',
        );
        await expectManifestCount(1);
      }
    },
  );

  test(
    'disabling CXP tears the running server DOWN (rebuild only on the '
    'relevant setting) and removes its manifest',
    () async {
      final (:container, :settings) = boot(initialSettings());

      final server = await container.read(cxpServerHostProvider.future);
      expect(server, isNotNull);
      await expectManifestCount(1);

      settings.put(settings._value.copyWith(cxpServerEnabled: false));
      await Future<void>(() {});

      final disabled = await container.read(cxpServerHostProvider.future);
      expect(disabled, isNull, reason: 'disabling stops the server');
      expect(
        server!.isRunning,
        isFalse,
        reason: 'the previously-running server was stopped, not orphaned',
      );
      // The torn-down server unpublished its manifest.
      await expectManifestCount(0);
    },
  );

  test('changing the bind port rebuilds onto a fresh server', () async {
    // Reserve a free port, then release it so the host can bind it.
    final probe = await ServerSocket.bind('127.0.0.1', 0);
    final freePort = probe.port;
    await probe.close();

    final (:container, :settings) = boot(initialSettings());
    final server1 = await container.read(cxpServerHostProvider.future);
    expect(server1, isNotNull);
    final peerId1 = server1!.selfIdentity!.peerId;

    settings.put(settings._value.copyWith(cxpServerPort: freePort));
    await Future<void>(() {});

    final server2 = await container.read(cxpServerHostProvider.future);
    expect(server2, isNotNull);
    expect(
      identical(server1, server2),
      isFalse,
      reason: 'a port change must rebuild the server',
    );
    expect(server2!.selfIdentity!.peerId, isNot(peerId1));
    expect(
      server1.isRunning,
      isFalse,
      reason: 'the old server was stopped when the port changed',
    );
    // The rebuilt server republished; the old one's manifest is gone.
    await expectManifestCount(1);
  });
}
