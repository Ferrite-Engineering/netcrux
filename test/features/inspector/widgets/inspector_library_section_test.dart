// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The Inspector's cell-library data sheet: a selected standard cell shows its
// function, storage, area, pins, power and ground pins, the library file the
// design uses and every library that defines it; a selected instance of a
// module of the design shows the area of the cells inside it.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/layout/bounding_box.dart';
import 'package:netcrux/domain/models/layout/edge_route.dart';
import 'package:netcrux/domain/models/layout/netlist_layout.dart';
import 'package:netcrux/domain/models/layout/node_position.dart';
import 'package:netcrux/domain/models/netlist/hierarchy_node.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/schematic/laid_out_graph.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/inspector/widgets/inspector_panel.dart';
import 'package:netcrux/features/project/providers/current_laid_out_graph_provider.dart';
import 'package:netcrux/features/project/providers/liberty_cell_providers.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/liberty/liberty_cell_index.dart';
import 'package:netcrux/services/liberty/liberty_library.dart';
import 'package:netcrux/services/liberty/liberty_parser.dart';
import 'package:netcrux/services/liberty/module_area_rollup.dart';
import 'package:netcrux/services/schematic/schematic_graph_builder.dart';

String _cells(String corner) =>
    '''
library ($corner) {
  cell (NAND2) {
    area : 3.75 ;
    pg_pin (VPWR) { pg_type : primary_power ; }
    pg_pin (VGND) { pg_type : primary_ground ; }
    pg_pin (VSUB) { }
    pin (A) { direction : input ; }
    pin (B) { direction : input ; }
    pin (Y) { direction : output ; function : "!(A&B)" ; }
  }
  cell (DFFR) {
    area : 20 ;
    ff (IQ, IQN) { clocked_on : "CLK" ; next_state : "D" ; clear : "!RST_B" ; }
    pin (CLK) { direction : input ; clock : true ; }
    pin (D) { direction : input ; }
    pin (RST_B) { direction : input ; }
    pin (Q) { direction : output ; function : "IQ" ; }
  }
  cell (INV) {
    area : 1.5 ;
    pin (A) { direction : input ; }
    pin (Y) { direction : output ; function : "!A" ; }
  }
}
''';

final LibertyCellIndex _index = LibertyCellIndex(<LibertyLibrary>[
  LibertyParser.parseString(_cells('cells_tt'), path: '/pdk/lib/tt.lib'),
  LibertyParser.parseString(_cells('cells_ss'), path: '/pdk/lib/ss.lib'),
]);

Map<String, Object?> _cell(String type) => <String, Object?>{
  'type': type,
  'connections': <String, Object?>{},
};

final NetlistModel _model = NetlistModel.fromJson(<String, Object?>{
  'creator': 'test',
  'modules': <String, Object?>{
    'top': <String, Object?>{
      'attributes': const <String, Object?>{'top': '1'},
      'cells': <String, Object?>{
        'u_nand': _cell('NAND2'),
        'u_ff': _cell('DFFR'),
        'u_sub': _cell('sub'),
        'u_and': _cell(r'$and'),
      },
    },
    'sub': <String, Object?>{
      'attributes': const <String, Object?>{},
      'cells': <String, Object?>{
        'i0': _cell('INV'),
        'i1': _cell('INV'),
        'x': _cell(r'$xor'),
      },
    },
    for (final name in <String>['NAND2', 'DFFR', 'INV'])
      name: <String, Object?>{
        'attributes': <String, Object?>{'blackbox': '1'},
      },
  },
});

ProviderContainer _container() {
  final root = HierarchyNode.rootOf(_model)!;
  final symbols = _index.symbolsFor(_model);
  final container = ProviderContainer(
    overrides: <Override>[
      currentLaidOutGraphProvider.overrideWith(
        (ref) async => LaidOutGraph(
          graph: SchematicGraphBuilder(liberty: symbols).build(_model, root),
          layout: const NetlistLayout(
            nodes: <NodePosition>[],
            edges: <EdgeRoute>[],
            bounds: BoundingBox(x: 0, y: 0, width: 0, height: 0),
          ),
        ),
      ),
      libertyCellIndexProvider.overrideWith((ref) async => _index),
      libertyCellSymbolsProvider.overrideWith((ref) async => symbols),
      moduleAreaRollupProvider.overrideWith(
        (ref) => ModuleAreaRollup(_model, _index),
      ),
    ],
  );
  container.read(hierarchyTreeProvider.notifier).setModel(_model);
  return container;
}

Future<void> _show(
  WidgetTester tester,
  String cellId, {
  Locale locale = const Locale('en'),
}) async {
  final container = _container();
  addTearDown(container.dispose);
  container
      .read(selectedElementProvider.notifier)
      .select(SelectedElement.cell(cellId: cellId));
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: const Scaffold(
          body: SizedBox(width: 420, height: 1200, child: InspectorPanel()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a gate shows its function, area, pins and libraries', (
    tester,
  ) async {
    await _show(tester, 'u_nand');
    expect(find.text('Cell library'), findsOneWidget);
    expect(find.text('nandGate'), findsOneWidget);
    expect(find.text('Y = !(A&B)'), findsOneWidget);
    expect(find.text('3.75'), findsOneWidget);
    expect(find.text('/pdk/lib/tt.lib'), findsOneWidget);
    expect(find.text('Defined in'), findsOneWidget);
    expect(find.text('cells_tt (tt.lib)'), findsOneWidget);
    expect(find.text('cells_ss (ss.lib)'), findsOneWidget);
    expect(find.text('Library pins'), findsOneWidget);
    expect(find.text('Power and ground pins'), findsOneWidget);
    expect(find.text('primary_power'), findsOneWidget);
    expect(find.text('primary_ground'), findsOneWidget);
    expect(find.text('no pg_type'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a flip-flop shows its storage, its clear and its clock pin', (
    tester,
  ) async {
    await _show(tester, 'u_ff');
    expect(
      find.text('Flip-flop, next state D, clocked on CLK'),
      findsOneWidget,
    );
    expect(find.text('!RST_B'), findsOneWidget);
    expect(find.text('input, clock'), findsOneWidget);
    expect(find.text('Q = IQ'), findsOneWidget);
    // No supply pins, no section for them.
    expect(find.text('Power and ground pins'), findsNothing);
  });

  testWidgets('an instance of a module shows the area summed inside it, '
      'partial when a cell has none', (tester) async {
    await _show(tester, 'u_sub');
    // Two INV of 1.5; the $xor has no area.
    expect(find.text('Area'), findsOneWidget);
    expect(find.text('3 (partial)'), findsOneWidget);
    expect(find.text('Cell library'), findsNothing);
  });

  testWidgets('a cell no library defines has no data sheet', (tester) async {
    await _show(tester, 'u_and');
    expect(find.text('Cell library'), findsNothing);
    expect(find.text('Area'), findsNothing);
  });

  for (final locale in L10N.supportedLocales) {
    testWidgets('pumps cleanly in ${locale.toLanguageTag()}', (tester) async {
      await _show(tester, 'u_ff', locale: locale);
      expect(tester.takeException(), isNull);
      await _show(tester, 'u_sub', locale: locale);
      expect(tester.takeException(), isNull);
    });
  }
}
