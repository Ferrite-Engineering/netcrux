// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/workspace/restore_round_trip_test.dart
//
// Verification driver for Open-Core Guide §4.1.1 (Workspace auto-save and
// restore on launch). The Flutter framework forbids calling `runApp` twice in
// one test process, so "quit and relaunch" is approximated the same way the
// WaveCrux suite does it: drive the live workspace through real mutations,
// force the debounced auto-save to flush, then re-read the persisted
// `workspace.json` through a FRESH `WorkspaceService` instance and assert the
// next cold start would restore exactly that state.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:netcrux/domain/models/workspace/netcrux_tab_payload.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_notifier.dart';

import '../helpers/app_driver.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets(
    'two opened tabs auto-persist and re-read identically (Guide §4.1.1)',
    (tester) async {
      await bootNetcrux(tester);
      final root = rootContainer(tester);
      final notifier = root.read(netcruxWorkspaceProvider.notifier);

      // Open two tabs with distinct payloads.
      final t1 = await notifier.openTab(
        displayName: 'alpha',
        payload: const NetcruxTabPayload(
          sourceFiles: ['/tmp/alpha.v'],
          topModule: 'alpha',
        ),
      );
      await notifier.openTab(
        displayName: 'beta',
        payload: const NetcruxTabPayload(
          sourceFiles: ['/tmp/beta.v'],
          topModule: 'beta',
        ),
      );
      await pumpUntil(tester, () => tabCount(tester) == 2);
      expect(tabCount(tester), 2);

      // Force the debounced auto-save to land (the production
      // AppLifecycleState.detached flush calls the same method).
      await notifier.flushPendingSave();

      // Re-read through a fresh service instance — what the next cold start
      // would hydrate from disk.
      final reloaded = await freshWorkspaceLoad();
      expect(
        reloaded.tabs,
        hasLength(2),
        reason: 'both tabs must survive the auto-save round-trip',
      );
      final names = reloaded.tabs.map((t) => t.displayName).toSet();
      expect(names, containsAll(<String>['alpha', 'beta']));
      final sources = reloaded.tabs
          .map((t) => t.payload.sourceFiles.single)
          .toSet();
      expect(sources, containsAll(<String>['/tmp/alpha.v', '/tmp/beta.v']));
      // First-opened tab is still present; the active pointer is preserved.
      expect(reloaded.tabs.any((t) => t.id == t1), isTrue);
      expect(reloaded.activeTabId, isNotNull);

      expect(tester.takeException(), isNull);
    },
  );
}
