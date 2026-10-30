// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/app_settings.dart';
import 'package:netcrux/domain/models/custom_cell_symbol/cell_symbol_geometry.dart';
import 'package:netcrux/domain/models/layout/bounding_box.dart';
import 'package:netcrux/domain/models/layout/edge_route.dart';
import 'package:netcrux/domain/models/layout/netlist_layout.dart';
import 'package:netcrux/domain/models/layout/node_position.dart';
import 'package:netcrux/domain/models/netlist/hierarchy_node.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/workspace/netcrux_tab_payload.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/project/providers/current_laid_out_graph_provider.dart';
import 'package:netcrux/features/project/providers/loaded_netlist_provider.dart';
import 'package:netcrux/features/settings/providers/app_settings_provider.dart';
import 'package:netcrux/features/viewer/providers/layout_approval_notifier.dart';
import 'package:netcrux/features/workspace/providers/active_tab_action_flags_provider.dart';
import 'package:netcrux/services/layout/elk_layout_service.dart';
import 'package:netcrux/services/layout/elk_layout_service_provider.dart';
import 'package:netcrux/services/workspace/netcrux_tab_overrides.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_codec.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_notifier.dart';
import 'package:netcrux/services/workspace/tab_container_manager_holder.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/telemetry_test_overrides.dart';

NetlistModel? _model;

class _StubLoadedNetlist extends LoadedNetlist {
  @override
  Future<NetlistModel?> build() async => _model;
}

class _LimitedSettings extends AppSettingsNotifier {
  @override
  Future<AppSettings> build() async =>
      const AppSettings.defaults().copyWith(layoutCellLimit: 10);
}

class _RowLayoutService extends ElkLayoutService {
  @override
  Future<NetlistLayout> layout(
    Module module, {
    CellSymbolGeometries symbols = CellSymbolGeometries.none,
    ElkSubgraph? only,
  }) async => NetlistLayout(
    nodes: <NodePosition>[
      for (final (i, name) in module.cells.keys.indexed)
        NodePosition(
          id: name,
          bounds: BoundingBox(x: i * 100.0, y: 0, width: 80, height: 40),
        ),
    ],
    edges: const <EdgeRoute>[],
    bounds: const BoundingBox(x: 0, y: 0, width: 400, height: 40),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a scope held back for its size still counts as a loaded netlist, and '
      'a laid-out one still does', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    _model = NetlistModel.fromJson(
      jsonDecode(
            File(
              'test/fixtures/verilog/large_chain.expected.json',
            ).readAsStringSync(),
          )
          as Map<String, Object?>,
    );
    final root = ProviderContainer(
      overrides: <Override>[
        ...netcruxTelemetryTestOverrides(),
        netcruxWorkspaceProvider.overrideWith(
          () => NetcruxWorkspaceNotifier(
            service: WorkspaceService<NetcruxTabPayload>(
              codec: const NetcruxWorkspaceCodec(),
              directoryFactory: () async =>
                  Directory.systemTemp.createTempSync('netcrux_flags_test_'),
              logger: (_) {},
            ),
          ),
        ),
        appSettingsProvider.overrideWith(_LimitedSettings.new),
        elkLayoutServiceProvider.overrideWithValue(_RowLayoutService()),
      ],
    );
    addTearDown(root.dispose);
    final manager = TabContainerManager(
      rootContainer: root,
      overridesFactory: (id) => [
        for (final override in netcruxTabOverridesFactory(id))
          if (override.origin != loadedNetlistProvider) override,
        loadedNetlistProvider.overrideWith(_StubLoadedNetlist.new),
      ],
    );
    addTearDown(manager.dispose);
    root.read(tabContainerManagerHolderProvider).manager = manager;
    await root.read(netcruxWorkspaceProvider.future);
    await root.read(appSettingsProvider.future);

    final sub = root.listen(activeTabActionFlagsProvider, (_, _) {});
    addTearDown(sub.close);
    final tabId = await root
        .read(netcruxWorkspaceProvider.notifier)
        .openTab(displayName: 'a', payload: NetcruxTabPayload.empty);
    await root.read(netcruxWorkspaceProvider.future);
    final tab = manager.containerFor(tabId);
    await tab.read(loadedNetlistProvider.future);
    tab.read(hierarchyTreeProvider.notifier).setModel(_model);
    await Future<void>.delayed(Duration.zero);

    // 32 cells over a limit of 10: nothing is drawn, yet the netlist is
    // loaded and the actions that work from it stay available.
    expect(await tab.read(currentLaidOutGraphProvider.future), isNotNull);
    await Future<void>.delayed(Duration.zero);
    expect(sub.read().hasNetlist, isTrue);

    // Lay it out anyway: the laid-out graph is what counts again.
    tab
        .read(layoutApprovalProvider.notifier)
        .approve(tab.read(hierarchyTreeProvider).selected!);
    final laidOut = await tab.read(currentLaidOutGraphProvider.future);
    expect(laidOut.graph.cells, hasLength(32));
    await Future<void>.delayed(Duration.zero);
    expect(sub.read().hasNetlist, isTrue);
  });
}
