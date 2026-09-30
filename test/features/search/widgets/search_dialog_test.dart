// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/netlist/bit_ref.dart';
import 'package:netcrux/domain/models/netlist/cell.dart';
import 'package:netcrux/domain/models/netlist/module.dart';
import 'package:netcrux/domain/models/netlist/net.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/netlist/port_direction.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/search/widgets/search_dialog.dart';
import 'package:netcrux/features/viewer/providers/reveal_request_notifier.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/yosys/yosys_json_parser.dart';
import '../../../helpers/telemetry_test_overrides.dart';

/// The committed three-level fixture design: `top` instantiates `u_cpu`
/// (module `cpu`) plus the `$dff` cell `dma_reg`, and carries the nets
/// `clk` / `rst` / `cpu_dout` / `dout`. Parsed through the production
/// Yosys-JSON path so the regression test pins the shape the app really
/// searches, not a hand-built model.
NetlistModel _fixtureModel() => const YosysJsonParser().parse(
  File(
    'test/fixtures/netlist/design_seed/generated/design_seed.netlist.json',
  ).readAsStringSync(),
);

NetlistModel _model({String cellName = 'alu_adder'}) => NetlistModel(
  creator: 'test',
  modules: <String, Module>{
    'top': Module(
      name: 'top',
      attributes: const <String, String>{'top': '1'},
      ports: const {},
      cells: <String, Cell>{
        cellName: Cell(
          name: cellName,
          type: r'$add',
          parameters: const <String, String>{},
          attributes: const <String, String>{},
          portDirections: const <String, PortDirection>{},
          connections: const <String, List<BitRef>>{},
        ),
      },
      nets: const <String, Net>{},
    ),
  },
);

Future<void> _pumpDialog(
  WidgetTester tester,
  ProviderContainer container, {
  Locale locale = const Locale('en'),
}) {
  return tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: const <LocalizationsDelegate<Object?>>[
          L10N.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: L10N.supportedLocales,
        home: const Scaffold(body: SearchDialog()),
      ),
    ),
  );
}

/// Pumps a host route and opens the dialog through [SearchDialog.show], so
/// activating a result pops a real dialog route instead of the app's only
/// page. [container] plays the active tab's container.
Future<void> _pumpHostedDialog(
  WidgetTester tester,
  ProviderContainer container, {
  Locale locale = const Locale('en'),
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: const <LocalizationsDelegate<Object?>>[
        L10N.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: L10N.supportedLocales,
      home: ProviderScope(
        overrides: netcruxTelemetryTestOverrides(),
        child: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => SearchDialog.show(context, container: container),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

/// The localizations the dialog itself resolved, for asserting on its
/// localized empty-state and kind-chip strings without hardcoding them.
L10N _l10n(WidgetTester tester) =>
    L10N.of(tester.element(find.byType(SearchDialog)));

/// Types [query] into the dialog's field and waits out the debounce.
Future<void> _search(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(TextField), query);
  await tester.pump(const Duration(milliseconds: 250));
}

void main() {
  group('SearchDialog debounce', () {
    testWidgets('a search runs only after the 200 ms debounce, not per '
        'keystroke', (tester) async {
      final container = ProviderContainer(
        overrides: netcruxTelemetryTestOverrides(),
      );
      addTearDown(container.dispose);
      container.read(hierarchyTreeProvider.notifier).setModel(_model());
      await _pumpDialog(tester, container);

      await tester.enterText(find.byType(TextField), 'alu');
      // Within the debounce window: no search has run yet.
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('alu_adder'), findsNothing);

      // Cross the 200 ms threshold: the walk runs and results appear.
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.text('alu_adder'), findsOneWidget);
    });

    testWidgets('rapid typing coalesces — each keystroke resets the timer', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: netcruxTelemetryTestOverrides(),
      );
      addTearDown(container.dispose);
      container.read(hierarchyTreeProvider.notifier).setModel(_model());
      await _pumpDialog(tester, container);

      // First keystroke burst (non-matching), then a second 100 ms later.
      await tester.enterText(find.byType(TextField), 'zz');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(find.byType(TextField), 'alu');
      // Only 100 ms since the *last* keystroke — the reset timer hasn't fired.
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('alu_adder'), findsNothing);

      // 200 ms after the last keystroke: exactly one trailing search runs.
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.text('alu_adder'), findsOneWidget);
    });

    testWidgets('clearing the query clears results immediately (no wait)', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: netcruxTelemetryTestOverrides(),
      );
      addTearDown(container.dispose);
      container.read(hierarchyTreeProvider.notifier).setModel(_model());
      await _pumpDialog(tester, container);

      await tester.enterText(find.byType(TextField), 'alu');
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('alu_adder'), findsOneWidget);

      // Emptying the field clears synchronously — no debounce to wait out.
      await tester.enterText(find.byType(TextField), '');
      await tester.pump();
      expect(find.text('alu_adder'), findsNothing);
    });
  });

  group('SearchDialog.show scopes to the passed active-tab container', () {
    testWidgets('searches and applies to the passed container, not the '
        'ambient root scope', (tester) async {
      // Ambient root scope holds one design; the "active tab" container
      // holds a different design. The dialog mounts under the root
      // navigator (outside the tab scope), so before the container is
      // threaded through it would read the root model and apply the
      // selection to the root container.
      final rootContainer = ProviderContainer(
        overrides: netcruxTelemetryTestOverrides(),
      );
      addTearDown(rootContainer.dispose);
      rootContainer
          .read(hierarchyTreeProvider.notifier)
          .setModel(_model(cellName: 'root_only_cell'));

      final tabContainer = ProviderContainer(
        overrides: netcruxTelemetryTestOverrides(),
      );
      addTearDown(tabContainer.dispose);
      tabContainer
          .read(hierarchyTreeProvider.notifier)
          .setModel(_model(cellName: 'tab_only_cell'));

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: rootContainer,
          child: MaterialApp(
            localizationsDelegates: const <LocalizationsDelegate<Object?>>[
              L10N.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: L10N.supportedLocales,
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () =>
                      SearchDialog.show(context, container: tabContainer),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'cell');
      await tester.pump(const Duration(milliseconds: 250));

      // Only the active tab's cell matches — the root design's cell never
      // surfaces through a dialog scoped to the tab container.
      expect(find.text('tab_only_cell'), findsOneWidget);
      expect(find.text('root_only_cell'), findsNothing);

      // Applying the result mutates the active tab's selection, not root.
      await tester.tap(find.text('tab_only_cell'));
      await tester.pumpAndSettle();

      final tabSelection = tabContainer.read(selectedElementProvider).primary;
      expect(
        tabSelection,
        isA<SelectedElementCell>().having(
          (s) => s.cellId,
          'cellId',
          'tab_only_cell',
        ),
      );
      expect(
        rootContainer.read(selectedElementProvider).primary,
        isA<SelectedElementNone>(),
      );
    });
  });

  group('SearchDialog over a loaded fixture netlist', () {
    late NetlistModel fixture;

    setUpAll(() => fixture = _fixtureModel());

    ProviderContainer loadedContainer() {
      final container = ProviderContainer(
        overrides: netcruxTelemetryTestOverrides(),
      );
      addTearDown(container.dispose);
      container.read(hierarchyTreeProvider.notifier).setModel(fixture);
      return container;
    }

    testWidgets('a module-instance name returns an instance hit', (
      tester,
    ) async {
      await _pumpHostedDialog(tester, loadedContainer());
      await _search(tester, 'cpu');

      expect(find.text(_l10n(tester).searchNoResults), findsNothing);
      expect(find.text('u_cpu'), findsOneWidget);
      final row = tester.widget<ListTile>(
        find.ancestor(of: find.text('u_cpu'), matching: find.byType(ListTile)),
      );
      expect(row.leading, isA<Icon>());
    });

    testWidgets('a primitive-cell name returns cell hits across scopes', (
      tester,
    ) async {
      await _pumpHostedDialog(tester, loadedContainer());
      await _search(tester, 'reg');

      // `dma_reg` lives in `top`, `pc_reg` one scope down in `cpu` — the
      // walk descends into child instances.
      expect(find.text('dma_reg'), findsOneWidget);
      expect(find.text('pc_reg'), findsOneWidget);
    });

    testWidgets('a net name returns a net hit', (tester) async {
      await _pumpHostedDialog(tester, loadedContainer());
      await _search(tester, 'clk');

      // Scoped to the result rows: the query field also holds the text
      // `clk`, and `find.text` matches an `EditableText`'s content too.
      expect(
        find.descendant(
          of: find.byType(ListTile),
          matching: find.text('clk'),
        ),
        findsOneWidget,
      );
      expect(find.text(_l10n(tester).searchResultNet), findsWidgets);
    });

    testWidgets('a query matching nothing still reports no results', (
      tester,
    ) async {
      await _pumpHostedDialog(tester, loadedContainer());
      await _search(tester, 'zzz_no_such_symbol');

      expect(find.text(_l10n(tester).searchNoResults), findsOneWidget);
    });
  });

  group('SearchDialog keyboard activation', () {
    late NetlistModel fixture;

    setUpAll(() => fixture = _fixtureModel());

    ProviderContainer loadedContainer() {
      final container = ProviderContainer(
        overrides: netcruxTelemetryTestOverrides(),
      );
      addTearDown(container.dispose);
      container.read(hierarchyTreeProvider.notifier).setModel(fixture);
      return container;
    }

    testWidgets('Enter activates the highlighted (first) result', (
      tester,
    ) async {
      final container = loadedContainer();
      await _pumpHostedDialog(tester, container);
      await _search(tester, 'u_cpu');

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      // Activation closes the dialog and applies the hit to the container.
      expect(find.byType(SearchDialog), findsNothing);
      expect(
        container.read(selectedElementProvider).primary,
        isA<SelectedElementCell>().having((s) => s.cellId, 'cellId', 'u_cpu'),
      );
    });

    testWidgets('ArrowDown moves the highlight and Enter activates that row', (
      tester,
    ) async {
      final container = loadedContainer();
      await _pumpHostedDialog(tester, container);
      // Two cell hits, ordered by the hierarchy walk: dma_reg then pc_reg.
      await _search(tester, 'reg');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      final highlighted = tester
          .widgetList<ListTile>(find.byType(ListTile))
          .where((t) => t.selected)
          .toList();
      expect(highlighted, hasLength(1));

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(
        container.read(selectedElementProvider).primary,
        isA<SelectedElementCell>().having((s) => s.cellId, 'cellId', 'pc_reg'),
      );
    });

    testWidgets('ArrowUp at the top of the list keeps the first row', (
      tester,
    ) async {
      final container = loadedContainer();
      await _pumpHostedDialog(tester, container);
      await _search(tester, 'reg');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(
        container.read(selectedElementProvider).primary,
        isA<SelectedElementCell>().having((s) => s.cellId, 'cellId', 'dma_reg'),
      );
    });

    testWidgets('Enter inside the debounce window runs the search instead of '
        'activating a stale row', (tester) async {
      final container = loadedContainer();
      await _pumpHostedDialog(tester, container);

      await tester.enterText(find.byType(TextField), 'reg');
      // Still inside the 200 ms debounce: no results are on screen yet.
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('dma_reg'), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      // The dialog stayed open and the pending search ran immediately.
      expect(find.byType(SearchDialog), findsOneWidget);
      expect(find.text('dma_reg'), findsOneWidget);
    });

    testWidgets('Enter with no results is inert', (tester) async {
      await _pumpHostedDialog(tester, loadedContainer());
      await _search(tester, 'zzz_no_such_symbol');

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.byType(SearchDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('SearchDialog reveal + net-driver navigation', () {
    // A design where net `sig_net` (netId 5) is driven by the output `Q` of
    // cell `driver_dff`, plus an undriven net `float_net` (netId 9) that no
    // cell drives. Lets us assert reveal-on-cell, driver-reveal-on-net, and
    // the undriven-net fallback.
    NetlistModel netModel() => const NetlistModel(
      creator: 'test',
      modules: <String, Module>{
        'top': Module(
          name: 'top',
          attributes: <String, String>{'top': '1'},
          ports: {},
          cells: <String, Cell>{
            'driver_dff': Cell(
              name: 'driver_dff',
              type: r'$dff',
              parameters: <String, String>{},
              attributes: <String, String>{},
              portDirections: <String, PortDirection>{
                'D': PortDirection.input,
                'Q': PortDirection.output,
              },
              connections: <String, List<BitRef>>{
                'D': <BitRef>[NetBit(3)],
                'Q': <BitRef>[NetBit(5)],
              },
            ),
          },
          nets: <String, Net>{
            'sig_net': Net(
              name: 'sig_net',
              bits: <BitRef>[NetBit(5)],
              attributes: <String, String>{},
            ),
            'float_net': Net(
              name: 'float_net',
              bits: <BitRef>[NetBit(9)],
              attributes: <String, String>{},
            ),
          },
        ),
      },
    );

    ProviderContainer loaded(NetlistModel model) {
      final container = ProviderContainer(
        overrides: netcruxTelemetryTestOverrides(),
      );
      addTearDown(container.dispose);
      container.read(hierarchyTreeProvider.notifier).setModel(model);
      return container;
    }

    testWidgets('clicking a cell result selects AND requests a reveal of it', (
      tester,
    ) async {
      final container = loaded(_model());
      await _pumpHostedDialog(tester, container);
      await _search(tester, 'alu_adder');

      await tester.tap(
        find.descendant(
          of: find.byType(ListTile),
          matching: find.text('alu_adder'),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        container.read(selectedElementProvider).primary,
        isA<SelectedElementCell>().having(
          (s) => s.cellId,
          'cellId',
          'alu_adder',
        ),
      );
      // The reveal request is parked for the canvas to consume — without a
      // gesture handler mounted here it stays set, which is what we assert.
      expect(container.read(revealRequestProvider), 'alu_adder');
    });

    testWidgets('clicking a net result reveals its DRIVER cell instead of '
        'clearing the selection', (tester) async {
      final container = loaded(netModel());
      await _pumpHostedDialog(tester, container);
      await _search(tester, 'sig_net');

      // Confirm it is classified as a net hit (not a cell).
      expect(find.text(_l10n(tester).searchResultNet), findsWidgets);
      await tester.tap(
        find.descendant(
          of: find.byType(ListTile),
          matching: find.text('sig_net'),
        ),
      );
      await tester.pumpAndSettle();

      // Old behaviour cleared selection; now it selects + reveals the DFF
      // that drives the net.
      expect(
        container.read(selectedElementProvider).primary,
        isA<SelectedElementCell>().having(
          (s) => s.cellId,
          'cellId',
          'driver_dff',
        ),
      );
      expect(container.read(revealRequestProvider), 'driver_dff');
    });

    testWidgets(
      'clicking an undriven net clears selection (nothing to reveal)',
      (tester) async {
        final container = loaded(netModel());
        // Seed a prior selection so we can see it get cleared.
        container
            .read(selectedElementProvider.notifier)
            .select(const SelectedElement.cell(cellId: 'driver_dff'));
        await _pumpHostedDialog(tester, container);
        await _search(tester, 'float_net');

        await tester.tap(
          find.descendant(
            of: find.byType(ListTile),
            matching: find.text('float_net'),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          container.read(selectedElementProvider).primary,
          isA<SelectedElementNone>(),
        );
        expect(container.read(revealRequestProvider), isNull);
      },
    );
  });

  group('SearchDialog locale sweep', () {
    for (final locale in L10N.supportedLocales) {
      testWidgets('pumps cleanly in ${locale.toLanguageTag()}', (tester) async {
        final container = ProviderContainer(
          overrides: netcruxTelemetryTestOverrides(),
        );
        addTearDown(container.dispose);
        container.read(hierarchyTreeProvider.notifier).setModel(_model());
        await _pumpDialog(tester, container, locale: locale);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        // The three mode chips + the query field render in every locale.
        expect(find.byType(ChoiceChip), findsNWidgets(3));
        expect(find.byType(TextField), findsOneWidget);
      });

      testWidgets('searches the fixture design in ${locale.toLanguageTag()}', (
        tester,
      ) async {
        final container = ProviderContainer(
          overrides: netcruxTelemetryTestOverrides(),
        );
        addTearDown(container.dispose);
        container
            .read(hierarchyTreeProvider.notifier)
            .setModel(_fixtureModel());
        await _pumpHostedDialog(tester, container, locale: locale);

        await _search(tester, 'reg');

        // Symbol names are design data, not UI copy, so the same rows
        // surface in every locale; only the kind chip is translated.
        expect(find.text('dma_reg'), findsOneWidget);
        expect(find.text('pc_reg'), findsOneWidget);
        expect(find.text(_l10n(tester).searchNoResults), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
