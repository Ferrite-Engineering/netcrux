// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/workspace/netcrux_tab_payload.dart';
import 'package:netcrux/services/workspace/active_project_file_path_provider.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_codec.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_notifier.dart';

import '../../helpers/telemetry_test_overrides.dart';
import '../../helpers/wait_for.dart';

ProviderContainer _buildContainer(Directory dir) {
  return ProviderContainer(
    overrides: <Override>[
      ...netcruxTelemetryTestOverrides(),
      netcruxWorkspaceProvider.overrideWith(
        () => NetcruxWorkspaceNotifier(
          service: WorkspaceService<NetcruxTabPayload>(
            codec: const NetcruxWorkspaceCodec(),
            directoryFactory: () async => dir,
            logger: (_) {},
          ),
          autoSaveDebounce: const Duration(milliseconds: 20),
        ),
      ),
    ],
  );
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('netcrux-active-proj-');
  });

  tearDown(() => bestEffortDeleteTempDir(tempDir));

  group('activeProjectFilePathProvider', () {
    test('returns null before the workspace finishes loading', () {
      final container = _buildContainer(tempDir);
      addTearDown(container.dispose);
      // Read before awaiting the AsyncNotifier — should yield null.
      expect(container.read(activeProjectFilePathProvider), isNull);
    });

    test('returns null when no tab is active (empty workspace)', () async {
      final container = _buildContainer(tempDir);
      addTearDown(container.dispose);
      await container.read(netcruxWorkspaceProvider.future);
      expect(container.read(activeProjectFilePathProvider), isNull);
    });

    test(
      'returns the active tab payload projectFilePath when present',
      () async {
        final container = _buildContainer(tempDir);
        addTearDown(container.dispose);
        await container.read(netcruxWorkspaceProvider.future);
        final notifier = container.read(netcruxWorkspaceProvider.notifier);
        await notifier.openTab(
          displayName: 'demo',
          payload: const NetcruxTabPayload(
            sourceFiles: <String>['/proj/foo.v'],
            projectFilePath: '/proj/demo.netcrux-project',
          ),
        );
        expect(
          container.read(activeProjectFilePathProvider),
          '/proj/demo.netcrux-project',
        );
      },
    );

    test(
      'returns null when active tab has no projectFilePath',
      () async {
        final container = _buildContainer(tempDir);
        addTearDown(container.dispose);
        await container.read(netcruxWorkspaceProvider.future);
        final notifier = container.read(netcruxWorkspaceProvider.notifier);
        await notifier.openTab(
          displayName: 'raw',
          payload: const NetcruxTabPayload(
            sourceFiles: <String>['/scratch/raw.v'],
          ),
        );
        expect(container.read(activeProjectFilePathProvider), isNull);
      },
    );

    test(
      'emits new value when active tab changes between two projects',
      () async {
        final container = _buildContainer(tempDir);
        addTearDown(container.dispose);
        await container.read(netcruxWorkspaceProvider.future);
        final notifier = container.read(netcruxWorkspaceProvider.notifier);
        await notifier.openTab(
          displayName: 'project-a',
          payload: const NetcruxTabPayload(
            sourceFiles: <String>['/a/main.v'],
            projectFilePath: '/a/projectA.netcrux-project',
          ),
        );
        final tabB = await notifier.openTab(
          displayName: 'project-b',
          payload: const NetcruxTabPayload(
            sourceFiles: <String>['/b/main.v'],
            projectFilePath: '/b/projectB.netcrux-project',
          ),
        );
        expect(
          container.read(activeProjectFilePathProvider),
          '/b/projectB.netcrux-project',
        );

        // Switch back to the first tab.
        final ws = container.read(netcruxWorkspaceProvider).requireValue;
        final tabA = ws.tabs.firstWhere((t) => t.id != tabB).id;
        await notifier.setActiveTab(tabA);
        expect(
          container.read(activeProjectFilePathProvider),
          '/a/projectA.netcrux-project',
        );
      },
    );

    test('returns null after the workspace is reset', () async {
      final container = _buildContainer(tempDir);
      addTearDown(container.dispose);
      await container.read(netcruxWorkspaceProvider.future);
      final notifier = container.read(netcruxWorkspaceProvider.notifier);
      await notifier.openTab(
        displayName: 'tmp',
        payload: const NetcruxTabPayload(
          sourceFiles: <String>['/t/main.v'],
          projectFilePath: '/t/tmp.netcrux-project',
        ),
      );
      expect(container.read(activeProjectFilePathProvider), isNotNull);
      await notifier.resetWorkspace();
      expect(container.read(activeProjectFilePathProvider), isNull);
    });
  });
}
