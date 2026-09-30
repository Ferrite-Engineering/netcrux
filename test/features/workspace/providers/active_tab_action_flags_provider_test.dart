// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/domain/models/trace/trace_overlay.dart';
import 'package:netcrux/domain/models/workspace/netcrux_tab_payload.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/features/viewer/providers/trace_overlay_notifier.dart';
import 'package:netcrux/features/workspace/providers/active_tab_action_flags_provider.dart';
import 'package:netcrux/services/workspace/netcrux_tab_overrides.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_codec.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_notifier.dart';
import 'package:netcrux/services/workspace/tab_container_manager_holder.dart';
import '../../../helpers/telemetry_test_overrides.dart';

/// Exercises the root-scope mirror against a real workspace + per-tab
/// container manager: flags must track the ACTIVE tab's per-tab state and
/// rebind when the active tab changes (two-tab isolation).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer root;
  late TabContainerManager manager;

  Future<void> setUpHarness() async {
    root = ProviderContainer(
      overrides: <Override>[
        ...netcruxTelemetryTestOverrides(),
        netcruxWorkspaceProvider.overrideWith(
          () => NetcruxWorkspaceNotifier(
            service: WorkspaceService<NetcruxTabPayload>(
              codec: const NetcruxWorkspaceCodec(),
              directoryFactory: () async =>
                  Directory.systemTemp.createTempSync('netcrux_flags_test_'),
              logger: (_) {},
            ),
          ),
        ),
      ],
    );
    addTearDown(root.dispose);
    manager = TabContainerManager(
      rootContainer: root,
      overridesFactory: netcruxTabOverridesFactory,
    );
    addTearDown(manager.dispose);
    root.read(tabContainerManagerHolderProvider).manager = manager;
    await root.read(netcruxWorkspaceProvider.future);
  }

  test(
    'mirrors the active tab selection / overlay state to the root',
    () async {
      await setUpHarness();
      // Keep the mirror alive for the test's duration (an unlistened
      // provider is paused and would not receive the container events).
      final states = <ActiveTabActionFlags>[];
      final sub = root.listen(
        activeTabActionFlagsProvider,
        (_, next) => states.add(next),
        fireImmediately: true,
      );
      addTearDown(sub.close);

      expect(sub.read(), const ActiveTabActionFlags());

      final tabId = await root
          .read(netcruxWorkspaceProvider.notifier)
          .openTab(displayName: 'a', payload: NetcruxTabPayload.empty);
      await root.read(netcruxWorkspaceProvider.future);
      final tab = manager.containerFor(tabId);

      tab
          .read(selectedElementProvider.notifier)
          .select(const SelectedElement.cell(cellId: 'u_alu'));
      // Mirrored-provider changes are applied to the flags on a microtask (see
      // ActiveTabActionFlagsNotifier._apply, which defers so a listener firing
      // mid-build can't mutate state), so drain pending microtasks first.
      await Future<void>.delayed(Duration.zero);
      expect(sub.read().hasSelection, isTrue);
      expect(sub.read().hasTraceOverlay, isFalse);

      tab.read(selectedElementProvider.notifier).clear();
      await Future<void>.delayed(Duration.zero);
      expect(sub.read().hasSelection, isFalse);
    },
  );

  test(
    'rebinds to the newly-active tab on tab switch (two-tab isolation)',
    () async {
      await setUpHarness();
      final sub = root.listen(activeTabActionFlagsProvider, (_, _) {});
      addTearDown(sub.close);

      final notifier = root.read(netcruxWorkspaceProvider.notifier);
      final tabA = await notifier.openTab(
        displayName: 'a',
        payload: NetcruxTabPayload.empty,
      );
      final tabB = await notifier.openTab(
        displayName: 'b',
        payload: NetcruxTabPayload.empty,
      );
      await root.read(netcruxWorkspaceProvider.future);

      // Select something in tab A only; tab B is active (opened last).
      manager
          .containerFor(tabA)
          .read(selectedElementProvider.notifier)
          .select(const SelectedElement.cell(cellId: 'u_alu'));
      expect(
        sub.read().hasSelection,
        isFalse,
        reason: 'the mirror must reflect the ACTIVE tab (B), not tab A',
      );

      await notifier.setActiveTab(tabA);
      expect(
        sub.read().hasSelection,
        isTrue,
        reason: 'switching to tab A must rebind the mirror to its container',
      );

      await notifier.setActiveTab(tabB);
      expect(sub.read().hasSelection, isFalse);
    },
  );

  test('per-tab writes after rebind keep flowing (subscriptions follow the '
      'container)', () async {
    await setUpHarness();
    final sub = root.listen(activeTabActionFlagsProvider, (_, _) {});
    addTearDown(sub.close);

    final notifier = root.read(netcruxWorkspaceProvider.notifier);
    final tabId = await notifier.openTab(
      displayName: 'a',
      payload: NetcruxTabPayload.empty,
    );
    await root.read(netcruxWorkspaceProvider.future);
    final tab = manager.containerFor(tabId);

    // Drive a second mirrored provider to confirm the whole subscription
    // set is armed, not just selection.
    expect(sub.read().hasTraceOverlay, isFalse);
    tab
        .read(traceOverlayProvider.notifier)
        .set(
          const TraceOverlay(
            mode: TraceOverlayMode.fanin,
            highlightedCellIds: <String>{'u_alu'},
            highlightedEdgeIds: <String>{},
            highlightedBoundaryPortIds: <String>{},
          ),
        );
    // Flag writes are deferred to a microtask (see _apply); drain it first.
    await Future<void>.delayed(Duration.zero);
    expect(sub.read().hasTraceOverlay, isTrue);
    tab.read(traceOverlayProvider.notifier).clear();
    await Future<void>.delayed(Duration.zero);
    expect(sub.read().hasTraceOverlay, isFalse);
  });
}
