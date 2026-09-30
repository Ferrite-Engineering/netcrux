// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/workspace/netcrux_tab_payload.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_codec.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_notifier.dart';
import 'package:netcrux/services/workspace/workspace_recovery_provider.dart';
import 'package:path/path.dart' as p;
import '../helpers/telemetry_test_overrides.dart';

/// End-to-end: a corrupt `workspace.json` on the launch path must yield a
/// clean default workspace, a quarantine file, a populated recovery notice,
/// and a real localized notice string in every shipped locale.
void main() {
  test(
    'corrupt workspace restore → empty + quarantine + localized notice',
    () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'netcrux-wsrecover-pipeline-',
      );
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      // 1. A user's workspace.json got truncated by a crash mid-write.
      File(
        p.join(tempDir.path, 'workspace.json'),
      ).writeAsStringSync('{"version": 1, "panes": [{"id": "trunc');

      // 2. Launch: the real workspace notifier loads from that directory.
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

      final workspace = await container.read(netcruxWorkspaceProvider.future);

      // 3. Launched clean, the bad file quarantined, the notice raised.
      expect(workspace.tabs, isEmpty);
      expect(
        File(p.join(tempDir.path, 'workspace.json')).existsSync(),
        isFalse,
      );
      final quarantined = tempDir
          .listSync()
          .whereType<File>()
          .where(
            (f) => p.basename(f.path).startsWith('workspace.json.corrupt-'),
          )
          .toList();
      expect(quarantined, hasLength(1));
      final recovery = container.read(workspaceRecoveryNoticeProvider);
      expect(recovery, isNotNull);

      // 4. The user-facing notice resolves to real text in every locale (the
      // ARB key the launch snackbar renders).
      for (final locale in L10N.supportedLocales) {
        final l10n = await L10N.delegate.load(locale);
        expect(
          l10n.workspaceRestoreCorrupted,
          isNotEmpty,
          reason: 'notice must be localized for $locale',
        );
      }
    },
  );
}
