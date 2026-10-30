// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/cli/cli_launch_intent.dart';
import 'package:netcrux/domain/models/workspace/netcrux_tab_payload.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/project/providers/current_project_provider.dart';
import 'package:netcrux/features/project/providers/loaded_netlist_provider.dart';
import 'package:netcrux/features/settings/providers/app_settings_provider.dart';
import 'package:netcrux/features/workspace/widgets/schematic_elaboration_progress_view.dart';
import 'package:netcrux/features/workspace/widgets/schematic_layout_deferred_view.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_codec.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_notifier.dart';
import 'package:netcrux/services/yosys/prebuilt_netlist_loader.dart';
import 'package:netcrux/services/yosys/prebuilt_netlist_loader_provider.dart';
import 'package:path/path.dart' as p;

import '../../../helpers/app_boot_overrides.dart';
import '../../../helpers/workspace_app_harness.dart';

/// A netlist JSON document with [cells] AND gates in its top module.
String _netlist(int cells) => jsonEncode(<String, Object?>{
  'creator': 'tab switching test',
  'modules': <String, Object?>{
    'top': <String, Object?>{
      'attributes': <String, Object?>{'top': '1'},
      'ports': <String, Object?>{
        'a': <String, Object?>{
          'direction': 'input',
          'bits': <Object>[2],
        },
      },
      'cells': <String, Object?>{
        for (var i = 0; i < cells; i++)
          'u$i': <String, Object?>{
            'hide_name': 0,
            'type': r'$and',
            'parameters': <String, Object?>{},
            'attributes': <String, Object?>{},
            'port_directions': <String, Object?>{'A': 'input', 'Y': 'output'},
            'connections': <String, Object?>{
              'A': <Object>[2],
              'Y': <Object>[3 + i],
            },
          },
      },
      'netnames': <String, Object?>{},
    },
  },
});

/// Reads of netlist documents that each wait for the test to release them,
/// so a test decides when a large design "finishes loading".
class _Documents {
  final Map<String, Completer<String>> _pending = <String, Completer<String>>{};

  Future<String> read(String location) =>
      (_pending[location] ??= Completer<String>()).future;

  void release(String location, String document) =>
      (_pending[location] ??= Completer<String>()).complete(document);
}

/// A design that is in the middle of being read, then read, in a tab the user
/// has left and come back to: the tab always shows its design, the progress of
/// its load, or what stopped it. Never the "Open Project..." placeholder of a
/// tab with nothing in it.
void main() {
  late Directory dir;
  setUp(
    () => dir = Directory(
      Directory.systemTemp
          .createTempSync('netcrux_tab_switching_')
          .resolveSymbolicLinksSync(),
    ),
  );
  tearDown(() => dir.deleteSync(recursive: true));
  final macOS = TargetPlatformVariant.only(TargetPlatform.macOS);

  Future<WorkspaceAppHarness> boot(
    WidgetTester tester,
    _Documents documents, {
    CliLaunchIntent intent = const CliLaunchIntent.empty(),
    Directory? workspaceDirectory,
  }) => WorkspaceAppHarness.boot(
    tester,
    intent: intent,
    workspaceDirectory: workspaceDirectory,
    preferences: kEulaAcceptedPrefs,
    overrides: [
      prebuiltNetlistLoaderProvider.overrideWithValue(
        PrebuiltNetlistLoader(read: documents.read, parseOnIsolate: false),
      ),
    ],
  );

  /// Opens [path] as a new tab the way the Open Source Files flow does:
  /// the tab first, then the project into the tab that is now active.
  Future<TabId> openTab(
    WidgetTester tester,
    WorkspaceAppHarness h,
    String path,
  ) async {
    final id = await tester.runAsync(
      () => h.root
          .read(netcruxWorkspaceProvider.notifier)
          .openTab(
            displayName: p.basename(path),
            payload: NetcruxTabPayload(sourceFiles: <String>[path]),
          ),
    );
    h.tabs
        .containerFor(id!)
        .read(currentProjectProvider.notifier)
        .setSourceFiles(<String>[path]);
    await WorkspaceAppHarness.settle(tester);
    return id;
  }

  Future<void> switchTo(
    WidgetTester tester,
    WorkspaceAppHarness h,
    TabId id,
  ) async {
    await tester.runAsync(
      () => h.root.read(netcruxWorkspaceProvider.notifier).setActiveTab(id),
    );
    await WorkspaceAppHarness.settle(tester);
  }

  L10N l10nOf(WidgetTester tester) =>
      L10N.of(tester.element(find.byType(Scaffold).first));

  TabId activeId(WorkspaceAppHarness h) =>
      h.root.read(netcruxWorkspaceProvider).value!.activeTabId!;

  testWidgets('a tab left while its netlist is being read still shows that '
      'read when it is switched back to', (tester) async {
    final documents = _Documents();
    final big = p.join(dir.path, 'big.json');
    final small = p.join(dir.path, 'small.json');
    final h = await boot(
      tester,
      documents,
      intent: CliLaunchIntent.openSourceFiles(<String>[big]),
    );
    final bigTab = activeId(h);
    expect(find.byType(SchematicElaborationProgressView), findsOneWidget);

    final smallTab = await openTab(tester, h, small);
    documents.release(small, _netlist(2));
    await WorkspaceAppHarness.settle(tester);
    expect(
      h.tabs.containerFor(smallTab).read(loadedNetlistProvider).value,
      isNotNull,
    );

    await switchTo(tester, h, bigTab);
    expect(
      h.tabs.containerFor(bigTab).read(currentProjectProvider).sourceFiles,
      <String>[big],
    );
    expect(find.byType(SchematicElaborationProgressView), findsOneWidget);
    expect(find.text(l10nOf(tester).actionOpenProject), findsNothing);

    documents.release(big, _netlist(3));
    await WorkspaceAppHarness.settle(tester);
    expect(
      h.tabs.containerFor(bigTab).read(loadedNetlistProvider).value,
      isNotNull,
    );
    expect(
      h.tabs.containerFor(bigTab).read(hierarchyTreeProvider).model,
      isNotNull,
    );
    expect(find.byType(SchematicElaborationProgressView), findsNothing);
    expect(tester.takeException(), isNull);
    await WorkspaceAppHarness.unmount(tester);
  }, variant: macOS);

  testWidgets('a scope held back for its size is still held back, not '
      'blank, when its tab is switched back to', (tester) async {
    final documents = _Documents();
    final big = p.join(dir.path, 'big.json');
    final small = p.join(dir.path, 'small.json');
    final h = await boot(
      tester,
      documents,
      intent: CliLaunchIntent.openSourceFiles(<String>[big]),
    );
    await h.root.read(appSettingsProvider.notifier).setLayoutCellLimit(2);
    final bigTab = activeId(h);
    documents.release(big, _netlist(5));
    await WorkspaceAppHarness.settle(tester);
    expect(find.byKey(SchematicLayoutDeferredView.layOutAnywayKey), findsOne);

    final smallTab = await openTab(tester, h, small);
    documents.release(small, _netlist(1));
    await WorkspaceAppHarness.settle(tester);
    expect(
      find.byKey(SchematicLayoutDeferredView.layOutAnywayKey),
      findsNothing,
    );

    await switchTo(tester, h, bigTab);
    expect(find.byKey(SchematicLayoutDeferredView.layOutAnywayKey), findsOne);
    expect(find.text(l10nOf(tester).actionOpenProject), findsNothing);
    expect(smallTab, isNot(bigTab));
    expect(tester.takeException(), isNull);
    await WorkspaceAppHarness.unmount(tester);
  }, variant: macOS);

  testWidgets('a restored tab that names a netlist is read when it is first '
      'shown, whichever tab was active', (tester) async {
    final documents = _Documents();
    final big = p.join(dir.path, 'big.json');
    final other = p.join(dir.path, 'other.json');
    final wsDir = Directory(p.join(dir.path, 'ws'))..createSync();
    final pane = PaneId.generate();
    final bigTab = TabId.generate();
    final otherTab = TabId.generate();
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
                  id: bigTab,
                  displayName: 'big.json',
                  paneId: pane,
                  payload: NetcruxTabPayload(sourceFiles: <String>[big]),
                ),
                WorkspaceTab<NetcruxTabPayload>(
                  id: otherTab,
                  displayName: 'other.json',
                  paneId: pane,
                  payload: NetcruxTabPayload(sourceFiles: <String>[other]),
                ),
              ],
              panes: <WorkspacePane>[
                WorkspacePane(id: pane, activeTabId: bigTab),
              ],
              activePaneId: pane,
            ),
          ),
    );
    // A launch that names a file of its own, as `netcrux file.v` does.
    final extra = p.join(dir.path, 'extra.json');
    final h = await boot(
      tester,
      documents,
      workspaceDirectory: wsDir,
      intent: CliLaunchIntent.openSourceFiles(<String>[extra]),
    );
    documents
      ..release(extra, _netlist(1))
      ..release(big, _netlist(2))
      ..release(other, _netlist(3));
    await WorkspaceAppHarness.settle(tester);

    await switchTo(tester, h, bigTab);
    expect(find.text(l10nOf(tester).actionOpenProject), findsNothing);
    expect(
      h.tabs.containerFor(bigTab).read(loadedNetlistProvider).value,
      isNotNull,
    );

    await switchTo(tester, h, otherTab);
    expect(find.text(l10nOf(tester).actionOpenProject), findsNothing);
    expect(
      h.tabs.containerFor(otherTab).read(loadedNetlistProvider).value,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
    await WorkspaceAppHarness.unmount(tester);
  }, variant: macOS);

  testWidgets('a tab opened with sources in its payload and no project is '
      'given its design when it is first shown', (tester) async {
    final documents = _Documents();
    final path = p.join(dir.path, 'design.json');
    final h = await boot(tester, documents);
    documents.release(path, _netlist(2));

    // What any route that creates the tab but never pushes its project
    // leaves: the payload names the sources, the tab's own state does not.
    final id = await tester.runAsync(
      () => h.root
          .read(netcruxWorkspaceProvider.notifier)
          .openTab(
            displayName: 'design.json',
            payload: NetcruxTabPayload(sourceFiles: <String>[path]),
          ),
    );
    await WorkspaceAppHarness.settle(tester);

    final tab = h.tabs.containerFor(id!);
    expect(tab.read(currentProjectProvider).sourceFiles, <String>[path]);
    expect(tab.read(loadedNetlistProvider).value, isNotNull);
    expect(find.text(l10nOf(tester).actionOpenProject), findsNothing);
    expect(tester.takeException(), isNull);
    await WorkspaceAppHarness.unmount(tester);
  }, variant: macOS);
}
