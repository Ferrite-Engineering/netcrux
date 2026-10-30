// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// LOCALE_SWEEP_EXEMPT: checks that the canvas shows the held-back view and
// lays out on its button; the view's copy in every locale is swept in
// schematic_layout_deferred_view_test.dart.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crux_workspace/crux_workspace.dart';
import 'package:crux_yosys/crux_yosys.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/app_settings.dart';
import 'package:netcrux/domain/models/custom_cell_symbol/cell_symbol_geometry.dart';
import 'package:netcrux/domain/models/layout/bounding_box.dart';
import 'package:netcrux/domain/models/layout/edge_route.dart';
import 'package:netcrux/domain/models/layout/netlist_layout.dart';
import 'package:netcrux/domain/models/layout/node_position.dart';
import 'package:netcrux/domain/models/netlist/hierarchy_node.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/features/project/providers/current_project_provider.dart';
import 'package:netcrux/features/project/providers/loaded_netlist_provider.dart';
import 'package:netcrux/features/settings/providers/app_settings_provider.dart';
import 'package:netcrux/features/workspace/widgets/project_tab_content.dart';
import 'package:netcrux/features/workspace/widgets/schematic_layout_deferred_view.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/layout/elk_layout_service.dart';
import 'package:netcrux/services/layout/elk_layout_service_provider.dart';
import 'package:netcrux/services/reload/source_file_watcher_provider.dart';
import 'package:netcrux/services/workspace/netcrux_tab_overrides.dart';
import 'package:netcrux/services/yosys/yosys_availability_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/cxp_test_overrides.dart';

class _AnsweredNetlist extends LoadedNetlist {
  _AnsweredNetlist(this.answer);

  final Completer<NetlistModel?> answer;

  @override
  Future<NetlistModel?> build() {
    ref.watch(currentProjectProvider);
    return answer.future;
  }
}

class _LimitedSettings extends AppSettingsNotifier {
  @override
  Future<AppSettings> build() async =>
      const AppSettings.defaults().copyWith(layoutCellLimit: 10);
}

class _CountingLayoutService extends ElkLayoutService {
  int calls = 0;

  @override
  Future<NetlistLayout> layout(
    Module module, {
    CellSymbolGeometries symbols = CellSymbolGeometries.none,
    ElkSubgraph? only,
  }) async {
    calls++;
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('a scope over the layout limit shows its size instead of laying '
      'out, and Lay out anyway lays it out', (tester) async {
    final chain = NetlistModel.fromJson(
      jsonDecode(
            File(
              'test/fixtures/verilog/large_chain.expected.json',
            ).readAsStringSync(),
          )
          as Map<String, Object?>,
    );
    final service = _CountingLayoutService();
    final root = ProviderContainer(
      overrides: [
        ...netcruxCxpOffTestOverrides(),
        yosysAvailabilityProvider.overrideWith(
          (ref) async => const YosysAvailability.available(
            executablePath: 'yosys',
            versionString: 'test stub',
          ),
        ),
        sourceFilePollIntervalProvider.overrideWithValue(null),
        elkLayoutServiceProvider.overrideWithValue(service),
        appSettingsProvider.overrideWith(_LimitedSettings.new),
      ],
    );
    addTearDown(root.dispose);
    final answer = Completer<NetlistModel?>();
    final manager = TabContainerManager(
      rootContainer: root,
      overridesFactory: (id) => [
        for (final override in netcruxTabOverridesFactory(id))
          if (override.origin != loadedNetlistProvider) override,
        loadedNetlistProvider.overrideWith(() => _AnsweredNetlist(answer)),
      ],
    );
    addTearDown(manager.dispose);
    final tab = manager.containerFor(TabId.generate());
    await root.read(appSettingsProvider.future);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: tab,
        child: const MaterialApp(
          localizationsDelegates: [
            L10N.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: L10N.supportedLocales,
          home: Scaffold(body: ProjectTabContent()),
        ),
      ),
    );
    tab.read(currentProjectProvider.notifier).setSourceFiles(const <String>[
      '/design/chain.v',
    ]);
    final loading = tab.read(loadedNetlistProvider.future);
    answer.complete(chain);
    await loading;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Held back: the size is on the canvas, nothing was laid out.
    expect(find.text('This scope is too large to lay out whole'), findsOne);
    expect(find.textContaining('holds 32 cells'), findsOne);
    expect(find.text('Lay out anyway'), findsOne);
    expect(service.calls, 0);

    await tester.tap(find.byKey(SchematicLayoutDeferredView.layOutAnywayKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(service.calls, 1);
    expect(find.text('This scope is too large to lay out whole'), findsNothing);

    expect(tester.takeException(), isNull);
  });
}
