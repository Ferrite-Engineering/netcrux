// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_workspace/crux_workspace.dart';
import 'package:crux_yosys/crux_yosys.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/app_settings.dart';
import 'package:netcrux/domain/models/custom_cell_symbol/cell_symbol_geometry.dart';
import 'package:netcrux/domain/models/layout/bounding_box.dart';
import 'package:netcrux/domain/models/layout/edge_route.dart';
import 'package:netcrux/domain/models/layout/netlist_layout.dart';
import 'package:netcrux/domain/models/layout/node_position.dart';
import 'package:netcrux/domain/models/netlist/hierarchy_node.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/project/providers/current_project_provider.dart';
import 'package:netcrux/features/project/providers/loaded_netlist_provider.dart';
import 'package:netcrux/features/settings/providers/app_settings_provider.dart';
import 'package:netcrux/services/layout/elk_layout_service.dart';
import 'package:netcrux/services/layout/elk_layout_service_provider.dart';
import 'package:netcrux/services/reload/source_file_watcher_provider.dart';
import 'package:netcrux/services/workspace/netcrux_tab_overrides.dart';
import 'package:netcrux/services/yosys/yosys_availability_provider.dart';

import 'cxp_test_overrides.dart';
import 'telemetry_test_overrides.dart';

/// A model whose only module, `flat`, holds [cells] inverters wired in a
/// chain (`u0` drives `u1`, and so on) and declares one net per output
/// (`n0`...): the shape of a flat post-synthesis scope.
NetlistModel flatChainModel(int cells) {
  const directions = <String, PortDirection>{
    'A': PortDirection.input,
    'Y': PortDirection.output,
  };
  return NetlistModel(
    creator: 'test',
    modules: <String, Module>{
      'flat': Module(
        name: 'flat',
        attributes: const <String, String>{'top': '1'},
        ports: const <String, Port>{
          'in0': Port(
            name: 'in0',
            direction: PortDirection.input,
            bits: <BitRef>[NetBit(2)],
          ),
        },
        cells: <String, Cell>{
          for (var i = 0; i < cells; i++)
            'u$i': Cell(
              name: 'u$i',
              type: r'$not',
              parameters: const <String, String>{},
              attributes: const <String, String>{},
              portDirections: directions,
              connections: <String, List<BitRef>>{
                'A': <BitRef>[NetBit(i + 2)],
                'Y': <BitRef>[NetBit(i + 3)],
              },
            ),
        },
        nets: <String, Net>{
          for (var i = 0; i < cells; i++)
            'n$i': Net(
              name: 'n$i',
              bits: <BitRef>[NetBit(i + 3)],
              attributes: const <String, String>{},
            ),
        },
      ),
    },
  );
}

/// Lays every node out in a row and counts the layouts it was asked for, and
/// how many of them were of the whole scope rather than of a cone.
class CountingLayoutService extends ElkLayoutService {
  /// Layouts asked for, cone or whole.
  int calls = 0;

  /// Layouts asked for with no cone restriction: the whole scope.
  int wholeScopeCalls = 0;

  @override
  Future<NetlistLayout> layout(
    Module module, {
    CellSymbolGeometries symbols = CellSymbolGeometries.none,
    ElkSubgraph? only,
  }) async {
    calls++;
    if (only == null) wholeScopeCalls++;
    return NetlistLayout(
      nodes: <NodePosition>[
        for (final (i, name) in module.cells.keys.indexed)
          if (only == null || only.cellIds.contains(name))
            NodePosition(
              id: name,
              bounds: BoundingBox(x: i * 100.0, y: 0, width: 80, height: 40),
            ),
      ],
      edges: const <EdgeRoute>[],
      bounds: const BoundingBox(x: 0, y: 0, width: 400, height: 40),
    );
  }
}

class _InstantNetlist extends LoadedNetlist {
  _InstantNetlist(this.model);

  final NetlistModel model;

  @override
  Future<NetlistModel?> build() async {
    ref.watch(currentProjectProvider);
    return model;
  }
}

class _LimitedSettings extends AppSettingsNotifier {
  _LimitedSettings(this.limit);

  final int limit;

  @override
  Future<AppSettings> build() async =>
      const AppSettings.defaults().copyWith(layoutCellLimit: limit);
}

/// One tab over a flat scope of [cells] cells and a layout limit of [limit],
/// built the way the app builds a tab: a root container and the tab's own
/// container with the production per-tab overrides.
class HeldBackTabRig {
  HeldBackTabRig._(this.root, this.manager, this.tab, this.service, this.model);

  /// The app-wide container.
  final ProviderContainer root;

  /// Owns [tab].
  final TabContainerManager manager;

  /// The tab's container.
  final ProviderContainer tab;

  /// Counts the layouts the tab asks for.
  final CountingLayoutService service;

  /// The design the tab loads.
  final NetlistModel model;

  /// Opens the tab. The model is loaded and handed to the tab's hierarchy.
  static Future<HeldBackTabRig> open({
    required int cells,
    required int limit,
  }) async {
    final service = CountingLayoutService();
    final model = flatChainModel(cells);
    final root = ProviderContainer(
      overrides: [
        ...netcruxTelemetryTestOverrides(),
        ...netcruxCxpOffTestOverrides(),
        yosysAvailabilityProvider.overrideWith(
          (ref) async => const YosysAvailability.available(
            executablePath: 'yosys',
            versionString: 'test stub',
          ),
        ),
        sourceFilePollIntervalProvider.overrideWithValue(null),
        elkLayoutServiceProvider.overrideWithValue(service),
        appSettingsProvider.overrideWith(() => _LimitedSettings(limit)),
      ],
    );
    final manager = TabContainerManager(
      rootContainer: root,
      overridesFactory: (id) => [
        for (final override in netcruxTabOverridesFactory(id))
          if (override.origin != loadedNetlistProvider) override,
        loadedNetlistProvider.overrideWith(() => _InstantNetlist(model)),
      ],
    );
    final tab = manager.containerFor(TabId.generate());
    await root.read(appSettingsProvider.future);
    tab.read(currentProjectProvider.notifier).setSourceFiles(const <String>[
      '/design/flat.v',
    ]);
    await tab.read(loadedNetlistProvider.future);
    return HeldBackTabRig._(root, manager, tab, service, model);
  }

  /// Hands the loaded design to the tab's hierarchy, as the tab content does
  /// once elaboration lands, so the top scope is the one on the canvas.
  void showDesign() {
    tab.read(hierarchyTreeProvider.notifier).setModel(model);
  }

  /// Releases the containers.
  void dispose() {
    manager.dispose();
    root.dispose();
  }
}
