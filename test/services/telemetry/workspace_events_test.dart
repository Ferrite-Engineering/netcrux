// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The shared suite workspace counters, at the seams that actually emit them.
//
// `workspace.restored`, `tab.opened`, `pane.split`, `pane.closed` and
// `tab.dragged_to_pane` come out of `NetcruxWorkspaceNotifier`'s overrides of
// `crux_workspace`'s mutation API, and `workspace.named.saved` /
// `workspace.named.opened` out of its `saveAs` / `loadFrom`. Every test here
// drives the real notifier over a real temp-directory `WorkspaceService` — the
// production path — rather than calling the emit helper.
//
// The half worth the length is the *no-op* coverage. The package's methods are
// all no-op-safe (`closePane` on a single-pane workspace, `moveTabToPane` onto
// the pane a tab already occupies, `openTab` deduping onto an open tab), and a
// counter that fires on those is measuring keystrokes instead of workspace
// shape. Those cases are asserted one by one below.

import 'dart:io';

import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/workspace/netcrux_tab_payload.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_codec.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_notifier.dart';
import 'package:path/path.dart' as p;

import '../../helpers/wait_for.dart';

class _RecordingTelemetryService implements TelemetryService {
  final List<TelemetryEvent> events = <TelemetryEvent>[];

  @override
  void record(TelemetryEvent event) => events.add(event);

  List<String> get names => [for (final e in events) e.name];

  TelemetryEvent named(String name) => events.firstWhere((e) => e.name == name);

  int count(String name) => names.where((n) => n == name).length;
}

void main() {
  late Directory tmp;
  late WorkspaceService<NetcruxTabPayload> service;
  late _RecordingTelemetryService telemetry;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('netcrux_ws_telemetry_');
    service = WorkspaceService<NetcruxTabPayload>(
      codec: const NetcruxWorkspaceCodec(),
      directoryFactory: () async => tmp,
      logger: (_) {},
    );
    telemetry = _RecordingTelemetryService();
  });

  tearDown(() => bestEffortDeleteTempDir(tmp));

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [
        telemetryServiceProvider.overrideWithValue(telemetry),
        netcruxWorkspaceProvider.overrideWith(
          () => NetcruxWorkspaceNotifier(
            service: service,
            autoSaveDebounce: Duration.zero,
            restoreGate: () async => true,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<NetcruxWorkspaceNotifier> boot(ProviderContainer container) async {
    await container.read(netcruxWorkspaceProvider.future);
    return await container.read(netcruxWorkspaceProvider.notifier);
  }

  Future<TabId> openTab(NetcruxWorkspaceNotifier ws, String path) => ws.openTab(
    displayName: p.basename(path),
    payload: NetcruxTabPayload(sourceFiles: <String>[path]),
  );

  group('workspace.restored', () {
    test(
      'fires once at launch, with the restored tab and pane counts',
      () async {
        final container = makeContainer();
        await boot(container);

        expect(telemetry.count('workspace.restored'), 1);
        final event = telemetry.named('workspace.restored');
        expect(event.properties, <String, Object?>{'tabs': 0, 'panes': 1});
      },
    );

    test('does not fire a second time when the notifier rebuilds', () async {
      // `build` re-runs on any watched-dependency change; the restore it counts
      // happens once per process.
      final container = makeContainer();
      final ws = await boot(container);
      await openTab(ws, '/tmp/top.v');

      expect(telemetry.count('workspace.restored'), 1);
    });

    test(
      'reports the counts of a workspace that had content on disk',
      () async {
        final first = makeContainer();
        final ws = await boot(first);
        await openTab(ws, '/tmp/top.v');
        await ws.splitPaneRight();
        await ws.flushPendingSave();
        first.dispose();

        telemetry = _RecordingTelemetryService();
        final second = makeContainer();
        await boot(second);

        expect(
          telemetry.named('workspace.restored').properties,
          <String, Object?>{'tabs': 1, 'panes': 2},
        );
      },
    );
  });

  group('tab.opened', () {
    test('fires with the post-open tab and pane counts', () async {
      final container = makeContainer();
      final ws = await boot(container);

      await openTab(ws, '/tmp/a.v');
      await openTab(ws, '/tmp/b.v');

      expect(telemetry.count('tab.opened'), 2);
      expect(
        telemetry.events.lastWhere((e) => e.name == 'tab.opened').properties,
        <String, Object?>{'tabs': 2, 'panes': 1},
      );
    });

    test(
      'a deduped open re-activates an existing tab and counts nothing',
      () async {
        // Re-opening a file already on screen is a tab *switch*. Counting it
        // would make `tab.opened` measure the recent-files list.
        final container = makeContainer();
        final ws = await boot(container);
        await openTab(ws, '/tmp/a.v');
        expect(telemetry.count('tab.opened'), 1);

        await openTab(ws, '/tmp/a.v');

        expect(telemetry.count('tab.opened'), 1);
        expect((await ws.future).tabs, hasLength(1));
      },
    );

    test('carries no file name, path, or display name', () async {
      final container = makeContainer();
      final ws = await boot(container);
      await openTab(ws, '/tmp/secret_project/top_secret.v');

      final serialized = telemetry.named('tab.opened').toString();
      expect(serialized, isNot(contains('secret')));
      expect(telemetry.named('tab.opened').properties.keys, <String>[
        'tabs',
        'panes',
      ]);
    });
  });

  group('pane.split / pane.closed', () {
    test('splitting emits pane.split', () async {
      final container = makeContainer();
      final ws = await boot(container);
      await ws.splitPaneRight();

      expect(telemetry.count('pane.split'), 1);
      expect(telemetry.named('pane.split').properties, isEmpty);
    });

    test(
      'a second split on an already-split workspace counts nothing',
      () async {
        final container = makeContainer();
        final ws = await boot(container);
        await ws.splitPaneRight();
        await ws.splitPaneRight();

        expect(telemetry.count('pane.split'), 1);
      },
    );

    test('closing a pane emits pane.closed', () async {
      final container = makeContainer();
      final ws = await boot(container);
      final paneId = await ws.splitPaneRight();
      await ws.closePane(paneId);

      expect(telemetry.count('pane.closed'), 1);
    });

    test('closing the only pane counts nothing', () async {
      final container = makeContainer();
      final ws = await boot(container);
      final only = (await ws.future).panes.single.id;

      await ws.closePane(only);

      expect(telemetry.count('pane.closed'), 0);
    });
  });

  group('tab.dragged_to_pane', () {
    test('moving a tab across panes emits it', () async {
      final container = makeContainer();
      final ws = await boot(container);
      final tabId = await openTab(ws, '/tmp/a.v');
      final other = await ws.splitPaneRight();

      await ws.moveTabToPane(tabId, other);

      expect(telemetry.count('tab.dragged_to_pane'), 1);
    });

    test(
      'moving a tab onto the pane it already occupies counts nothing',
      () async {
        final container = makeContainer();
        final ws = await boot(container);
        final tabId = await openTab(ws, '/tmp/a.v');
        final home = (await ws.future).tabs.single.paneId;

        await ws.moveTabToPane(tabId, home);

        expect(telemetry.count('tab.dragged_to_pane'), 0);
      },
    );
  });

  group('workspace.named.saved / workspace.named.opened', () {
    test('saveAs emits named.saved with no properties at all', () async {
      final container = makeContainer();
      final ws = await boot(container);
      await openTab(ws, '/tmp/a.v');
      final path = p.join(tmp.path, 'my.netcrux-workspace');

      await ws.saveAs(path);

      expect(telemetry.count('workspace.named.saved'), 1);
      // The chosen path is the user's filesystem and never leaves the machine.
      expect(telemetry.named('workspace.named.saved').properties, isEmpty);
      expect(
        telemetry.named('workspace.named.saved').toString(),
        isNot(contains('my.netcrux-workspace')),
      );
    });

    test('loadFrom emits named.opened with the loaded shape', () async {
      final container = makeContainer();
      final ws = await boot(container);
      await openTab(ws, '/tmp/a.v');
      await ws.splitPaneRight();
      final path = p.join(tmp.path, 'my.netcrux-workspace');
      await ws.saveAs(path);
      await ws.resetWorkspace();

      await ws.loadFrom(path);

      expect(telemetry.count('workspace.named.opened'), 1);
      expect(
        telemetry.named('workspace.named.opened').properties,
        <String, Object?>{'tabs': 1, 'panes': 2},
      );
    });
  });

  test('every workspace event this notifier emits is a catalog name', () async {
    // Cross-checks the emission sites against the pinned catalog from the
    // other direction than the static scanner: these are the names the
    // *running* notifier produced.
    final container = makeContainer();
    final ws = await boot(container);
    // Split-then-close first: `moveTabToPane` collapses a source pane it
    // empties, so doing the move first would leave `closePane` nothing to do.
    final firstSplit = await ws.splitPaneRight();
    await ws.closePane(firstSplit);
    final tabId = await openTab(ws, '/tmp/a.v');
    await openTab(ws, '/tmp/b.v');
    final other = await ws.splitPaneRight();
    await ws.moveTabToPane(tabId, other);
    final path = p.join(tmp.path, 'w.netcrux-workspace');
    await ws.saveAs(path);
    await ws.loadFrom(path);

    expect(
      telemetry.names.toSet(),
      <String>{
        'workspace.restored',
        'tab.opened',
        'pane.split',
        'tab.dragged_to_pane',
        'pane.closed',
        'workspace.named.saved',
        'workspace.named.opened',
      },
    );
  });
}
