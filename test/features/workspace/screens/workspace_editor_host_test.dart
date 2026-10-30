// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_eula/crux_eula.dart' show CruxEulaAcceptanceDialog;
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/enums/editor_host_kind.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/project/providers/current_project_provider.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/services/host_bridge/editor_host_providers.dart';
import 'package:netcrux/services/host_bridge/host_bridge_messages.dart';
import 'package:netcrux/services/host_bridge/host_netlist_request_provider.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_notifier.dart';
import 'package:netcrux/services/yosys/prebuilt_netlist_loader.dart';
import 'package:netcrux/services/yosys/prebuilt_netlist_loader_provider.dart';

import '../../../helpers/fake_host_bridge_transport.dart';
import '../../../helpers/workspace_app_harness.dart';

/// The editor-host front door, driven through the real `NetcruxApp` with the
/// transport faked: a netlist the host sends as text opens as a tab through
/// the loader a browser upload uses, its hints land on the place they name, a
/// later netlist replaces that tab's design, and the host is told how it went.
final String _seed = File(
  'test/fixtures/netlist/design_seed/generated/design_seed.netlist.json',
).readAsStringSync();

/// Reads a `data:` location the way the web loader reads a `blob:` one.
Future<String> _readLocation(String location) async =>
    Uri.parse(location.split('#').first).data!.contentAsString();

List<Override> _hosted(FakeHostBridgeTransport channel) => <Override>[
  hdlElaborationSupportedProvider.overrideWithValue(false),
  prebuiltNetlistLoaderProvider.overrideWithValue(
    const PrebuiltNetlistLoader(read: _readLocation, parseOnIsolate: false),
  ),
  hostBridgeChannelProvider.overrideWithValue(channel),
  editorHostKindProvider.overrideWithValue(EditorHostKind.vscode),
];

Map<String, Object?> _open(String text, {Map<String, Object?>? hints}) =>
    <String, Object?>{
      'type': kHostBridgeFrameType,
      'protocol': 1,
      'kind': kHostBridgeOpenNetlistKind,
      'name': 'design_seed.json',
      'text': text,
      ...?hints,
    };

List<String> _phases(FakeHostBridgeTransport channel) => <String>[
  for (final frame in channel.posted)
    if (frame['kind'] == kHostBridgeStatusKind) frame['phase']! as String,
];

void main() {
  testWidgets('a netlist from the host opens as a tab and lands on its hints', (
    tester,
  ) async {
    final channel = FakeHostBridgeTransport();
    final h = await WorkspaceAppHarness.boot(
      tester,
      overrides: _hosted(channel),
    );
    h.root.read(editorHostBridgeProvider);
    channel.receive(
      _open(
        _seed,
        hints: <String, Object?>{
          'scope': 'top.u_cpu',
          'signal': 'alu_y',
        },
      ),
    );
    await WorkspaceAppHarness.settle(tester);

    final tab = h.activeTab;
    expect(tab.read(currentProjectProvider).sourceFiles, hasLength(1));
    final tree = tab.read(hierarchyTreeProvider);
    expect(tree.model?.topModule?.name, 'top');
    expect(tree.selected?.path, <String>['u_cpu']);
    expect(
      tab.read(selectedElementProvider).primary,
      const SelectedElement.cell(cellId: 'u_alu'),
    );
    final workspace = h.root.read(netcruxWorkspaceProvider).value!;
    expect(workspace.tabs.single.displayName, 'design_seed.json');
    expect(_phases(channel), <String>['loading', 'loaded']);
    final loaded = channel.posted.last;
    expect(loaded['modules'], greaterThan(0));
    expect(loaded['cells'], greaterThan(0));
    // The request's text is released as soon as the workspace has taken it.
    expect(h.root.read(hostNetlistRequestProvider), isNull);
    expect(tester.takeException(), isNull);
    await WorkspaceAppHarness.unmount(tester);
  });

  testWidgets('a netlist sent again replaces the design in the same tab', (
    tester,
  ) async {
    final channel = FakeHostBridgeTransport();
    final h = await WorkspaceAppHarness.boot(
      tester,
      overrides: _hosted(channel),
    );
    h.root.read(editorHostBridgeProvider);
    channel.receive(_open(_seed));
    await WorkspaceAppHarness.settle(tester);
    final first = h.activeTab.read(currentProjectProvider).sourceFiles.single;

    // Blank space at the end: a different document, as a file saved again.
    channel.receive(_open('$_seed '));
    await WorkspaceAppHarness.settle(tester);

    final workspace = h.root.read(netcruxWorkspaceProvider).value!;
    expect(workspace.tabs, hasLength(1));
    expect(
      h.activeTab.read(currentProjectProvider).sourceFiles.single,
      isNot(first),
    );
    expect(_phases(channel), <String>[
      'loading',
      'loaded',
      'loading',
      'loaded',
    ]);
    expect(tester.takeException(), isNull);
    await WorkspaceAppHarness.unmount(tester);
  });

  testWidgets('a document that is not a netlist is reported to the host', (
    tester,
  ) async {
    final channel = FakeHostBridgeTransport();
    final h = await WorkspaceAppHarness.boot(
      tester,
      overrides: _hosted(channel),
    );
    h.root.read(editorHostBridgeProvider);
    channel.receive(_open('{"not":"a netlist"'));
    await WorkspaceAppHarness.settle(tester);

    expect(_phases(channel), <String>['loading', 'failed']);
    expect(channel.posted.last['message'], isNotEmpty);
    expect(
      find.textContaining('Could not open design_seed.json'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await WorkspaceAppHarness.unmount(tester);
  });

  testWidgets('hosted, no license agreement is put in front of the viewer', (
    tester,
  ) async {
    final channel = FakeHostBridgeTransport();
    await WorkspaceAppHarness.boot(tester, overrides: _hosted(channel));
    expect(find.byType(CruxEulaAcceptanceDialog), findsNothing);
    expect(tester.takeException(), isNull);
    await WorkspaceAppHarness.unmount(tester);
  });

  testWidgets('standalone, the same boot does ask for the agreement', (
    tester,
  ) async {
    // The control for the test above: with nothing hosting the build and no
    // acceptance on record the dialog is up, so its absence there is the
    // host's doing and not an artifact of the harness.
    await WorkspaceAppHarness.boot(
      tester,
      overrides: <Override>[
        hdlElaborationSupportedProvider.overrideWithValue(false),
      ],
    );
    expect(find.byType(CruxEulaAcceptanceDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
    await WorkspaceAppHarness.unmount(tester);
  });
}
