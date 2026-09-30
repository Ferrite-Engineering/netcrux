// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/workspace/netcrux_tab_payload.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_codec.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_notifier.dart';

import '../../helpers/telemetry_test_overrides.dart';
import '../../helpers/wait_for.dart';

/// Stands in for any per-tab state NetCrux scopes into a tab container
/// (the selected net, the viewport transform, an analysis result).
class _TabState {
  int value = 0;
}

final _tabStateProvider = Provider<_TabState>(
  (ref) => _TabState(),
  name: 'tabState',
);

List<Override> _tabOverrides(TabId _) => <Override>[
  _tabStateProvider.overrideWith((ref) => _TabState()),
];

/// Regression coverage for the structural scope-eviction wiring that
/// `bootstrap` installs: both container managers are registered as
/// `WorkspaceScopeReconciler`s on the workspace notifier.
///
/// Nothing fails to compile when that registration is missing, which is
/// why it needs a test of its own. Two distinct defects follow from
/// skipping it. The first is a leak: a closed tab's `ProviderContainer`
/// is never disposed, so every provider, subscription and timer it holds
/// survives for the process lifetime. The second is worse and does not
/// present as memory growth — tab ids round-trip through the workspace
/// document, so reloading a workspace revives an id the manager still
/// caches a container for, and the new tab silently inherits the dead
/// tab's state.
void main() {
  late Directory tmp;
  late WorkspaceService<NetcruxTabPayload> service;
  late ProviderContainer root;
  late TabContainerManager tabs;
  late PaneContainerManager panes;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('netcrux_scope_reconcile_');
    service = WorkspaceService<NetcruxTabPayload>(
      codec: const NetcruxWorkspaceCodec(),
      directoryFactory: () async => tmp,
      logger: (_) {},
    );
  });

  tearDown(() => bestEffortDeleteTempDir(tmp));

  /// Boots a root container with both managers registered exactly the way
  /// `bootstrap` does, and returns the hydrated notifier.
  Future<NetcruxWorkspaceNotifier> boot() async {
    root = ProviderContainer(
      overrides: [
        ...netcruxTelemetryTestOverrides(),
        netcruxWorkspaceProvider.overrideWith(
          () => NetcruxWorkspaceNotifier(
            service: service,
            autoSaveDebounce: const Duration(milliseconds: 10),
          ),
        ),
      ],
    );
    addTearDown(root.dispose);
    await root.read(netcruxWorkspaceProvider.future);

    tabs = TabContainerManager(
      rootContainer: root,
      overridesFactory: _tabOverrides,
    );
    addTearDown(tabs.dispose);
    panes = PaneContainerManager(
      rootContainer: root,
      overridesFactory: (_) => const <Override>[],
    );
    addTearDown(panes.dispose);

    final notifier = root.read(netcruxWorkspaceProvider.notifier)
      ..addScopeReconciler(tabs)
      ..addScopeReconciler(panes);
    return notifier;
  }

  test('closing a tab evicts its container', () async {
    final notifier = await boot();

    final tabId = await notifier.openTab(
      displayName: 'cpu',
      payload: const NetcruxTabPayload(sourceFiles: ['/d/cpu.v']),
    );
    tabs.containerFor(tabId);
    expect(tabs.hasContainerFor(tabId), isTrue);

    await notifier.closeTab(tabId);

    expect(
      tabs.hasContainerFor(tabId),
      isFalse,
      reason:
          'without the reconciler registration the container survives for '
          'the process lifetime',
    );
  });

  test(
    'a tab id revived by a workspace reload gets a fresh container',
    () async {
      final notifier = await boot();

      final tabId = await notifier.openTab(
        displayName: 'cpu',
        payload: const NetcruxTabPayload(sourceFiles: ['/d/cpu.v']),
      );
      final live = tabs.containerFor(tabId);
      live.read(_tabStateProvider).value = 42;

      // A persisted document keeps tab ids verbatim; that round-trip is what
      // makes resurrection possible at all.
      final persisted = root.read(netcruxWorkspaceProvider).requireValue;
      await notifier.closeTab(tabId);
      await notifier.replaceWith(persisted);

      expect(
        persisted.tabs.single.id,
        equals(tabId),
        reason: 'precondition: the reload really does revive the same id',
      );

      final revived = tabs.containerFor(tabId);
      expect(identical(revived, live), isFalse);
      expect(
        revived.read(_tabStateProvider).value,
        0,
        reason:
            'the revived tab inherited the closed tab’s state — this is the '
            'cross-tab bleed the reconciler seam exists to prevent',
      );
    },
  );

  test('the pane manager is registered too', () async {
    final notifier = await boot();

    final paneId = root
        .read(netcruxWorkspaceProvider)
        .requireValue
        .panes
        .first
        .id;
    panes.containerFor(paneId);
    expect(panes.hasContainerFor(paneId), isTrue);

    // resetWorkspace is a wholesale replacement, so it emits the empty
    // snapshot first; a registered pane manager drops the outgoing
    // document's pane scopes.
    await notifier.resetWorkspace();

    expect(panes.hasContainerFor(paneId), isFalse);
  });
}
