// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/providers/pro_overlay_installed_provider.dart';
import 'package:netcrux/domain/models/layout/bounding_box.dart';
import 'package:netcrux/domain/models/layout/edge_route.dart';
import 'package:netcrux/domain/models/layout/netlist_layout.dart';
import 'package:netcrux/domain/models/layout/node_position.dart';
import 'package:netcrux/domain/models/netlist/port_direction.dart';
import 'package:netcrux/domain/models/schematic/cell_kind.dart';
import 'package:netcrux/domain/models/schematic/laid_out_graph.dart';
import 'package:netcrux/domain/models/schematic/pin_tie.dart';
import 'package:netcrux/domain/models/schematic/schematic_graph.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/features/inspector/widgets/inspector_panel.dart';
import 'package:netcrux/features/project/providers/current_laid_out_graph_provider.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/source_pane/source_pane_openers.dart';
import 'package:netcrux/shared/widgets/netcrux_feature_tier_badge.dart';

const List<Locale> _locales = <Locale>[
  Locale('en'),
  Locale('zh', 'CN'),
  Locale('zh'),
  Locale('ja'),
  Locale('ko'),
];

const _graph = LaidOutGraph(
  graph: SchematicGraph(
    moduleName: 'cpu',
    cells: <SchematicCell>[
      SchematicCell(
        id: 'u_alu',
        kind: CellKind.generic,
        type: 'alu',
        ports: [],
      ),
    ],
    boundaryPorts: <SchematicBoundaryPort>[],
    edges: <SchematicEdge>[],
  ),
  layout: NetlistLayout(
    nodes: <NodePosition>[],
    edges: <EdgeRoute>[],
    bounds: BoundingBox(x: 0, y: 0, width: 0, height: 0),
  ),
);

/// A multiplier with one input on an undriven net, one tied to 0, one tied
/// to x and one the netlist left unconnected.
const _tiedGraph = LaidOutGraph(
  graph: SchematicGraph(
    moduleName: 'top',
    cells: <SchematicCell>[
      SchematicCell(
        id: 'u_mul',
        kind: CellKind.generic,
        type: r'$mul',
        ports: <SchematicPort>[
          SchematicPort(
            id: 'u_mul:A',
            name: 'A',
            direction: PortDirection.input,
            side: SchematicPortSide.west,
            tie: PinTie.undriven,
          ),
          SchematicPort(
            id: 'u_mul:B',
            name: 'B',
            direction: PortDirection.input,
            side: SchematicPortSide.west,
            tie: PinTie.constant('0'),
          ),
          SchematicPort(
            id: 'u_mul:C',
            name: 'C',
            direction: PortDirection.input,
            side: SchematicPortSide.west,
            tie: PinTie.constant('x'),
          ),
          SchematicPort(
            id: 'u_mul:D',
            name: 'D',
            direction: PortDirection.input,
            side: SchematicPortSide.west,
            tie: PinTie.unconnected,
          ),
        ],
      ),
    ],
    boundaryPorts: <SchematicBoundaryPort>[],
    edges: <SchematicEdge>[],
  ),
  layout: NetlistLayout(
    nodes: <NodePosition>[],
    edges: <EdgeRoute>[],
    bounds: BoundingBox(x: 0, y: 0, width: 0, height: 0),
  ),
);

/// A laid-out graph whose net 7 fans out to [sinks] sinks — the clock net
/// of a flattened SoC, in miniature.
LaidOutGraph _fanoutGraph(int sinks) {
  return LaidOutGraph(
    graph: SchematicGraph(
      moduleName: 'soc',
      cells: const <SchematicCell>[],
      boundaryPorts: const <SchematicBoundaryPort>[],
      edges: <SchematicEdge>[
        for (var i = 0; i < sinks; i++)
          SchematicEdge(
            id: 'e$i',
            sourcePortId: 'u_clkgen:clk_out',
            targetPortId: 'u_ff_$i:clk',
            netId: 7,
          ),
      ],
    ),
    layout: const NetlistLayout(
      nodes: <NodePosition>[],
      edges: <EdgeRoute>[],
      bounds: BoundingBox(x: 0, y: 0, width: 0, height: 0),
    ),
  );
}

/// A container whose laid-out graph is stubbed (so the inspector's cell
/// lookup succeeds without running ELK layout).
ProviderContainer _container({
  bool withGraph = false,
  LaidOutGraph? graph,
  List<Override> overrides = const <Override>[],
}) {
  return ProviderContainer(
    overrides: <Override>[
      if (withGraph || graph != null)
        currentLaidOutGraphProvider.overrideWith(
          (ref) async => graph ?? _graph,
        ),
      ...overrides,
    ],
  );
}

Widget _wrap(ProviderContainer container, Locale locale) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: L10N.localizationsDelegates,
      supportedLocales: L10N.supportedLocales,
      home: const Scaffold(
        body: SizedBox(width: 320, height: 600, child: InspectorPanel()),
      ),
    ),
  );
}

void main() {
  group('InspectorPanel', () {
    testWidgets('renders the empty state when nothing is selected', (
      tester,
    ) async {
      final container = _container();
      addTearDown(container.dispose);
      await tester.pumpWidget(_wrap(container, const Locale('en')));
      await tester.pumpAndSettle();
      expect(find.text('No selection'), findsOneWidget);
    });

    testWidgets('renders the cell view for a selected cell', (tester) async {
      final container = _container(withGraph: true);
      addTearDown(container.dispose);
      container
          .read(selectedElementProvider.notifier)
          .select(const SelectedElement.cell(cellId: 'u_alu'));
      await tester.pumpWidget(_wrap(container, const Locale('en')));
      await tester.pumpAndSettle();
      // Cell header + the instance id + the cell type field.
      expect(find.text('Cell'), findsOneWidget);
      expect(find.text('u_alu'), findsOneWidget);
      expect(find.text('alu'), findsOneWidget);
      expect(find.text('No selection'), findsNothing);
    });

    for (final locale in _locales) {
      testWidgets('pumps cleanly with a cell selected in '
          '${locale.toLanguageTag()}', (tester) async {
        final container = _container(withGraph: true);
        addTearDown(container.dispose);
        container
            .read(selectedElementProvider.notifier)
            .select(const SelectedElement.cell(cellId: 'u_alu'));
        await tester.pumpWidget(_wrap(container, locale));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        // The instance id is locale-independent, so it always renders.
        expect(find.text('u_alu'), findsOneWidget);
      });
    }
  });

  group('pin ties', () {
    testWidgets('the cell view says what each pin is tied to', (tester) async {
      final container = _container(graph: _tiedGraph);
      addTearDown(container.dispose);
      container
          .read(selectedElementProvider.notifier)
          .select(const SelectedElement.cell(cellId: 'u_mul'));
      await tester.pumpWidget(_wrap(container, const Locale('en')));
      await tester.pumpAndSettle();
      expect(
        find.text('input, Undriven (no driver in this scope)'),
        findsOneWidget,
      );
      expect(find.text('input, Constant 0'), findsOneWidget);
      expect(find.text('input, x (unknown value)'), findsOneWidget);
      expect(find.text('input, Unconnected'), findsOneWidget);
    });

    testWidgets('the port view has a Tied to row', (tester) async {
      final container = _container(graph: _tiedGraph);
      addTearDown(container.dispose);
      container
          .read(selectedElementProvider.notifier)
          .select(
            const SelectedElement.port(
              cellId: 'u_mul',
              portId: 'u_mul:A',
              portName: 'A',
            ),
          );
      await tester.pumpWidget(_wrap(container, const Locale('en')));
      await tester.pumpAndSettle();
      expect(find.text('Tied to'), findsOneWidget);
      expect(find.text('Undriven (no driver in this scope)'), findsOneWidget);
    });

    for (final locale in _locales) {
      testWidgets('the port view pumps cleanly in $locale', (tester) async {
        final container = _container(graph: _tiedGraph);
        addTearDown(container.dispose);
        container
            .read(selectedElementProvider.notifier)
            .select(
              const SelectedElement.port(
                cellId: 'u_mul',
                portId: 'u_mul:B',
                portName: 'B',
              ),
            );
        await tester.pumpWidget(_wrap(container, locale));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final l10n = await L10N.delegate.load(locale);
        expect(find.text(l10n.inspectorFieldTiedTo), findsOneWidget);
        expect(find.text(l10n.inspectorTieConstant('0')), findsOneWidget);
      });
    }
  });

  group('wire fanout', () {
    // The clock net of a flattened SoC is the case this pane exists for. The
    // sinks used to be one joined `SelectableText` in a non-scrolling
    // `Column`: 2 000 sinks laid out as one 2 000-line paragraph and
    // overflowed the pane, which cannot be scrolled away. The rows are now
    // virtualized, so only the handful in view is built.
    testWidgets('renders a 2 000-sink net without overflowing, and builds '
        'only the visible rows', (tester) async {
      const sinks = 2000;
      final container = _container(graph: _fanoutGraph(sinks));
      addTearDown(container.dispose);
      container
          .read(selectedElementProvider.notifier)
          .select(const SelectedElement.wire(edgeId: 'e0', netId: 7));
      await tester.pumpWidget(_wrap(container, const Locale('en')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final rows = tester
          .widgetList<SelectableText>(find.byType(SelectableText))
          .length;
      // Header rows (net id + driver) plus one per *visible* sink. A 600 px
      // pane fits well under 40 of them; the pre-fix shape built all 2 000
      // sinks into a single widget and blew the column height.
      expect(rows, lessThan(60), reason: 'built $rows rows for $sinks sinks');
      expect(rows, greaterThan(2));
      // The first sink in the list is on screen and the far end is not.
      // (The selected edge's own sink is appended last, so `u_ff_1` leads.)
      expect(find.text('u_ff_1:clk'), findsOneWidget);
      expect(find.text('u_ff_${sinks - 1}:clk'), findsNothing);
      expect(find.text('u_ff_0:clk'), findsNothing);
    });

    testWidgets('scrolls to reach the far end of the fanout', (tester) async {
      final container = _container(graph: _fanoutGraph(2000));
      addTearDown(container.dispose);
      container
          .read(selectedElementProvider.notifier)
          .select(const SelectedElement.wire(edgeId: 'e0', netId: 7));
      await tester.pumpWidget(_wrap(container, const Locale('en')));
      await tester.pumpAndSettle();

      expect(find.text('u_ff_1:clk'), findsOneWidget);
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // The head of the fanout scrolled off; deeper sinks are reachable.
      expect(find.text('u_ff_1:clk'), findsNothing);
    });
  });

  group('Go to source', () {
    testWidgets('is badged Pro and, with no Pro overlay, says so', (
      tester,
    ) async {
      var opened = 0;
      final container = _container(
        withGraph: true,
        overrides: <Override>[
          betaPeriodProvider.overrideWithValue(true),
          openSourceForElementOpenerProvider.overrideWithValue(
            (_, _, {elementId}) => opened++,
          ),
        ],
      );
      addTearDown(container.dispose);
      container
          .read(selectedElementProvider.notifier)
          .select(const SelectedElement.cell(cellId: 'u_alu'));
      await tester.pumpWidget(_wrap(container, const Locale('en')));
      await tester.pumpAndSettle();

      expect(find.byType(NetCruxFeatureTierBadge), findsOneWidget);
      await tester.tap(find.text('Go to source'));
      await tester.pump();
      expect(opened, 0);
      expect(
        find.text('Show Source for this Element requires NetCrux Pro.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('with the Pro overlay installed, opens the source', (
      tester,
    ) async {
      var opened = 0;
      final container = _container(
        withGraph: true,
        overrides: <Override>[
          betaPeriodProvider.overrideWithValue(true),
          proOverlayInstalledProvider.overrideWithValue(true),
          openSourceForElementOpenerProvider.overrideWithValue(
            (_, _, {elementId}) => opened++,
          ),
        ],
      );
      addTearDown(container.dispose);
      container
          .read(selectedElementProvider.notifier)
          .select(const SelectedElement.cell(cellId: 'u_alu'));
      await tester.pumpWidget(_wrap(container, const Locale('en')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Go to source'));
      await tester.pump();
      expect(opened, 1);
      expect(find.byType(SnackBar), findsNothing);
    });
  });
}
