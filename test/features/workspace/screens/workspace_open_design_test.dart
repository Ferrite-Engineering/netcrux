// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/cli/cli_launch_intent.dart';
import 'package:netcrux/domain/models/project/netcrux_project.dart';
import 'package:netcrux/domain/models/workspace/netcrux_tab_payload.dart';
import 'package:netcrux/features/project/providers/current_project_provider.dart';
import 'package:netcrux/features/project/providers/loaded_netlist_provider.dart';
import 'package:netcrux/features/settings/providers/app_settings_provider.dart';
import 'package:netcrux/services/project/netcrux_project_file.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_codec.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_notifier.dart';
import 'package:path/path.dart' as p;

import '../../../helpers/workspace_app_harness.dart';

/// The workspace's launch paths open each file for what it is: a `.netcrux`
/// session restores its design rather than being handed to Yosys as HDL, a
/// `<design>.crux-project` keeps every source and its top module, a manifest
/// that names a netlist renders it without Yosys, and a design directory opens
/// the one manifest inside it.
///
/// Every scenario boots the real `NetcruxApp` with a launch intent and reads
/// the project the production flow pushed into the active tab.
void main() {
  late Directory dir;
  // Resolved, because the manifest planner canonicalizes paths and macOS
  // reaches the temp directory through the `/var` -> `/private/var` link.
  setUp(
    () => dir = Directory(
      Directory.systemTemp
          .createTempSync('netcrux_open_design_')
          .resolveSymbolicLinksSync(),
    ),
  );
  tearDown(() => dir.deleteSync(recursive: true));
  final macOS = TargetPlatformVariant.only(TargetPlatform.macOS);

  String writeSession() {
    final path = p.join(dir.path, 'review.netcrux');
    File(path).writeAsStringSync(
      jsonEncode(<String, Object?>{
        'version': 1,
        'sourceFiles': <String>[
          p.join(dir.path, 'cpu.sv'),
          p.join(dir.path, 'alu.sv'),
        ],
        'topModule': 'cpu',
        'scopePath': <String>[],
        'zoom': 1.0,
        'panX': 0.0,
        'panY': 0.0,
      }),
    );
    return path;
  }

  void expectSessionDesign(ProviderContainer tab) {
    final project = tab.read(currentProjectProvider);
    expect(project.sourceFiles, <String>[
      p.join(dir.path, 'cpu.sv'),
      p.join(dir.path, 'alu.sv'),
    ]);
    expect(project.topModule, 'cpu');
  }

  testWidgets('--session opens the session design, not the session file', (
    tester,
  ) async {
    final h = await WorkspaceAppHarness.boot(
      tester,
      intent: CliLaunchIntent.openSession(writeSession()),
    );
    expectSessionDesign(h.activeTab);
    expect(tester.takeException(), isNull);
    await WorkspaceAppHarness.unmount(tester);
  }, variant: macOS);

  testWidgets('a positional .netcrux opens the session design', (
    tester,
  ) async {
    final h = await WorkspaceAppHarness.boot(
      tester,
      intent: CliLaunchIntent.openProject(writeSession()),
    );
    expectSessionDesign(h.activeTab);
    expect(tester.takeException(), isNull);
    await WorkspaceAppHarness.unmount(tester);
  }, variant: macOS);

  /// Writes the three-source `uart` design into [designDir] with its manifest
  /// named [manifestName], and returns the manifest path.
  String writeUartDesign(String designDir, {required String manifestName}) {
    final manifest = p.join(designDir, manifestName);
    File(manifest)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('''
version: 1
name: uart
design:
  top: uart_tx
  sources:
    - rtl/defs.vh
    - rtl/fifo.v
    - rtl/uart_tx.v
''');
    for (final f in ['defs.vh', 'fifo.v', 'uart_tx.v']) {
      File(p.join(designDir, 'rtl', f))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('');
    }
    return manifest;
  }

  testWidgets('a <design>.crux-project keeps every source and its top module', (
    tester,
  ) async {
    final manifest = writeUartDesign(
      dir.path,
      manifestName: 'uart.crux-project',
    );
    final h = await WorkspaceAppHarness.boot(
      tester,
      intent: CliLaunchIntent.openProject(manifest),
    );
    final project = h.activeTab.read(currentProjectProvider);
    expect(project.sourceFiles.map(p.basename), <String>[
      'defs.vh',
      'fifo.v',
      'uart_tx.v',
    ]);
    expect(project.topModule, 'uart_tx');
    final payload = h.root.read(netcruxWorkspaceProvider).value!.tabs.single;
    expect(payload.displayName, 'uart');
    expect(payload.payload.projectFilePath, manifest);
    // A named manifest opens without the legacy file-name notice.
    expect(find.textContaining('Rename it to'), findsNothing);
    expect(tester.takeException(), isNull);
    await WorkspaceAppHarness.unmount(tester);
  }, variant: macOS);

  testWidgets('a legacy bare .crux-project opens and names the new name once', (
    tester,
  ) async {
    final designDir = p.join(dir.path, 'uart');
    final manifest = writeUartDesign(designDir, manifestName: '.crux-project');
    final h = await WorkspaceAppHarness.boot(
      tester,
      intent: CliLaunchIntent.openProject(manifest),
    );
    expect(h.activeTab.read(currentProjectProvider).topModule, 'uart_tx');
    const notice =
        'This .crux-project file has no name, so file pickers hide it. '
        'Rename it to uart.crux-project';
    expect(find.textContaining(notice), findsOneWidget);
    // Once per open: when the notice times out, no second copy is queued
    // behind it.
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining(notice), findsNothing);
    expect(tester.takeException(), isNull);
    await WorkspaceAppHarness.unmount(tester);
  }, variant: macOS);

  testWidgets('a design directory opens the one manifest inside it', (
    tester,
  ) async {
    final designDir = p.join(dir.path, 'uart');
    final manifest = writeUartDesign(
      designDir,
      manifestName: 'uart.crux-project',
    );
    final h = await WorkspaceAppHarness.boot(
      tester,
      intent: CliLaunchIntent.openProject(designDir),
    );
    expect(h.activeTab.read(currentProjectProvider).sourceFiles, hasLength(3));
    final payload = h.root.read(netcruxWorkspaceProvider).value!.tabs.single;
    // The manifest, not the directory, is what the tab and recents remember,
    // so reopening goes straight to the file.
    expect(payload.payload.projectFilePath, manifest);
    expect(
      h.root.read(appSettingsProvider).value!.recentProjectPaths.first,
      manifest,
    );
    expect(tester.takeException(), isNull);
    await WorkspaceAppHarness.unmount(tester);
  }, variant: macOS);

  testWidgets('a directory with two manifests is refused, localized', (
    tester,
  ) async {
    final designDir = p.join(dir.path, 'uart');
    writeUartDesign(designDir, manifestName: 'uart.crux-project');
    writeUartDesign(designDir, manifestName: '.crux-project');
    final h = await WorkspaceAppHarness.boot(
      tester,
      intent: CliLaunchIntent.openProject(designDir),
    );
    expect(h.root.read(netcruxWorkspaceProvider).value!.tabs, isEmpty);
    expect(
      find.textContaining(
        '$designDir holds more than one .crux-project file '
        '(.crux-project, uart.crux-project)',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await WorkspaceAppHarness.unmount(tester);
  }, variant: macOS);

  testWidgets('a directory with no manifest says what to create, localized', (
    tester,
  ) async {
    final designDir = Directory(p.join(dir.path, 'uart'))..createSync();
    final h = await WorkspaceAppHarness.boot(
      tester,
      intent: CliLaunchIntent.openProject(designDir.path),
    );
    expect(h.root.read(netcruxWorkspaceProvider).value!.tabs, isEmpty);
    expect(
      find.textContaining('Create one named uart.crux-project'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await WorkspaceAppHarness.unmount(tester);
  }, variant: macOS);

  testWidgets(
    'a <design>.crux-project naming a netlist renders it without Yosys',
    (
      tester,
    ) async {
      final netlist = p.join(dir.path, 'build', 'seed.json');
      File(netlist)
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(
          File(
            'test/fixtures/netlist/design_seed/generated/'
            'design_seed.netlist.json',
          ).readAsStringSync(),
        );
      final manifest = p.join(dir.path, 'seed.crux-project');
      File(manifest).writeAsStringSync(
        'version: 1\nname: seed\nartifacts:\n  netlist: build/seed.json\n',
      );
      final h = await WorkspaceAppHarness.boot(
        tester,
        intent: CliLaunchIntent.openProject(manifest),
      );
      final tab = h.activeTab;
      expect(tab.read(currentProjectProvider).sourceFiles, <String>[netlist]);
      expect(tab.read(currentProjectProvider).isPrebuiltNetlist, isTrue);
      final model = await tester.runAsync(
        () => tab.read(loadedNetlistProvider.future),
      );
      expect(model?.topModule?.name, 'top');
      await tester.pump();
      expect(tester.takeException(), isNull);
      await WorkspaceAppHarness.unmount(tester);
    },
    variant: macOS,
  );

  testWidgets('an unusable <design>.crux-project explains itself, localized', (
    tester,
  ) async {
    final manifest = p.join(dir.path, 'empty_design.crux-project');
    File(manifest).writeAsStringSync('version: 1\nname: empty_design\n');
    final h = await WorkspaceAppHarness.boot(
      tester,
      intent: CliLaunchIntent.openProject(manifest),
    );
    expect(h.root.read(netcruxWorkspaceProvider).value!.tabs, isEmpty);
    expect(
      find.textContaining('empty_design does not name RTL sources'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await WorkspaceAppHarness.unmount(tester);
  }, variant: macOS);

  testWidgets('a restored project tab keeps its project file settings', (
    tester,
  ) async {
    final projectPath = p.join(dir.path, 'demo.netcrux-project');
    await tester.runAsync(
      () => const NetcruxProjectFileWriter().write(
        projectPath,
        NetcruxProject.create(
          sourceFiles: const <String>['rtl/top.v'],
          topModule: 'top',
          defines: const <String, String>{'WIDTH': '32'},
          includePaths: const <String>['inc'],
          extraYosysCommands: const <String>['flatten'],
        ),
      ),
    );
    final wsDir = Directory(p.join(dir.path, 'ws'))..createSync();
    final pane = PaneId.generate();
    final tabId = TabId.generate();
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
                  id: tabId,
                  displayName: 'demo',
                  paneId: pane,
                  // What the payload carries: the sources and top, no knobs.
                  payload: NetcruxTabPayload(
                    sourceFiles: <String>[p.join(dir.path, 'rtl', 'top.v')],
                    topModule: 'top',
                    projectFilePath: projectPath,
                  ),
                ),
              ],
              panes: <WorkspacePane>[
                WorkspacePane(id: pane, activeTabId: tabId),
              ],
              activePaneId: pane,
            ),
          ),
    );

    final h = await WorkspaceAppHarness.boot(
      tester,
      workspaceDirectory: wsDir,
    );
    final project = h.activeTab.read(currentProjectProvider);
    expect(project.sourceFiles, <String>[p.join(dir.path, 'rtl', 'top.v')]);
    expect(project.defines, const <String, String>{'WIDTH': '32'});
    expect(project.includePaths, <String>[p.join(dir.path, 'inc')]);
    expect(project.extraYosysCommands, const <String>['flatten']);
    expect(tester.takeException(), isNull);
    await WorkspaceAppHarness.unmount(tester);
  }, variant: macOS);
}
