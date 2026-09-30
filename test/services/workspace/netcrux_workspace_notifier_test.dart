// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/workspace/netcrux_tab_payload.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_codec.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_notifier.dart';

import '../../helpers/telemetry_test_overrides.dart';
import '../../helpers/wait_for.dart';

void main() {
  late Directory tmp;
  late WorkspaceService<NetcruxTabPayload> service;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('netcrux_workspace_test_');
    service = WorkspaceService<NetcruxTabPayload>(
      codec: const NetcruxWorkspaceCodec(),
      directoryFactory: () async => tmp,
      // Silence tearDown-race "save failed: rename" log spam — debounced
      // saves can still be in-flight when the test deletes the tmp dir.
      logger: (_) {},
    );
  });

  tearDown(() => bestEffortDeleteTempDir(tmp));

  ProviderContainer makeContainer({
    Duration debounce = const Duration(milliseconds: 50),
  }) {
    return ProviderContainer(
      overrides: [
        ...netcruxTelemetryTestOverrides(),
        netcruxWorkspaceProvider.overrideWith(
          () => NetcruxWorkspaceNotifier(
            service: service,
            autoSaveDebounce: debounce,
          ),
        ),
      ],
    );
  }

  test(
    'first build returns an empty workspace when no document exists',
    () async {
      final container = makeContainer();
      addTearDown(container.dispose);
      final ws = await container.read(netcruxWorkspaceProvider.future);
      expect(ws.tabs, isEmpty);
      expect(ws.panes, hasLength(1));
    },
  );

  test(
    'openTab + reorderTab + closeTab round-trip + persists to disk',
    () async {
      final container = makeContainer();
      addTearDown(container.dispose);
      await container.read(netcruxWorkspaceProvider.future);
      final notifier = container.read(netcruxWorkspaceProvider.notifier);

      final t1 = await notifier.openTab(
        displayName: 'cpu',
        payload: const NetcruxTabPayload(sourceFiles: ['/d/cpu.v']),
      );
      final t2 = await notifier.openTab(
        displayName: 'mem',
        payload: const NetcruxTabPayload(sourceFiles: ['/d/mem.v']),
      );
      final t3 = await notifier.openTab(
        displayName: 'io',
        payload: const NetcruxTabPayload(sourceFiles: ['/d/io.v']),
      );

      expect(
        container.read(netcruxWorkspaceProvider).value!.tabs,
        hasLength(3),
      );

      await notifier.reorderTab(t1, 2);
      expect(
        container
            .read(netcruxWorkspaceProvider)
            .value!
            .tabs
            .map((t) => t.id)
            .toList(),
        [t2, t3, t1],
      );

      await notifier.closeTab(t2);
      final after = container.read(netcruxWorkspaceProvider).value!;
      expect(after.tabs, hasLength(2));
      expect(after.tabs.map((t) => t.id), [t3, t1]);

      // Final save must have been flushed (autoSaveDebounce is zero).
      await notifier.flushPendingSave();
      final file = File('${tmp.path}/workspace.json');
      expect(file.existsSync(), isTrue);

      // Re-hydrate from disk into a fresh container.
      final reloadContainer = makeContainer();
      addTearDown(reloadContainer.dispose);
      final reloaded = await reloadContainer.read(
        netcruxWorkspaceProvider.future,
      );
      expect(reloaded.tabs, hasLength(2));
      expect(reloaded.tabs.first.payload.sourceFiles, ['/d/io.v']);
    },
  );

  test(
    'per-tab payload isolation — updateTabPayload only touches one tab',
    () async {
      final container = makeContainer();
      addTearDown(container.dispose);
      await container.read(netcruxWorkspaceProvider.future);
      final notifier = container.read(netcruxWorkspaceProvider.notifier);

      final a = await notifier.openTab(
        displayName: 'a',
        payload: const NetcruxTabPayload(sourceFiles: ['/d/a.v']),
      );
      final b = await notifier.openTab(
        displayName: 'b',
        payload: const NetcruxTabPayload(sourceFiles: ['/d/b.v']),
      );

      await notifier.updateTabPayload(
        a,
        (current) => current.copyWith(topModule: 'cpu', zoom: 2.5),
      );

      final ws = container.read(netcruxWorkspaceProvider).value!;
      final tabA = ws.tabs.firstWhere((t) => t.id == a);
      final tabB = ws.tabs.firstWhere((t) => t.id == b);
      expect(tabA.payload.topModule, 'cpu');
      expect(tabA.payload.zoom, 2.5);
      expect(tabB.payload.topModule, '');
      expect(tabB.payload.zoom, 1.0);
    },
  );

  test('splitPaneRight + closePane round-trip', () async {
    final container = makeContainer();
    addTearDown(container.dispose);
    await container.read(netcruxWorkspaceProvider.future);
    final notifier = container.read(netcruxWorkspaceProvider.notifier);

    final t1 = await notifier.openTab(
      displayName: 'a',
      payload: const NetcruxTabPayload(sourceFiles: ['/d/a.v']),
    );
    final t2 = await notifier.openTab(
      displayName: 'b',
      payload: const NetcruxTabPayload(sourceFiles: ['/d/b.v']),
    );

    final newPaneId = await notifier.splitPaneRight();
    final afterSplit = container.read(netcruxWorkspaceProvider).value!;
    expect(afterSplit.panes, hasLength(2));
    expect(afterSplit.activePaneId, newPaneId);
    // The active tab (t2) moved to the new pane.
    final movedTab = afterSplit.tabs.firstWhere((t) => t.id == t2);
    expect(movedTab.paneId, newPaneId);
    // t1 remains in the original pane.
    final retainedTab = afterSplit.tabs.firstWhere((t) => t.id == t1);
    expect(retainedTab.paneId, isNot(newPaneId));

    await notifier.closePane(newPaneId);
    final afterClose = container.read(netcruxWorkspaceProvider).value!;
    expect(afterClose.panes, hasLength(1));
    // t2 merged back into the surviving pane.
    expect(
      afterClose.tabs.map((t) => t.paneId).toSet().length,
      1,
    );
  });
}
