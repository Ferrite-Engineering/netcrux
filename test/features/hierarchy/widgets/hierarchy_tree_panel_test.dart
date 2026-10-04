// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:crux_a11y/crux_a11y_testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/netlist/cell.dart';
import 'package:netcrux/domain/models/netlist/hierarchy_node.dart';
import 'package:netcrux/domain/models/netlist/module.dart';
import 'package:netcrux/domain/models/netlist/net.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/netlist/port.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/hierarchy/widgets/hierarchy_leaf_row.dart';
import 'package:netcrux/features/hierarchy/widgets/hierarchy_tree_panel.dart';
import 'package:netcrux/features/hierarchy/widgets/hierarchy_tree_row.dart';
import 'package:netcrux/features/project/providers/loaded_netlist_provider.dart';
import 'package:netcrux/features/viewer/providers/reveal_request_notifier.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/yosys/streaming_yosys_json_reader.dart';

NetlistModel _model() {
  Cell cell(String name, String type) => Cell(
    name: name,
    type: type,
    parameters: const {},
    attributes: const {},
    portDirections: const {},
    connections: const {},
  );

  const leaf = Module(
    name: 'leaf',
    attributes: <String, String>{},
    ports: <String, Port>{},
    cells: <String, Cell>{},
    nets: <String, Net>{},
  );
  final cpu = Module(
    name: 'cpu',
    attributes: const <String, String>{},
    ports: const <String, Port>{},
    cells: <String, Cell>{
      'u_alu': cell('u_alu', 'leaf'),
      'u_decode': cell('u_decode', 'leaf'),
      'u_and': cell('u_and', r'$and'),
    },
    nets: const <String, Net>{},
  );
  final top = Module(
    name: 'top',
    attributes: const <String, String>{'top': '1'},
    ports: const <String, Port>{},
    cells: <String, Cell>{
      'u_cpu': cell('u_cpu', 'cpu'),
      'u_dma': cell('u_dma', 'leaf'),
    },
    nets: const <String, Net>{},
  );
  return NetlistModel(
    creator: 'test',
    modules: <String, Module>{
      'top': top,
      'cpu': cpu,
      'leaf': leaf,
    },
  );
}

Widget _wrap({
  required Widget child,
  required ProviderContainer container,
  Locale locale = const Locale('en'),
}) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: L10N.localizationsDelegates,
      supportedLocales: L10N.supportedLocales,
      home: Scaffold(body: SizedBox(width: 320, height: 600, child: child)),
    ),
  );
}

void main() {
  group('buildVisibleRows', () {
    test('empty model produces no rows', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final rows = buildVisibleRows(
        model: const NetlistModel(creator: '', modules: <String, Module>{}),
        state: HierarchyTreeState.empty,
      );
      expect(rows, isEmpty);
    });

    test('root-only when collapsed', () {
      final model = _model();
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(hierarchyTreeProvider.notifier).setModel(model);
      // Initial state expands the root only; descendants depend on
      // explicit expansion in this test (we manually collapse first).
      // setModel auto-expanded the root → still only the root row
      // shows because children of root aren't auto-expanded.
      final state = container.read(hierarchyTreeProvider);
      final rows = buildVisibleRows(model: model, state: state);
      // root row + 1 user-defined child (u_cpu) + 1 leaf instance
      // (u_dma) — both are at depth 1, and the root expansion
      // surfaces them. (u_dma is a leaf module instance; primitives
      // like $and would not appear.)
      expect(rows, hasLength(3));
      expect(rows.first.depth, 0);
      expect(rows.first.instanceName, 'top');
    });

    test('expanding u_cpu reveals its instance children', () {
      final model = _model();
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(hierarchyTreeProvider.notifier)
        ..setModel(model);
      final root = container.read(hierarchyTreeProvider).root!;
      final cpu = root.child(model, 'u_cpu')!;
      notifier.expandScope(cpu);
      final state = container.read(hierarchyTreeProvider);
      final rows = buildVisibleRows(model: model, state: state);
      final names = rows.map((r) => r.instanceName).toList();
      expect(names, containsAllInOrder(<String>['top', 'u_cpu', 'u_alu']));
    });

    test('filter hides non-matching siblings', () {
      final model = _model();
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(hierarchyTreeProvider.notifier)
        ..setModel(model)
        ..setFilterText('alu');
      final state = container.read(hierarchyTreeProvider);
      final rows = buildVisibleRows(model: model, state: state);
      final names = rows.map((r) => r.instanceName).toList();
      // The path that leads to u_alu must remain visible — even
      // though "u_cpu" doesn't match itself, it's on the path.
      expect(names, contains('top'));
      expect(names, contains('u_cpu'));
      expect(names, contains('u_alu'));
      // u_dma (sibling under top, leaf-module) does not match.
      expect(names, isNot(contains('u_dma')));
    });

    test('filter has no matches → empty row list', () {
      final model = _model();
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(hierarchyTreeProvider.notifier)
        ..setModel(model)
        ..setFilterText('nonsense_string');
      final state = container.read(hierarchyTreeProvider);
      final rows = buildVisibleRows(model: model, state: state);
      expect(rows, isEmpty);
    });
  });

  group('HierarchyTreePanel widget', () {
    testWidgets('renders empty-state when no design is loaded', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        _wrap(child: const HierarchyTreePanel(), container: container),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Open a design to browse its hierarchy.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders tree rows when a model is loaded', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(hierarchyTreeProvider.notifier).setModel(_model());
      await tester.pumpWidget(
        _wrap(child: const HierarchyTreePanel(), container: container),
      );
      await tester.pumpAndSettle();
      expect(find.byType(HierarchyTreeRow), findsWidgets);
      expect(find.text('top'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('clicking a row updates the selected scope', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(hierarchyTreeProvider.notifier)
        ..setModel(_model());
      await tester.pumpWidget(
        _wrap(child: const HierarchyTreePanel(), container: container),
      );
      await tester.pumpAndSettle();
      // Tap the second row (u_cpu — auto-shown because root is
      // expanded by setModel).
      final rowFinder = find.byType(HierarchyTreeRow).at(1);
      await tester.tap(rowFinder);
      await tester.pumpAndSettle();
      final selected = container.read(hierarchyTreeProvider).selected!;
      expect(selected.displayName, isNot('top'));
      expect(notifier, isNotNull);
    });

    testWidgets('typing in the filter updates state', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(hierarchyTreeProvider.notifier).setModel(_model());
      await tester.pumpWidget(
        _wrap(child: const HierarchyTreePanel(), container: container),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'alu');
      await tester.pumpAndSettle();
      expect(container.read(hierarchyTreeProvider).filterText, 'alu');
    });

    testWidgets('surfaces elaboration error when loadedNetlistProvider has '
        'errored and no model has been set on the tree', (tester) async {
      final container = ProviderContainer(
        overrides: <Override>[
          loadedNetlistProvider.overrideWith(_ThrowingLoadedNetlist.new),
        ],
      );
      addTearDown(container.dispose);
      // Settle the throwing AsyncNotifier outside the widget tester's
      // fake-async zone so the AsyncError state is visible the first
      // time the panel rebuilds.
      await tester.runAsync(() async {
        final sub = container.listen<AsyncValue<NetlistModel?>>(
          loadedNetlistProvider,
          (previous, next) {},
        );
        addTearDown(sub.close);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
      });
      expect(
        container.read(loadedNetlistProvider).hasError,
        isTrue,
        reason: 'override should have errored by now',
      );
      await tester.pumpWidget(
        _wrap(child: const HierarchyTreePanel(), container: container),
      );
      // Shows the failure message + remediation text — not the stale
      // "Open a design" empty-state placeholder.
      expect(
        find.textContaining('Elaboration failed'),
        findsOneWidget,
        reason:
            'The hierarchy panel must surface elaboration errors so users '
            "don't see a misleading 'Open a design' placeholder when the "
            'project actually pointed at sources but the pipeline failed.',
      );
      expect(
        find.text('Open a design to browse its hierarchy.'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('empty top-module model shows the no-top message', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(hierarchyTreeProvider.notifier)
          .setModel(
            const NetlistModel(creator: '', modules: <String, Module>{}),
          );
      await tester.pumpWidget(
        _wrap(child: const HierarchyTreePanel(), container: container),
      );
      await tester.pumpAndSettle();
      // model is set but topModule == null → root resolves to null,
      // so we expect the "no top" empty-state message.
      expect(
        find.text('The elaborated design has no top module.'),
        findsOneWidget,
      );
    });

    // Locale sweep — open-core convention.
    for (final locale in const <Locale>[
      Locale('en'),
      Locale('zh', 'CN'),
      Locale('zh'),
      Locale('ja'),
      Locale('ko'),
    ]) {
      testWidgets('locale ${locale.toLanguageTag()} pumps cleanly', (
        tester,
      ) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        container.read(hierarchyTreeProvider.notifier).setModel(_model());
        await tester.pumpWidget(
          _wrap(
            child: const HierarchyTreePanel(),
            container: container,
            locale: locale,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('HierarchyTreePanel keyboard (one Tab stop, arrow keys)', () {
    String? focusedRow() {
      final label = FocusManager.instance.primaryFocus?.debugLabel ?? '';
      const prefix = 'Hierarchy row ';
      return label.startsWith(prefix) ? label.substring(prefix.length) : null;
    }

    Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
      await tester.sendKeyEvent(key);
      await tester.pump();
      // A row that had to be scrolled into view is focused after layout.
      await tester.pump();
    }

    Future<ProviderContainer> pumpTree(
      WidgetTester tester, {
      NetlistModel? model,
      double height = 600,
    }) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(hierarchyTreeProvider.notifier)
          .setModel(model ?? _model());
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Scaffold(
              body: SizedBox(
                width: 320,
                height: height,
                child: const HierarchyTreePanel(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('Tab reaches the tree once, on the selected scope, and every '
        'row is one named node with its state', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpTree(tester);

      final walk = await walkFocus(tester);
      expectCleanFocusWalk(walk, context: 'hierarchy panel');
      // The filter field and one row — not three rows plus a chevron.
      expect(
        walk.stops.map((s) => s.line),
        <String>[
          'Filter scopes and cells… edit',
          'top 2 cells button expanded selected',
        ],
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedRow(), 'u_cpu');
      expect(
        describeFocus(tester).line,
        'u_cpu (cpu) 3 cells button collapsed',
      );
      handle.dispose();
    });

    testWidgets('Up, Down, Home and End move between visible rows; Enter '
        'selects', (tester) async {
      final container = await pumpTree(tester);
      await tester.tap(find.text('top'));
      await tester.pump();
      expect(focusedRow(), '');

      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(focusedRow(), '', reason: 'Up on the first row stays');
      await press(tester, LogicalKeyboardKey.end);
      expect(focusedRow(), 'u_dma');
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(focusedRow(), 'u_cpu');
      await press(tester, LogicalKeyboardKey.home);
      expect(focusedRow(), '');
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedRow(), 'u_dma');

      await press(tester, LogicalKeyboardKey.enter);
      expect(
        container.read(hierarchyTreeProvider).selected?.path,
        <String>['u_dma'],
      );
      expect(focusedRow(), 'u_dma', reason: 'selecting keeps focus');
    });

    testWidgets('Right expands then enters; Left collapses then leaves', (
      tester,
    ) async {
      final container = await pumpTree(tester);
      await tester.tap(find.text('u_cpu (cpu)'));
      await tester.pump();
      expect(focusedRow(), 'u_cpu');
      bool expanded() =>
          container.read(hierarchyTreeProvider).expandedKeys.contains('u_cpu');

      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(expanded(), isTrue);
      expect(focusedRow(), 'u_cpu', reason: 'expanding does not move focus');
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(focusedRow(), 'u_cpu/u_alu', reason: 'into the first child');

      // A leaf: Left moves to the parent, and Right does nothing.
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(focusedRow(), 'u_cpu/u_alu');
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(focusedRow(), 'u_cpu');
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(expanded(), isFalse);
      expect(focusedRow(), 'u_cpu');
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(focusedRow(), '', reason: 'a collapsed row moves to its parent');
      expect(tester.takeException(), isNull);
    });

    testWidgets('the Tab stop stays where the arrows left it, and follows a '
        'selection made elsewhere', (tester) async {
      final container = await pumpTree(tester);
      await tester.tap(find.text('top'));
      await tester.pump();
      await press(tester, LogicalKeyboardKey.end);
      expect(focusedRow(), 'u_dma');

      // Out to the filter field and back.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(focusedRow(), isNull);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(focusedRow(), 'u_dma');

      // Leave, change the selection from outside the tree, come back.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      container.read(hierarchyTreeProvider.notifier).selectByPath(<String>[
        'u_cpu',
      ]);
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(focusedRow(), 'u_cpu');
    });

    testWidgets('End reaches a row that was never built, scrolled into view', (
      tester,
    ) async {
      final wide = Module(
        name: 'top',
        attributes: const <String, String>{'top': '1'},
        ports: const <String, Port>{},
        cells: <String, Cell>{
          for (var i = 0; i < 80; i++)
            'u_$i': Cell(
              name: 'u_$i',
              type: 'leaf',
              parameters: const {},
              attributes: const {},
              portDirections: const {},
              connections: const {},
            ),
        },
        nets: const <String, Net>{},
      );
      await pumpTree(
        tester,
        height: 300,
        model: NetlistModel(
          creator: 'test',
          modules: <String, Module>{
            'top': wide,
            'leaf': const Module(
              name: 'leaf',
              attributes: <String, String>{},
              ports: <String, Port>{},
              cells: <String, Cell>{},
              nets: <String, Net>{},
            ),
          },
        ),
      );
      await tester.tap(find.text('top'));
      await tester.pump();
      expect(find.text('u_79 (leaf)'), findsNothing, reason: 'not built yet');

      await press(tester, LogicalKeyboardKey.end);
      expect(focusedRow(), 'u_79');
      expect(find.text('u_79 (leaf)').hitTestable(), findsOneWidget);

      await press(tester, LogicalKeyboardKey.home);
      expect(focusedRow(), '');
      expect(find.text('top').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
  group('filtered cell rows', () {
    HierarchyTreeState filtered(NetlistModel model, String filter) {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(hierarchyTreeProvider.notifier)
        ..setModel(model)
        ..setFilterText(filter);
      return container.read(hierarchyTreeProvider);
    }

    NetlistModel wideModel(int cellCount) {
      Cell cell(String name) => Cell(
        name: name,
        type: 'BUF',
        parameters: const {},
        attributes: const {},
        portDirections: const {},
        connections: const {},
      );
      return NetlistModel(
        creator: 'test',
        modules: <String, Module>{
          'top': Module(
            name: 'top',
            attributes: const <String, String>{'top': '1'},
            ports: const <String, Port>{},
            cells: <String, Cell>{
              for (var i = 0; i < cellCount; i++) 'g$i': cell('g$i'),
            },
            nets: const <String, Net>{},
          ),
        },
      );
    }

    test('lists a matching primitive cell under its scope', () {
      final model = _model();
      final entries = buildHierarchyEntries(
        model: model,
        state: filtered(model, 'u_and'),
      );
      final cells = entries.whereType<HierarchyCellEntry>().toList();
      expect(cells, hasLength(1));
      expect(cells.single.cellName, 'u_and');
      expect(cells.single.cellType, r'$and');
      expect(cells.single.scope.displayName, 'u_cpu');
      // The scope is kept for its cell although its own name does not match,
      // and the cell sits one level under it, right after its row.
      final scopeIndex = entries.indexWhere(
        (entry) =>
            entry is HierarchyVisibleRow && entry.instanceName == 'u_cpu',
      );
      expect(scopeIndex, isNonNegative);
      expect(entries[scopeIndex + 1], same(cells.single));
      expect(cells.single.depth, entries[scopeIndex].depth + 1);
    });

    test('matches the cell type as well as the name', () {
      final model = _model();
      final entries = buildHierarchyEntries(
        model: model,
        state: filtered(model, r'$AND'),
      );
      expect(
        entries.whereType<HierarchyCellEntry>().map((e) => e.cellName),
        ['u_and'],
      );
    });

    test('lists no instance of a user module as a cell row', () {
      final model = _model();
      final entries = buildHierarchyEntries(
        model: model,
        state: filtered(model, 'u_alu'),
      );
      expect(entries.whereType<HierarchyCellEntry>(), isEmpty);
      expect(
        entries.whereType<HierarchyVisibleRow>().map((e) => e.instanceName),
        contains('u_alu'),
      );
    });

    test('produces no cell rows without a filter', () {
      final model = _model();
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(hierarchyTreeProvider.notifier)
        ..setModel(model)
        ..expandScope(HierarchyNode.rootOf(model)!.child(model, 'u_cpu')!);
      final entries = buildHierarchyEntries(
        model: model,
        state: container.read(hierarchyTreeProvider),
      );
      expect(entries.whereType<HierarchyCellEntry>(), isEmpty);
    });

    test('lists a page of cells, then a row counting the rest', () {
      final model = wideModel(250);
      final state = filtered(model, 'g');
      var entries = buildHierarchyEntries(model: model, state: state);
      expect(
        entries.whereType<HierarchyCellEntry>(),
        hasLength(kHierarchyCellPageSize),
      );
      final more = entries.whereType<HierarchyMoreCellsEntry>().single;
      expect(more.hiddenCount, 250 - kHierarchyCellPageSize);
      expect(entries.last, same(more));

      entries = buildHierarchyEntries(
        model: model,
        state: state,
        cellLimitFor: (_) => 2 * kHierarchyCellPageSize,
      );
      expect(
        entries.whereType<HierarchyCellEntry>(),
        hasLength(2 * kHierarchyCellPageSize),
      );
      expect(
        entries.whereType<HierarchyMoreCellsEntry>().single.hiddenCount,
        250 - 2 * kHierarchyCellPageSize,
      );

      entries = buildHierarchyEntries(
        model: model,
        state: state,
        cellLimitFor: (_) => 300,
      );
      expect(entries.whereType<HierarchyCellEntry>(), hasLength(250));
      expect(entries.whereType<HierarchyMoreCellsEntry>(), isEmpty);
    });

    test('serv_ice40: add_cy lists eleven cells in the flat service scope', () {
      final bytes = File(
        'test/fixtures/netlist/serv_ice40/captured/serv_ice40.netlist.json.gz',
      ).readAsBytesSync();
      final model = const StreamingYosysJsonReader().parse(
        utf8.decode(gzip.decode(bytes)),
      );
      final entries = buildHierarchyEntries(
        model: model,
        state: filtered(model, 'add_cy'),
      );
      final scopes = entries.whereType<HierarchyVisibleRow>().toList();
      expect(scopes.map((row) => row.instanceName), ['service']);
      final cells = entries.whereType<HierarchyCellEntry>().toList();
      expect(cells, hasLength(11));
      expect(cells.where((cell) => cell.cellType == 'SB_DFF'), hasLength(1));
      expect(cells.where((cell) => cell.cellType == 'SB_LUT4'), hasLength(10));
      expect(entries.whereType<HierarchyMoreCellsEntry>(), isEmpty);
    });
  });

  group('filtered cell rows in the panel', () {
    Future<ProviderContainer> pumpFiltered(
      WidgetTester tester,
      NetlistModel model,
      String filter,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(hierarchyTreeProvider.notifier).setModel(model);
      await tester.pumpWidget(
        _wrap(child: const HierarchyTreePanel(), container: container),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), filter);
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('a cell row shows its type and is one named node', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpFiltered(tester, _model(), 'u_and');
      final row = find.byType(HierarchyLeafRow);
      expect(row, findsOneWidget);
      expect(
        find.descendant(of: row, matching: find.text('u_and')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.text(r'$and')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(r'Cell u_and, type $and'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      handle.dispose();
    });

    testWidgets('a cell row keeps the tail of its name and tooltips it all', (
      tester,
    ) async {
      await pumpFiltered(tester, _model(), 'u_and');
      final row = tester.widget<HierarchyLeafRow>(
        find.byType(HierarchyLeafRow),
      );
      expect(row.elideLabelStart, isTrue);
      expect(row.tooltip, 'u_and');
      expect(row.label, 'u_and');
    });

    testWidgets('choosing a cell row selects it and reveals it', (
      tester,
    ) async {
      final container = await pumpFiltered(tester, _model(), 'u_and');
      await tester.tap(find.byType(HierarchyLeafRow));
      await tester.pumpAndSettle();
      expect(
        container.read(hierarchyTreeProvider).selected!.displayName,
        'u_cpu',
      );
      expect(
        container.read(selectedElementProvider).primary,
        const SelectedElement.cell(cellId: 'u_and'),
      );
      expect(container.read(revealRequestProvider), 'u_and');
      // The row now reads as the selection.
      expect(
        tester
            .widget<HierarchyLeafRow>(find.byType(HierarchyLeafRow))
            .isSelected,
        isTrue,
      );
    });

    testWidgets('Enter on a focused cell row reveals it too', (tester) async {
      final container = await pumpFiltered(tester, _model(), 'u_and');
      tester
          .widget<HierarchyLeafRow>(find.byType(HierarchyLeafRow))
          .focusNode!
          .requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(container.read(revealRequestProvider), 'u_and');
    });

    testWidgets('the show-more row lists the next page', (tester) async {
      Cell cell(String name) => Cell(
        name: name,
        type: 'BUF',
        parameters: const {},
        attributes: const {},
        portDirections: const {},
        connections: const {},
      );
      final model = NetlistModel(
        creator: 'test',
        modules: <String, Module>{
          'top': Module(
            name: 'top',
            attributes: const <String, String>{'top': '1'},
            ports: const <String, Port>{},
            cells: <String, Cell>{
              for (var i = 0; i < 150; i++) 'g$i': cell('g$i'),
            },
            nets: const <String, Net>{},
          ),
        },
      );
      await pumpFiltered(tester, model, 'g');
      final list = find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      );
      final more = find.text('Show more (50 more matching cells)');
      await tester.scrollUntilVisible(more, 200, scrollable: list);
      // The show-more row is a sentence: it keeps the ordinary end cut.
      final moreRow = tester.widget<HierarchyLeafRow>(
        find.ancestor(of: more, matching: find.byType(HierarchyLeafRow)),
      );
      expect(moreRow.elideLabelStart, isFalse);
      expect(moreRow.tooltip, isNull);
      await tester.tap(more);
      await tester.pumpAndSettle();
      expect(more, findsNothing);
      await tester.scrollUntilVisible(find.text('g149'), 200, scrollable: list);
      expect(find.text('g149'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the no-match message names cells and points at Search', (
      tester,
    ) async {
      await pumpFiltered(tester, _model(), 'nothing_like_this');
      expect(
        find.textContaining('No scopes or cells match the filter'),
        findsOneWidget,
      );
    });
  });
}

class _ThrowingLoadedNetlist extends LoadedNetlist {
  @override
  Future<NetlistModel?> build() async {
    throw const LoadedNetlistException(
      'Yosys is not available: not found on PATH',
    );
  }
}
