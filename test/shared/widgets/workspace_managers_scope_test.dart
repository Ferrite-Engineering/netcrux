// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/shared/widgets/workspace_managers_scope.dart';

void main() {
  group('WorkspaceManagersScope', () {
    testWidgets('exposes the supplied managers via .of(context)', (
      tester,
    ) async {
      final root = ProviderContainer();
      addTearDown(root.dispose);
      final tabs = TabContainerManager(rootContainer: root);
      addTearDown(tabs.dispose);
      final panes = PaneContainerManager(rootContainer: root);
      addTearDown(panes.dispose);

      TabContainerManager? capturedTabs;
      PaneContainerManager? capturedPanes;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: root,
          child: WorkspaceManagersScope(
            tabContainerManager: tabs,
            paneContainerManager: panes,
            child: Builder(
              builder: (context) {
                final scope = WorkspaceManagersScope.of(context);
                capturedTabs = scope.tabContainerManager;
                capturedPanes = scope.paneContainerManager;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      expect(capturedTabs, same(tabs));
      expect(capturedPanes, same(panes));
      expect(tester.takeException(), isNull);
    });

    testWidgets('maybeOf returns null when no scope ancestor exists', (
      tester,
    ) async {
      WorkspaceManagersScope? captured;
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            captured = WorkspaceManagersScope.maybeOf(context);
            return const SizedBox.shrink();
          },
        ),
      );
      expect(captured, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('updateShouldNotify returns false (managers are stable)', (
      tester,
    ) async {
      final root = ProviderContainer();
      addTearDown(root.dispose);
      final tabs = TabContainerManager(rootContainer: root);
      addTearDown(tabs.dispose);
      final panes = PaneContainerManager(rootContainer: root);
      addTearDown(panes.dispose);

      final scopeA = WorkspaceManagersScope(
        tabContainerManager: tabs,
        paneContainerManager: panes,
        child: const SizedBox.shrink(),
      );
      final scopeB = WorkspaceManagersScope(
        tabContainerManager: tabs,
        paneContainerManager: panes,
        child: const SizedBox.shrink(),
      );
      expect(scopeB.updateShouldNotify(scopeA), isFalse);
    });
  });
}
