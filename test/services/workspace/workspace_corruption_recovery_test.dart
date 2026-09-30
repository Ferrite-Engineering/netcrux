// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/workspace/netcrux_tab_payload.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_codec.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_notifier.dart';
import 'package:netcrux/services/workspace/workspace_recovery_provider.dart';
import 'package:path/path.dart' as p;
import '../../helpers/telemetry_test_overrides.dart';

/// A corrupt `workspace.json` on launch must recover to an empty
/// workspace, quarantine the bad file, and surface a recovery notice — never
/// brick launch.
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('netcrux-wsrecover-');
  });
  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  ProviderContainer containerFor() {
    final service = WorkspaceService<NetcruxTabPayload>(
      codec: const NetcruxWorkspaceCodec(),
      directoryFactory: () async => tempDir,
    );
    final container = ProviderContainer(
      overrides: [
        ...netcruxTelemetryTestOverrides(),
        netcruxWorkspaceProvider.overrideWith(
          () => NetcruxWorkspaceNotifier(
            service: service,
            autoSaveDebounce: Duration.zero,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  File? quarantineFile() {
    const prefix = 'workspace.json.corrupt-';
    final matches = tempDir
        .listSync()
        .whereType<File>()
        .where((f) => p.basename(f.path).startsWith(prefix))
        .toList();
    return matches.isEmpty ? null : matches.first;
  }

  void writeWorkspace(String contents) {
    File(p.join(tempDir.path, 'workspace.json')).writeAsStringSync(contents);
  }

  for (final variant in <({String label, String body})>[
    (label: 'truncated', body: '{"version": 1, "panes": [{"id":'),
    (label: 'garbage', body: 'not json at all <<>>'),
    (label: 'non-object root', body: '[1, 2, 3]'),
    (
      label: 'version-skewed',
      body: jsonEncode({
        'version': 9999,
        'panes': [
          {'id': '11111111-1111-1111-1111-111111111111'},
        ],
        'activePaneId': '11111111-1111-1111-1111-111111111111',
      }),
    ),
  ]) {
    test(
      '${variant.label} workspace.json → empty + quarantine + notice',
      () async {
        writeWorkspace(variant.body);
        final container = containerFor();

        final workspace = await container.read(netcruxWorkspaceProvider.future);
        // Launched into a clean default workspace, not a crash.
        expect(workspace.tabs, isEmpty);
        // The corrupt file was moved aside (preserved for manual recovery).
        expect(
          File(p.join(tempDir.path, 'workspace.json')).existsSync(),
          isFalse,
        );
        final quarantined = quarantineFile();
        expect(quarantined, isNotNull, reason: 'a .corrupt-* file must exist');
        expect(quarantined!.readAsStringSync(), variant.body);
        // The recovery notice is surfaced for the launch UI.
        expect(container.read(workspaceRecoveryNoticeProvider), isNotNull);
      },
    );
  }

  test('a healthy workspace.json restores with no recovery notice', () async {
    // Write a genuinely valid document by saving through the service, then
    // assert a fresh launch restores it without quarantine.
    await WorkspaceService<NetcruxTabPayload>(
      codec: const NetcruxWorkspaceCodec(),
      directoryFactory: () async => tempDir,
    ).save(Workspace<NetcruxTabPayload>.empty());
    final container = containerFor();
    await container.read(netcruxWorkspaceProvider.future);
    expect(quarantineFile(), isNull);
    expect(container.read(workspaceRecoveryNoticeProvider), isNull);
  });

  test('a missing workspace.json records no recovery', () async {
    final container = containerFor();
    await container.read(netcruxWorkspaceProvider.future);
    expect(quarantineFile(), isNull);
    expect(container.read(workspaceRecoveryNoticeProvider), isNull);
  });

  test('acknowledge() clears the recovery notice', () async {
    writeWorkspace('garbage');
    final container = containerFor();
    await container.read(netcruxWorkspaceProvider.future);
    expect(container.read(workspaceRecoveryNoticeProvider), isNotNull);
    container.read(workspaceRecoveryNoticeProvider.notifier).acknowledge();
    expect(container.read(workspaceRecoveryNoticeProvider), isNull);
  });
}
