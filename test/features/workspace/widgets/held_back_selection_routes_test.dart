// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// LOCALE_SWEEP_EXEMPT: checks which view the canvas shows for each way of
// selecting a cell in a held-back scope; the view's copy in every locale is
// swept in schematic_layout_deferred_view_test.dart.

import 'dart:async';

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/features/hierarchy/widgets/hierarchy_leaf_row.dart';
import 'package:netcrux/features/hierarchy/widgets/hierarchy_tree_panel.dart';
import 'package:netcrux/features/search/widgets/search_dialog.dart';
import 'package:netcrux/features/viewer/providers/cone_view_notifier.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/features/viewer/widgets/cone_view_banner.dart';
import 'package:netcrux/features/workspace/widgets/project_tab_content.dart';
import 'package:netcrux/features/workspace/widgets/schematic_layout_deferred_view.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/held_back_tab_rig.dart';

const _heldBackTitle = 'This scope is too large to lay out whole';

/// Pumps the tab content over a flat scope of 30 cells with the limit at
/// [limit], and lets the design reach the canvas.
Future<HeldBackTabRig> _pumpTab(WidgetTester tester, {int limit = 10}) async {
  final rig = await HeldBackTabRig.open(cells: 30, limit: limit);
  addTearDown(rig.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: rig.tab,
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
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
  return rig;
}

/// Opens Search from the tab, types [query] and picks the first result.
Future<void> _searchAndPick(WidgetTester tester, String query) async {
  unawaited(SearchDialog.show(tester.element(find.byType(ProjectTabContent))));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.descendant(
      of: find.byType(SearchDialog),
      matching: find.byType(TextField),
    ),
    query,
  );
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(CruxSearchResultTile).first);
  await tester.pumpAndSettle();
}

Future<void> _filterHierarchyAndPick(WidgetTester tester, String query) async {
  await tester.enterText(
    find.descendant(
      of: find.byType(HierarchyTreePanel),
      matching: find.byType(TextField),
    ),
    query,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byType(HierarchyLeafRow).first);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('over the limit', () {
    testWidgets('the held-back view shows until something is selected', (
      tester,
    ) async {
      final rig = await _pumpTab(tester);
      expect(find.text(_heldBackTitle), findsOne);
      expect(find.textContaining('opens its Cone View'), findsOne);
      // Nothing selected: no selection line and no Show Cone View button.
      expect(find.byKey(SchematicLayoutDeferredView.showConeKey), findsNothing);
      expect(rig.service.calls, 0);
    });

    testWidgets('picking a result in Search opens its cone at once', (
      tester,
    ) async {
      final rig = await _pumpTab(tester);
      await _searchAndPick(tester, 'u17');

      expect(find.text(_heldBackTitle), findsNothing);
      expect(find.byType(ConeViewBanner), findsOne);
      expect(find.text('Cone view of u17: 3 of 30 cells'), findsOne);
      expect(
        rig.tab.read(selectedElementProvider).primary,
        const SelectedElement.cell(cellId: 'u17'),
      );
      // Only the cone was laid out, never the 30-cell scope.
      expect(rig.service.calls, 1);
      expect(rig.service.wholeScopeCalls, 0);
    });

    testWidgets('picking a cell in the Hierarchy filter opens its cone at '
        'once', (tester) async {
      final rig = await _pumpTab(tester);
      await _filterHierarchyAndPick(tester, 'u21');

      expect(find.text(_heldBackTitle), findsNothing);
      expect(find.text('Cone view of u21: 3 of 30 cells'), findsOne);
      expect(rig.service.wholeScopeCalls, 0);
    });

    testWidgets('a cross-probe opens the cone of the element it selects', (
      tester,
    ) async {
      final rig = await _pumpTab(tester);
      rig.tab
          .read(selectedElementProvider.notifier)
          .select(const SelectedElement.cell(cellId: 'u9'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text(_heldBackTitle), findsNothing);
      expect(find.text('Cone view of u9: 3 of 30 cells'), findsOne);
      expect(rig.service.wholeScopeCalls, 0);
    });

    testWidgets('Show Whole Scope returns to the held-back view, which names '
        'the selection and offers Show Cone View', (tester) async {
      final rig = await _pumpTab(tester);
      await _searchAndPick(tester, 'u17');
      expect(find.text('Cone view of u17: 3 of 30 cells'), findsOne);

      await tester.tap(find.text('Show Whole Scope'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text(_heldBackTitle), findsOne);
      expect(find.byType(ConeViewBanner), findsOne);
      expect(find.text('Selected: u17'), findsOne);
      expect(rig.tab.read(coneViewProvider), isNull);
      expect(rig.service.wholeScopeCalls, 0);

      await tester.tap(find.byKey(SchematicLayoutDeferredView.showConeKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text(_heldBackTitle), findsNothing);
      expect(find.text('Cone view of u17: 3 of 30 cells'), findsOne);
      expect(rig.service.wholeScopeCalls, 0);
    });

    testWidgets('Lay out anyway still lays the scope out', (tester) async {
      final rig = await _pumpTab(tester);
      await tester.tap(find.byKey(SchematicLayoutDeferredView.layOutAnywayKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text(_heldBackTitle), findsNothing);
      expect(rig.service.wholeScopeCalls, 1);
    });
  });

  group('under the limit', () {
    testWidgets('picking a result in Search lays the scope out and opens no '
        'cone', (tester) async {
      final rig = await _pumpTab(tester, limit: 100);
      expect(find.text(_heldBackTitle), findsNothing);
      await _searchAndPick(tester, 'u17');

      expect(find.byType(ConeViewBanner), findsOne);
      expect(find.textContaining('Cone view of'), findsNothing);
      expect(rig.tab.read(coneViewProvider), isNull);
      expect(rig.service.wholeScopeCalls, greaterThanOrEqualTo(1));
    });

    testWidgets('picking a cell in the Hierarchy filter opens no cone', (
      tester,
    ) async {
      final rig = await _pumpTab(tester, limit: 100);
      await _filterHierarchyAndPick(tester, 'u21');
      expect(rig.tab.read(coneViewProvider), isNull);
      expect(find.textContaining('Cone view of'), findsNothing);
    });
  });
}
