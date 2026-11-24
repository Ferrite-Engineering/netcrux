// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';

import 'package:crux_telemetry/crux_telemetry.dart' show kTelemetryConsentKey;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/services/links/incoming_link_service.dart';
import 'package:netcrux/services/links/netcrux_link_providers.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_notifier.dart';
import 'package:path/path.dart' as p;

import '../../../helpers/app_boot_overrides.dart';
import '../../../helpers/workspace_app_harness.dart';

/// The workspace screen is where a `netcrux://` link lands: the one a launch
/// carried and each that reaches the running app go through one inbox, which
/// waits for the launch to settle, asks before opening a file the user has not
/// opened, and then selects the cell or net in the design's tab. These boot
/// the real `NetcruxApp` and drive both routes.

/// The agreement accepted and the telemetry question answered, so neither
/// first-run surface covers the link's confirmation.
const Map<String, Object> _prefs = <String, Object>{
  ...kEulaAcceptedPrefs,
  kTelemetryConsentKey: 'disabled',
};

/// Links the running app receives, delivered when the test says.
class _Links extends IncomingLinkService {
  _Links();

  final StreamController<String> controller = StreamController<String>();

  @override
  Stream<String> get links => controller.stream;
}

void main() {
  late Directory dir;
  late String design;

  setUp(() {
    dir = Directory(
      Directory.systemTemp
          .createTempSync('netcrux_workspace_link_')
          .resolveSymbolicLinksSync(),
    );
    design = p.join(dir.path, 'seed.json');
    File(
      'test/fixtures/netlist/design_seed/generated/design_seed.netlist.json',
    ).copySync(design);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  String link({String? cell, String? net}) => [
    'netcrux://open?file=${Uri.encodeComponent(design)}',
    if (cell != null) 'cell=${Uri.encodeComponent(cell)}',
    if (net != null) 'net=${Uri.encodeComponent(net)}',
  ].join('&');

  int tabCount(WorkspaceAppHarness h) =>
      h.root.read(netcruxWorkspaceProvider).value?.tabs.length ?? 0;

  testWidgets('a launch link is confirmed, then opens the design at its '
      'cell; a later link to the same design selects without asking', (
    tester,
  ) async {
    final incoming = _Links();
    final h = await WorkspaceAppHarness.boot(
      tester,
      preferences: _prefs,
      overrides: [
        initialNetCruxLinksProvider.overrideWithValue(<String>[
          link(cell: 'top.u_cpu.pc_reg'),
        ]),
        incomingLinkServiceProvider.overrideWithValue(incoming),
      ],
    );

    // The file is new to the user, so nothing opens before they answer.
    expect(find.text('Open a design from a link?'), findsOneWidget);
    expect(find.text(design), findsOneWidget);
    expect(tabCount(h), 0);

    await tester.tap(find.byKey(const ValueKey('linkConfirmOpen')));
    await WorkspaceAppHarness.settle(tester);
    expect(find.text('Open a design from a link?'), findsNothing);
    expect(tabCount(h), 1);
    final tab = h.activeTab;
    expect(tab.read(hierarchyTreeProvider).selected?.path, ['u_cpu']);
    expect(
      tab.read(selectedElementProvider).primary,
      const SelectedElement.cell(cellId: 'pc_reg'),
    );

    // The running app receives a second link to the same design: its tab is
    // focused, nothing is asked, and the selection moves to the net.
    incoming.controller.add(link(net: 'top.u_cpu.u_alu.y'));
    await WorkspaceAppHarness.settle(tester);
    expect(find.text('Open a design from a link?'), findsNothing);
    expect(tabCount(h), 1);
    expect(tab.read(hierarchyTreeProvider).selected?.path, ['u_cpu', 'u_alu']);
    expect(tab.read(selectedElementProvider).isNotEmpty, isTrue);
    expect(
      tab.read(selectedElementProvider).primary,
      isNot(const SelectedElement.cell(cellId: 'pc_reg')),
    );

    await incoming.controller.close();
    await WorkspaceAppHarness.unmount(tester);
  });

  testWidgets('Cancel opens nothing', (tester) async {
    final h = await WorkspaceAppHarness.boot(
      tester,
      preferences: _prefs,
      overrides: [
        initialNetCruxLinksProvider.overrideWithValue(<String>[
          link(cell: 'top.dma_reg'),
        ]),
      ],
    );
    expect(find.text('Open a design from a link?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('linkConfirmCancel')));
    await WorkspaceAppHarness.settle(tester);
    expect(find.text('Open a design from a link?'), findsNothing);
    expect(tabCount(h), 0);
    await WorkspaceAppHarness.unmount(tester);
  });

  testWidgets('a refused link says why and opens nothing', (tester) async {
    final h = await WorkspaceAppHarness.boot(
      tester,
      preferences: _prefs,
      overrides: [
        initialNetCruxLinksProvider.overrideWithValue(<String>[
          'netcrux://open?file=rtl/top.v',
        ]),
      ],
    );
    expect(find.text('Open a design from a link?'), findsNothing);
    expect(
      find.text(
        'NetCrux did not open the link because the file is not given as a '
        'full local path.',
      ),
      findsOneWidget,
    );
    expect(tabCount(h), 0);
    await WorkspaceAppHarness.unmount(tester);
  });

  testWidgets('a launch with two links is refused as a whole', (tester) async {
    final h = await WorkspaceAppHarness.boot(
      tester,
      preferences: _prefs,
      overrides: [
        initialNetCruxLinksProvider.overrideWithValue(<String>[
          link(cell: 'top.dma_reg'),
          link(net: 'top.dout'),
        ]),
      ],
    );
    expect(find.text('Open a design from a link?'), findsNothing);
    expect(
      find.text(
        'NetCrux did not open the link because it is not a valid NetCrux '
        'link.',
      ),
      findsOneWidget,
    );
    expect(tabCount(h), 0);
    await WorkspaceAppHarness.unmount(tester);
  });
}
