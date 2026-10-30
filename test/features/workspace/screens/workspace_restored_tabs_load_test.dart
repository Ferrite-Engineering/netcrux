// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/cli/cli_launch_intent.dart';
import 'package:netcrux/domain/models/workspace/netcrux_tab_payload.dart';
import 'package:netcrux/features/project/providers/current_project_provider.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_codec.dart';
import 'package:path/path.dart' as p;

import '../../../helpers/workspace_app_harness.dart';

/// A tab restored from the saved workspace always comes back with its design:
/// whichever way NetCrux was launched, every restored tab that has source
/// files is pushed into its own pipeline, so none of them shows the "Open
/// Project..." placeholder while its sources are on disk.
void main() {
  late Directory dir;
  setUp(
    () => dir = Directory(
      Directory.systemTemp
          .createTempSync('netcrux_restored_tabs_')
          .resolveSymbolicLinksSync(),
    ),
  );
  tearDown(() => dir.deleteSync(recursive: true));
  final macOS = TargetPlatformVariant.only(TargetPlatform.macOS);

  /// Saves a workspace of two tabs in one pane, the JSON tab active, the shape
  /// a session that was closed with a large netlist open leaves behind.
  Future<(Directory, TabId, TabId)> saveWorkspace(WidgetTester tester) async {
    final wsDir = Directory(p.join(dir.path, 'ws'))..createSync();
    final pane = PaneId.generate();
    final jsonTab = TabId.generate();
    final vTab = TabId.generate();
    await tester.runAsync(
      () =>
          WorkspaceService<NetcruxTabPayload>(
            codec: const NetcruxWorkspaceCodec(),
            directoryFactory: () async => wsDir,
            logger: (_) {},
          ).save(
            Workspace<NetcruxTabPayload>(
              tabs: <WorkspaceTab<NetcruxTabPayload>>[
                WorkspaceTab<NetcruxTabPayload>(
                  id: jsonTab,
                  displayName: 'big.json',
                  paneId: pane,
                  payload: NetcruxTabPayload(
                    sourceFiles: <String>[p.join(dir.path, 'big.json')],
                  ),
                ),
                WorkspaceTab<NetcruxTabPayload>(
                  id: vTab,
                  displayName: 'big.v',
                  paneId: pane,
                  payload: NetcruxTabPayload(
                    sourceFiles: <String>[p.join(dir.path, 'big.v')],
                    blackBoxMissingModules: true,
                  ),
                ),
              ],
              panes: <WorkspacePane>[
                WorkspacePane(id: pane, activeTabId: jsonTab),
              ],
              activePaneId: pane,
            ),
          ),
    );
    return (wsDir, jsonTab, vTab);
  }

  void expectRestored(
    WorkspaceAppHarness h,
    TabId jsonTab,
    TabId vTab, {
    bool blackBoxes = true,
  }) {
    final json = h.tabs.containerFor(jsonTab).read(currentProjectProvider);
    expect(json.sourceFiles, <String>[p.join(dir.path, 'big.json')]);
    final v = h.tabs.containerFor(vTab).read(currentProjectProvider);
    expect(v.sourceFiles, <String>[p.join(dir.path, 'big.v')]);
    // Opening a design by name again starts it without the option.
    expect(v.blackBoxMissingModules, blackBoxes);
  }

  testWidgets('with no launch arguments every restored tab has its design', (
    tester,
  ) async {
    final (wsDir, jsonTab, vTab) = await saveWorkspace(tester);
    final h = await WorkspaceAppHarness.boot(
      tester,
      workspaceDirectory: wsDir,
    );
    expectRestored(h, jsonTab, vTab);
    expect(tester.takeException(), isNull);
    await WorkspaceAppHarness.unmount(tester);
  }, variant: macOS);

  testWidgets('launched with a source file, the restored tabs keep their '
      'designs beside the new one', (tester) async {
    final (wsDir, jsonTab, vTab) = await saveWorkspace(tester);
    final extra = p.join(dir.path, 'extra.v');
    final h = await WorkspaceAppHarness.boot(
      tester,
      workspaceDirectory: wsDir,
      intent: CliLaunchIntent.openSourceFiles(<String>[extra]),
    );
    expectRestored(h, jsonTab, vTab);
    expect(h.activeTab.read(currentProjectProvider).sourceFiles, <String>[
      extra,
    ]);
    expect(tester.takeException(), isNull);
    await WorkspaceAppHarness.unmount(tester);
  }, variant: macOS);

  testWidgets('launched with the restored design itself, its sibling tab '
      'keeps its design', (tester) async {
    final (wsDir, jsonTab, vTab) = await saveWorkspace(tester);
    final h = await WorkspaceAppHarness.boot(
      tester,
      workspaceDirectory: wsDir,
      intent: CliLaunchIntent.openSourceFiles(<String>[
        p.join(dir.path, 'big.v'),
      ]),
    );
    expectRestored(h, jsonTab, vTab, blackBoxes: false);
    expect(tester.takeException(), isNull);
    await WorkspaceAppHarness.unmount(tester);
  }, variant: macOS);
}
