// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Each hierarchy row shows the cell area of its module, summed from the cell
// libraries, and says "partial" when some cell under it has no area; a design
// without cell libraries shows no area at all.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/hierarchy/widgets/hierarchy_tree_panel.dart';
import 'package:netcrux/features/hierarchy/widgets/hierarchy_tree_row.dart';
import 'package:netcrux/features/project/providers/liberty_cell_providers.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/liberty/liberty_cell_index.dart';
import 'package:netcrux/services/liberty/liberty_library.dart';
import 'package:netcrux/services/liberty/liberty_parser.dart';
import 'package:netcrux/services/liberty/module_area_rollup.dart';

Map<String, Object?> _cell(String type) => <String, Object?>{
  'type': type,
  'connections': <String, Object?>{},
};

/// `top` holds two `core` instances and a buffer; `core` holds two NAND2s
/// and an `$and` no library defines. `top.u_io` is a `pads` with only
/// library cells.
final NetlistModel _model = NetlistModel.fromJson(<String, Object?>{
  'creator': 'test',
  'modules': <String, Object?>{
    'top': <String, Object?>{
      'attributes': const <String, Object?>{'top': '1'},
      'cells': <String, Object?>{
        'u_core0': _cell('core'),
        'u_core1': _cell('core'),
        'u_io': _cell('pads'),
        'u_buf': _cell('BUF'),
      },
    },
    'core': <String, Object?>{
      'attributes': const <String, Object?>{},
      'cells': <String, Object?>{
        'n0': _cell('NAND2'),
        'n1': _cell('NAND2'),
        'a': _cell(r'$and'),
      },
    },
    'pads': <String, Object?>{
      'attributes': const <String, Object?>{},
      'cells': <String, Object?>{'b0': _cell('BUF'), 'b1': _cell('BUF')},
    },
  },
});

final LibertyCellIndex _index = LibertyCellIndex(<LibertyLibrary>[
  LibertyParser.parseString('''
library (l) {
  cell (NAND2) { area : 2.5 ; pin (A) { direction : input ; } }
  cell (BUF) { area : 1.25 ; pin (A) { direction : input ; } }
}
'''),
]);

Future<void> _pump(
  WidgetTester tester, {
  required bool libraries,
  Locale locale = const Locale('en'),
}) async {
  final container = ProviderContainer(
    overrides: <Override>[
      moduleAreaRollupProvider.overrideWith(
        (ref) => libraries ? ModuleAreaRollup(_model, _index) : null,
      ),
    ],
  );
  addTearDown(container.dispose);
  // Setting the model expands the root, which shows every scope here.
  container.read(hierarchyTreeProvider.notifier).setModel(_model);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: const Scaffold(
          body: SizedBox(width: 480, height: 600, child: HierarchyTreePanel()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

String? _areaOf(WidgetTester tester, String instance) => tester
    .widget<HierarchyTreeRow>(
      find.byWidgetPredicate(
        (w) => w is HierarchyTreeRow && w.instanceName == instance,
      ),
    )
    .areaLabel;

void main() {
  testWidgets('each scope shows its summed area, partial where a cell has '
      'none', (tester) async {
    await _pump(tester, libraries: true);
    // core: 2 × 2.5, plus an $and with no area.
    expect(_areaOf(tester, 'u_core0'), 'area 5, partial');
    expect(_areaOf(tester, 'u_core1'), 'area 5, partial');
    // pads: 2 × 1.25, all known.
    expect(_areaOf(tester, 'u_io'), 'area 2.5');
    // top: 2 × 5 + 2.5 + 1.25, partial through core.
    expect(_areaOf(tester, 'top'), 'area 13.75, partial');
    expect(find.text('area 2.5'), findsOneWidget);
  });

  testWidgets('the area is read with the row', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, libraries: true);
    expect(
      find.bySemanticsLabel(RegExp(r'^u_io .*\n2 cells\narea 2\.5$')),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('without cell libraries no row shows an area', (tester) async {
    await _pump(tester, libraries: false);
    for (final row in tester.widgetList<HierarchyTreeRow>(
      find.byType(HierarchyTreeRow),
    )) {
      expect(row.areaLabel, isNull, reason: row.instanceName);
    }
    expect(find.textContaining('area'), findsNothing);
  });

  for (final locale in L10N.supportedLocales) {
    testWidgets('the areas render in ${locale.toLanguageTag()}', (
      tester,
    ) async {
      await _pump(tester, libraries: true, locale: locale);
      expect(tester.takeException(), isNull);
      // Every scope here has an area, worded for the locale.
      for (final row in tester.widgetList<HierarchyTreeRow>(
        find.byType(HierarchyTreeRow),
      )) {
        expect(row.areaLabel, isNotNull, reason: row.instanceName);
        expect(row.areaLabel, contains('5'), reason: row.instanceName);
      }
    });
  }
}
