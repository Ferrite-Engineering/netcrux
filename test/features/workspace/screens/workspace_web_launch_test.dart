// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/web/web_launch_params.dart';
import 'package:netcrux/core/web/web_launch_params_provider.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/project/providers/current_project_provider.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/services/web/web_json_loader.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_notifier.dart';
import 'package:netcrux/services/yosys/prebuilt_netlist_loader.dart';
import 'package:netcrux/services/yosys/prebuilt_netlist_loader_provider.dart';

import '../../../helpers/workspace_app_harness.dart';

/// The browser build's front door, driven through the real `NetcruxApp`
/// launch path with the browser seams set: `?json=` opens the netlist it
/// names, `#scope=` / `#sig=` land on the place they name, a failed fetch
/// says why, and without a URL the start screen offers the one thing a
/// browser can open.
const String _url = 'https://example.com/netlists/design_seed.json';

List<Override> _browser({required NetlistDocumentReader read}) => <Override>[
  hdlElaborationSupportedProvider.overrideWithValue(false),
  prebuiltNetlistLoaderProvider.overrideWithValue(
    PrebuiltNetlistLoader(read: read, parseOnIsolate: false),
  ),
];

Future<String> _seed(String location) async => await File(
  'test/fixtures/netlist/design_seed/generated/design_seed.netlist.json',
).readAsString();

void main() {
  testWidgets('?json= opens the netlist and #scope= / #sig= land on it', (
    tester,
  ) async {
    final fetched = <String>[];
    final h = await WorkspaceAppHarness.boot(
      tester,
      overrides: <Override>[
        ..._browser(
          read: (location) {
            fetched.add(location);
            return _seed(location);
          },
        ),
        webLaunchParamsProvider.overrideWithValue(
          WebLaunchParams.parse(
            queryString: 'json=${Uri.encodeComponent(_url)}',
            fragment: 'scope=top.u_cpu&sig=alu_y',
          ),
        ),
      ],
    );
    final tab = h.activeTab;
    expect(fetched, <String>[_url]);
    expect(tab.read(currentProjectProvider).sourceFiles, <String>[_url]);
    final tree = tab.read(hierarchyTreeProvider);
    expect(tree.model?.topModule?.name, 'top');
    expect(tree.selected?.path, <String>['u_cpu']);
    expect(
      tab.read(selectedElementProvider).primary,
      const SelectedElement.cell(cellId: 'u_alu'),
    );
    final workspace = h.root.read(netcruxWorkspaceProvider).value!;
    expect(workspace.tabs.single.displayName, 'design_seed.json');
    expect(tester.takeException(), isNull);
    await WorkspaceAppHarness.unmount(tester);
  });

  testWidgets('a netlist URL that cannot be fetched explains itself', (
    tester,
  ) async {
    await WorkspaceAppHarness.boot(
      tester,
      overrides: <Override>[
        ..._browser(
          read: (_) async =>
              throw const WebJsonLoadException('Failed to fetch'),
        ),
        webLaunchParamsProvider.overrideWithValue(
          const WebLaunchParams(jsonUrl: _url),
        ),
      ],
    );
    expect(
      find.textContaining('Could not load the netlist from $_url'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await WorkspaceAppHarness.unmount(tester);
  });

  testWidgets('without a URL the start screen offers only a netlist', (
    tester,
  ) async {
    await WorkspaceAppHarness.boot(
      tester,
      overrides: _browser(read: _seed),
    );
    final start = find.byType(FilledButton);
    expect(
      find.descendant(of: start, matching: find.text('Open Netlist JSON…')),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(OutlinedButton, 'Open Source Files…'),
      findsNothing,
    );
    expect(find.textContaining('Yosys write_json'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await WorkspaceAppHarness.unmount(tester);
  });
}
