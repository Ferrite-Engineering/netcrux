// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Everything the pointer does to an element on the schematic canvas can be
// done from the keyboard: Alt+Arrow selects a cell, a module port, a pin or a
// net (the click), Shift adds to the selection (the Shift-click), Enter pushes
// into the selected instance (the double-click), and Shift+F10 or the Menu
// key opens the element menu (the right-click) — the only route to Copy Path
// and to the Pro entries such as cross-probing a signal to a peer. Each step
// is announced, because a selection a screen reader user cannot hear is not a
// selection they can act on.

import 'package:crux_a11y/crux_a11y_testing.dart';
import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/cdc/cdc_analysis_result.dart';
import 'package:netcrux/domain/models/cdc/cdc_crossing.dart';
import 'package:netcrux/domain/models/cdc/cdc_crossing_kind.dart';
import 'package:netcrux/domain/models/cdc/cdc_severity.dart';
import 'package:netcrux/domain/models/cdc/cdc_synchronizer_status.dart';
import 'package:netcrux/domain/models/cdc/clock_domain.dart';
import 'package:netcrux/domain/models/layout/bounding_box.dart';
import 'package:netcrux/domain/models/layout/edge_route.dart';
import 'package:netcrux/domain/models/layout/netlist_layout.dart';
import 'package:netcrux/domain/models/layout/node_position.dart';
import 'package:netcrux/domain/models/netlist/port_direction.dart';
import 'package:netcrux/domain/models/reset_domain/reset_crossing.dart';
import 'package:netcrux/domain/models/reset_domain/reset_crossing_kind.dart';
import 'package:netcrux/domain/models/reset_domain/reset_domain.dart';
import 'package:netcrux/domain/models/reset_domain/reset_domain_analysis_result.dart';
import 'package:netcrux/domain/models/reset_domain/reset_polarity.dart';
import 'package:netcrux/domain/models/reset_domain/reset_severity.dart';
import 'package:netcrux/domain/models/reset_domain/reset_synchronizer_status.dart';
import 'package:netcrux/domain/models/schematic/cell_kind.dart';
import 'package:netcrux/domain/models/schematic/laid_out_graph.dart';
import 'package:netcrux/domain/models/schematic/schematic_graph.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/features/cdc/providers/cdc_analysis_state_provider.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/project/providers/current_laid_out_graph_provider.dart';
import 'package:netcrux/features/reset_domain/providers/reset_domain_analysis_state_provider.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/features/viewer/widgets/schematic_gesture_handler.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

/// `clk` drives `u_a.A` (net 5) and `u_a.Y` drives `u_b.A` (net 7). The cells
/// sit on the top row, the port below, all inside the 400 × 300 canvas.
const LaidOutGraph _graph = LaidOutGraph(
  graph: SchematicGraph(
    moduleName: 'top',
    cells: <SchematicCell>[
      SchematicCell(
        id: 'u_a',
        kind: CellKind.notGate,
        type: r'$not',
        ports: <SchematicPort>[
          SchematicPort(
            id: 'u_a:A',
            name: 'A',
            direction: PortDirection.input,
            side: SchematicPortSide.west,
          ),
          SchematicPort(
            id: 'u_a:Y',
            name: 'Y',
            direction: PortDirection.output,
            side: SchematicPortSide.east,
          ),
        ],
      ),
      SchematicCell(
        id: 'u_b',
        kind: CellKind.andGate,
        type: r'$and',
        ports: <SchematicPort>[
          SchematicPort(
            id: 'u_b:A',
            name: 'A',
            direction: PortDirection.input,
            side: SchematicPortSide.west,
          ),
        ],
      ),
    ],
    boundaryPorts: <SchematicBoundaryPort>[
      SchematicBoundaryPort(
        id: 'port:clk',
        name: 'clk',
        direction: PortDirection.input,
        width: 1,
      ),
    ],
    edges: <SchematicEdge>[
      SchematicEdge(
        id: 'e0',
        sourcePortId: 'port:clk',
        targetPortId: 'u_a:A',
        netId: 5,
      ),
      SchematicEdge(
        id: 'e1',
        sourcePortId: 'u_a:Y',
        targetPortId: 'u_b:A',
        netId: 7,
      ),
    ],
  ),
  layout: NetlistLayout(
    nodes: <NodePosition>[
      NodePosition(
        id: 'u_a',
        bounds: BoundingBox(x: 100, y: 10, width: 60, height: 40),
      ),
      NodePosition(
        id: 'u_b',
        bounds: BoundingBox(x: 300, y: 10, width: 60, height: 40),
      ),
      NodePosition(
        id: 'port:clk',
        bounds: BoundingBox(x: 10, y: 200, width: 10, height: 10),
      ),
    ],
    edges: <EdgeRoute>[],
    bounds: BoundingBox(x: 0, y: 0, width: 400, height: 300),
  ),
);

class _RecordingHierarchy extends HierarchyTreeNotifier {
  final List<String> pushed = <String>[];

  @override
  void pushInto(String instanceName) => pushed.add(instanceName);
}

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  LaidOutGraph graph = _graph,
  _RecordingHierarchy? hierarchy,
  Locale locale = const Locale('en'),
}) async {
  final container = ProviderContainer(
    overrides: [
      currentLaidOutGraphProvider.overrideWith((ref) async => graph),
      if (hierarchy != null)
        hierarchyTreeProvider.overrideWith(() => hierarchy),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: const Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              height: 300,
              child: SchematicGestureHandler(child: SizedBox.expand()),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> _alt(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
  await tester.pump();
}

SelectedElement _primary(ProviderContainer container) =>
    container.read(selectedElementProvider).primary;

void main() {
  testWidgets('Alt+Down and Alt+Up step through cells and ports, announced', (
    tester,
  ) async {
    final recorder = AnnouncementRecorder.attach(tester);
    final container = await _pump(tester);

    await _alt(tester, LogicalKeyboardKey.arrowDown);
    expect(_primary(container), const SelectedElement.cell(cellId: 'u_a'));
    await _alt(tester, LogicalKeyboardKey.arrowDown);
    expect(_primary(container), const SelectedElement.cell(cellId: 'u_b'));
    await _alt(tester, LogicalKeyboardKey.arrowDown);
    expect(
      _primary(container),
      const SelectedElement.boundaryPort(portId: 'port:clk', portName: 'clk'),
    );
    await _alt(tester, LogicalKeyboardKey.arrowUp);
    expect(_primary(container), const SelectedElement.cell(cellId: 'u_b'));

    expect(recorder.messages, <String>[
      r'u_a, $not cell',
      r'u_b, $and cell',
      'Port clk',
      r'u_b, $and cell',
    ]);
  });

  testWidgets('Alt+Right and Alt+Left step through the pins of the cell, each '
      'followed by its net', (tester) async {
    final recorder = AnnouncementRecorder.attach(tester);
    final container = await _pump(tester);
    container
        .read(selectedElementProvider.notifier)
        .select(const SelectedElement.cell(cellId: 'u_a'));

    const pinA = SelectedElement.port(
      cellId: 'u_a',
      portId: 'u_a:A',
      portName: 'A',
    );
    const pinY = SelectedElement.port(
      cellId: 'u_a',
      portId: 'u_a:Y',
      portName: 'Y',
    );
    final visited = <SelectedElement>[];
    for (var i = 0; i < 4; i++) {
      await _alt(tester, LogicalKeyboardKey.arrowRight);
      visited.add(_primary(container));
    }
    // Net 5 is driven by the clock port, yet the walk stays on u_a.
    expect(visited, const <SelectedElement>[
      pinA,
      SelectedElement.wire(edgeId: 'e0', netId: 5),
      pinY,
      SelectedElement.wire(edgeId: 'e1', netId: 7),
    ]);
    await _alt(tester, LogicalKeyboardKey.arrowLeft);
    expect(_primary(container), pinY);

    // No netlist model in this harness, so a net is named by its id.
    expect(recorder.messages, <String>[
      'Pin A of u_a',
      'Net 5',
      'Pin Y of u_a',
      'Net 7',
      'Pin Y of u_a',
    ]);
  });

  testWidgets(
    'a pin selected with the pointer continues the walk on its cell',
    (
      tester,
    ) async {
      final container = await _pump(tester);
      container
          .read(selectedElementProvider.notifier)
          .select(
            const SelectedElement.port(
              cellId: 'u_a',
              portId: 'u_a:Y',
              portName: 'Y',
            ),
          );
      await _alt(tester, LogicalKeyboardKey.arrowRight);
      expect(
        _primary(container),
        const SelectedElement.wire(edgeId: 'e1', netId: 7),
      );
    },
  );

  testWidgets('an element with no pins or nets says so', (tester) async {
    final recorder = AnnouncementRecorder.attach(tester);
    const bare = LaidOutGraph(
      graph: SchematicGraph(
        moduleName: 'top',
        cells: <SchematicCell>[
          SchematicCell(
            id: 'u_bare',
            kind: CellKind.generic,
            type: 'blackbox',
            ports: <SchematicPort>[],
          ),
        ],
        boundaryPorts: <SchematicBoundaryPort>[],
        edges: <SchematicEdge>[],
      ),
      layout: NetlistLayout(
        nodes: <NodePosition>[
          NodePosition(
            id: 'u_bare',
            bounds: BoundingBox(x: 10, y: 10, width: 40, height: 40),
          ),
        ],
        edges: <EdgeRoute>[],
        bounds: BoundingBox(x: 0, y: 0, width: 400, height: 300),
      ),
    );
    final container = await _pump(tester, graph: bare);
    await _alt(tester, LogicalKeyboardKey.arrowDown);
    await _alt(tester, LogicalKeyboardKey.arrowRight);

    expect(_primary(container), const SelectedElement.cell(cellId: 'u_bare'));
    expect(recorder.messages, <String>[
      'u_bare, blackbox cell',
      'u_bare has no pins or nets',
    ]);
  });

  testWidgets('Shift+Alt+Down adds to the selection, like a Shift-click', (
    tester,
  ) async {
    final container = await _pump(tester);
    await _alt(tester, LogicalKeyboardKey.arrowDown);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await _alt(tester, LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

    final selection = container.read(selectedElementProvider);
    expect(selection.elements, hasLength(2));
    expect(selection.primary, const SelectedElement.cell(cellId: 'u_b'));
  });

  testWidgets('an empty scope and an unselected net walk say so', (
    tester,
  ) async {
    final recorder = AnnouncementRecorder.attach(tester);
    final container = await _pump(tester, graph: LaidOutGraph.empty);

    await _alt(tester, LogicalKeyboardKey.arrowDown);
    await _alt(tester, LogicalKeyboardKey.arrowRight);

    expect(_primary(container), const SelectedElement.none());
    expect(recorder.messages, <String>[
      'Nothing to select in this scope',
      'Nothing is selected',
    ]);
  });

  testWidgets('Enter pushes into the selected instance, like a double-click', (
    tester,
  ) async {
    final hierarchy = _RecordingHierarchy();
    final container = await _pump(tester, hierarchy: hierarchy);
    container
        .read(selectedElementProvider.notifier)
        .select(const SelectedElement.cell(cellId: 'u_b'));

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(hierarchy.pushed, <String>['u_b']);
    expect(_primary(container), const SelectedElement.none());
  });

  for (final (name, press) in <(String, Future<void> Function(WidgetTester))>[
    (
      'Shift+F10',
      (tester) async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.f10);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      },
    ),
    (
      'the Menu key',
      (tester) => tester.sendKeyEvent(LogicalKeyboardKey.contextMenu),
    ),
  ]) {
    testWidgets('$name opens the element menu for the selection', (
      tester,
    ) async {
      final container = await _pump(tester);
      await _alt(tester, LogicalKeyboardKey.arrowDown);
      final canvasFocus = FocusManager.instance.primaryFocus;

      await press(tester);
      await tester.pumpAndSettle();
      expect(find.text('Copy Path'), findsOneWidget);
      expect(find.text('Trace Fanin'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Copy Path'), findsNothing);
      expect(
        FocusManager.instance.primaryFocus,
        canvasFocus,
        reason: 'closing the menu must return focus to the canvas',
      );
      expect(_primary(container), const SelectedElement.cell(cellId: 'u_a'));
    });
  }

  group('locale sweep', () {
    for (final (locale, cell, pin, net) in <(Locale, String, String, String)>[
      (const Locale('zh', 'CN'), r'u_a，$not 单元', 'u_a 的引脚 A', '线网 5'),
      (const Locale('ja'), r'u_a、$not セル', 'u_a のピン A', 'ネット 5'),
      (const Locale('ko'), r'u_a, $not 셀', 'u_a의 핀 A', '넷 5'),
    ]) {
      testWidgets('selections are announced in $locale', (tester) async {
        final recorder = AnnouncementRecorder.attach(tester);
        await _pump(tester, locale: locale);

        await _alt(tester, LogicalKeyboardKey.arrowDown);
        await _alt(tester, LogicalKeyboardKey.arrowRight);
        await _alt(tester, LogicalKeyboardKey.arrowRight);

        expect(recorder.messages, <String>[cell, pin, net]);
        expect(tester.takeException(), isNull);
      });
    }
  });

  testWidgets('the menu key with nothing selected says so and opens nothing', (
    tester,
  ) async {
    final recorder = AnnouncementRecorder.attach(tester);
    await _pump(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
    await tester.pumpAndSettle();

    expect(find.text('Copy Path'), findsNothing);
    expect(recorder.messages, <String>['Nothing is selected']);
  });

  testWidgets('Escape clears the selection and a focused CDC or reset '
      'crossing in one press', (tester) async {
    final container = await _pump(tester);
    await _alt(tester, LogicalKeyboardKey.arrowDown);
    container.read(cdcAnalysisStateProvider.notifier)
      ..setResult(_oneCdcCrossing())
      ..selectCrossing('c1');
    container.read(resetDomainAnalysisStateProvider.notifier)
      ..setResult(_oneResetCrossing())
      ..selectCrossing('r1');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(_primary(container), const SelectedElement.none());
    expect(container.read(cdcAnalysisStateProvider).selectedCrossingId, isNull);
    expect(
      container.read(resetDomainAnalysisStateProvider).selectedCrossingId,
      isNull,
    );
  });
}

CdcAnalysisResult _oneCdcCrossing() => const CdcAnalysisResult(
  detectedDomains: <ClockDomain>[],
  detectedCrossings: <CdcCrossing>[
    CdcCrossing(
      id: 'c1',
      sourceDomainId: 'a',
      destinationDomainId: 'b',
      signalId: ElementId(kind: ElementKind.signal, path: 'x'),
      signalName: 'x',
      crossingKind: CdcCrossingKind.singleBit,
      synchronizerStatus: CdcSynchronizerStatus.metastable,
      severity: CdcSeverity.warning,
      confidence: CdcConfidence.high,
    ),
  ],
  analysisDiagnostics: <String>[],
  analysisDuration: Duration.zero,
);

ResetDomainAnalysisResult _oneResetCrossing() =>
    const ResetDomainAnalysisResult(
      detectedDomains: <ResetDomain>[],
      detectedCrossings: <ResetCrossing>[
        ResetCrossing(
          id: 'r1',
          sourceDomainId: 'a',
          destinationDomainId: 'b',
          signalId: ElementId(kind: ElementKind.signal, path: 'x'),
          signalName: 'x',
          crossingKind: ResetCrossingKind.resetDeassertCrossing,
          synchronizerStatus: ResetSynchronizerStatus.missingSynchronizer,
          severity: ResetSeverity.critical,
          confidence: ResetConfidence.high,
          sourcePolarity: ResetPolarity.activeHigh,
        ),
      ],
      analysisDiagnostics: <String>[],
      analysisDuration: Duration.zero,
    );
