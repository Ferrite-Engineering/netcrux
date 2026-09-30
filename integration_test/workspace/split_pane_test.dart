// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/workspace/split_pane_test.dart
//
// Verification driver for Open-Core Guide §4.1.4 (Split-pane — tab between
// panes). Exercises the `splitPaneRight` + `moveTabToPane` mutation contract
// against the live workspace: splitting creates a second pane, moving a tab
// reassigns its `paneId`, and emptying a pane collapses the workspace back to
// a single pane.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:netcrux/domain/models/workspace/netcrux_tab_payload.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_notifier.dart';

import '../helpers/app_driver.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets(
    'split right then move a tab between panes (Guide §4.1.4)',
    (tester) async {
      await bootNetcrux(tester);
      final root = rootContainer(tester);
      final notifier = root.read(netcruxWorkspaceProvider.notifier);

      final t1 = await notifier.openTab(
        displayName: 'alpha',
        payload: const NetcruxTabPayload(sourceFiles: ['/tmp/alpha.v']),
      );
      final t2 = await notifier.openTab(
        displayName: 'beta',
        payload: const NetcruxTabPayload(sourceFiles: ['/tmp/beta.v']),
      );
      await pumpUntil(tester, () => tabCount(tester) == 2);

      // Split a new pane to the right.
      final rightPane = await notifier.splitPaneRight();
      await tester.pump();
      var ws = root.read(netcruxWorkspaceProvider).value!;
      expect(ws.panes, hasLength(2), reason: 'split creates a second pane');

      // Move both tabs into the right pane; the left pane then has none.
      await notifier.moveTabToPane(t1, rightPane);
      await notifier.moveTabToPane(t2, rightPane);
      await tester.pump();
      ws = root.read(netcruxWorkspaceProvider).value!;
      expect(
        ws.tabs.where((t) => t.paneId == rightPane),
        hasLength(2),
        reason: 'both tabs now live in the right pane',
      );

      // A pane emptied of all tabs collapses — the workspace returns to a
      // single pane (the surviving populated one).
      expect(
        ws.panes,
        hasLength(1),
        reason: 'the now-empty left pane collapses back to single-pane',
      );

      expect(tester.takeException(), isNull);
    },
  );
}
