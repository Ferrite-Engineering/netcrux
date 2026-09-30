// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/project/netcrux_project.dart';
import 'package:netcrux/features/project/providers/current_project_provider.dart';
import 'package:netcrux/services/reload/source_file_watcher_provider.dart';
import 'package:netcrux/services/workspace/netcrux_tab_overrides.dart';

void main() {
  group('Auto-reload behavior under multi-tab', () {
    test('sourceReloadEventsProvider state is independent per-tab', () {
      final root = ProviderContainer();
      addTearDown(root.dispose);
      final manager = TabContainerManager(
        rootContainer: root,
        overridesFactory: netcruxTabOverridesFactory,
      );
      addTearDown(manager.dispose);

      final tabA = manager.containerFor(TabId.generate());
      final tabB = manager.containerFor(TabId.generate());

      // Each tab carries its own currentProject + reload-event state.
      tabA
          .read(currentProjectProvider.notifier)
          .setProject(
            const NetcruxProject(
              version: 1,
              sourceFiles: <String>['/d/a.v'],
              topModule: '',
              defines: <String, String>{},
              includePaths: <String>[],
              extraYosysCommands: <String>[],
              lowerToStructural: false,
            ),
          );

      tabA.read(sourceReloadEventsProvider.notifier).publish(3);
      expect(tabA.read(sourceReloadEventsProvider), 3);
      expect(tabB.read(sourceReloadEventsProvider), isNull);

      tabA.read(sourceReloadEventsProvider.notifier).clear();
      expect(tabA.read(sourceReloadEventsProvider), isNull);
    });

    test('sourceFileWatcherProvider builds independently per-tab', () {
      final root = ProviderContainer();
      addTearDown(root.dispose);
      final manager = TabContainerManager(
        rootContainer: root,
        overridesFactory: netcruxTabOverridesFactory,
      );
      addTearDown(manager.dispose);

      final tabA = manager.containerFor(TabId.generate());
      final tabB = manager.containerFor(TabId.generate());

      // Reading the provider runs build() inside each per-tab container.
      // The watcher's ref.listen<NetcruxProject>(currentProjectProvider)
      // resolves to that container's currentProjectProvider override so
      // a file change in tab A cannot trip tab B's elaboration.
      // (We're verifying activation here; the underlying watch loop is
      // covered by crux_file_watcher's own test suite.)
      tabA.read(sourceFileWatcherProvider);
      tabB.read(sourceFileWatcherProvider);

      // Notifier instances are distinct per-tab.
      final notifierA = tabA.read(sourceFileWatcherProvider.notifier);
      final notifierB = tabB.read(sourceFileWatcherProvider.notifier);
      expect(identical(notifierA, notifierB), isFalse);
    });
  });
}
