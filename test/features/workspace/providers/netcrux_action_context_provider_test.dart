// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';
import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/domain/models/workspace/netcrux_tab_payload.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/features/workspace/providers/netcrux_action_context_provider.dart';
import 'package:netcrux/services/workspace/netcrux_tab_overrides.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_codec.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_notifier.dart';
import 'package:netcrux/services/workspace/tab_container_manager_holder.dart';
import '../../../helpers/telemetry_test_overrides.dart';

/// Composition test: the shared context provider must combine the
/// workspace facts (open tab, pane count) with the active-tab mirror.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('reflects workspace + active-tab state', () async {
    final root = ProviderContainer(
      overrides: <Override>[
        ...netcruxTelemetryTestOverrides(),
        netcruxWorkspaceProvider.overrideWith(
          () => NetcruxWorkspaceNotifier(
            service: WorkspaceService<NetcruxTabPayload>(
              codec: const NetcruxWorkspaceCodec(),
              directoryFactory: () async =>
                  Directory.systemTemp.createTempSync('netcrux_ctx_test_'),
              logger: (_) {},
            ),
          ),
        ),
      ],
    );
    addTearDown(root.dispose);
    final manager = TabContainerManager(
      rootContainer: root,
      overridesFactory: netcruxTabOverridesFactory,
    );
    addTearDown(manager.dispose);
    root.read(tabContainerManagerHolderProvider).manager = manager;
    await root.read(netcruxWorkspaceProvider.future);

    final sub = root.listen(netcruxActionContextProvider, (_, _) {});
    addTearDown(sub.close);

    expect(sub.read().hasOpenTab, isFalse);
    expect(sub.read().paneCount, 1);

    final tabId = await root
        .read(netcruxWorkspaceProvider.notifier)
        .openTab(displayName: 'a', payload: NetcruxTabPayload.empty);
    await root.read(netcruxWorkspaceProvider.future);
    expect(sub.read().hasOpenTab, isTrue);
    expect(sub.read().hasSelection, isFalse);

    manager
        .containerFor(tabId)
        .read(selectedElementProvider.notifier)
        .select(const SelectedElement.cell(cellId: 'u_alu'));
    // The active-tab mirror applies listener updates on a microtask (so a
    // per-tab provider resolving mid-build can never write root state
    // during a widget build) — drain it before asserting.
    await Future<void>.delayed(Duration.zero);
    expect(sub.read().hasSelection, isTrue);

    await root.read(netcruxWorkspaceProvider.notifier).splitPaneRight();
    expect(sub.read().paneCount, 2);
  });
}
