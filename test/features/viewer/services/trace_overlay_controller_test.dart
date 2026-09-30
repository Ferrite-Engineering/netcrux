// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/layout/bounding_box.dart';
import 'package:netcrux/domain/models/layout/edge_route.dart';
import 'package:netcrux/domain/models/layout/netlist_layout.dart';
import 'package:netcrux/domain/models/layout/node_position.dart';
import 'package:netcrux/domain/models/netlist/port_direction.dart';
import 'package:netcrux/domain/models/schematic/cell_kind.dart';
import 'package:netcrux/domain/models/schematic/laid_out_graph.dart';
import 'package:netcrux/domain/models/schematic/schematic_graph.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/domain/models/trace/trace_overlay.dart';
import 'package:netcrux/features/project/providers/current_laid_out_graph_provider.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/features/viewer/providers/trace_overlay_notifier.dart';
import 'package:netcrux/features/viewer/services/trace_overlay_controller.dart';

/// `driver -> sink` over net 1, laid out so the trace service has real
/// geometry to walk.
LaidOutGraph _fixture() {
  const cells = <SchematicCell>[
    SchematicCell(
      id: 'driver',
      kind: CellKind.generic,
      type: 'src',
      ports: <SchematicPort>[
        SchematicPort(
          id: 'driver:Y',
          name: 'Y',
          direction: PortDirection.output,
          side: SchematicPortSide.east,
        ),
      ],
    ),
    SchematicCell(
      id: 'sink',
      kind: CellKind.generic,
      type: 'dst',
      ports: <SchematicPort>[
        SchematicPort(
          id: 'sink:A',
          name: 'A',
          direction: PortDirection.input,
          side: SchematicPortSide.west,
        ),
      ],
    ),
  ];
  const edges = <SchematicEdge>[
    SchematicEdge(
      id: 'e_1_0',
      sourcePortId: 'driver:Y',
      targetPortId: 'sink:A',
      netId: 1,
    ),
  ];
  const layout = NetlistLayout(
    bounds: BoundingBox(x: 0, y: 0, width: 300, height: 100),
    nodes: <NodePosition>[
      NodePosition(
        id: 'driver',
        bounds: BoundingBox(x: 0, y: 0, width: 60, height: 40),
      ),
      NodePosition(
        id: 'sink',
        bounds: BoundingBox(x: 200, y: 0, width: 60, height: 40),
      ),
    ],
    edges: <EdgeRoute>[
      EdgeRoute(
        id: 'e_1_0',
        points: [LayoutPoint(60, 20), LayoutPoint(200, 20)],
        sourceNodeId: 'driver',
        targetNodeId: 'sink',
      ),
    ],
  );
  return const LaidOutGraph(
    graph: SchematicGraph(
      moduleName: 'top',
      cells: cells,
      boundaryPorts: <SchematicBoundaryPort>[],
      edges: edges,
    ),
    layout: layout,
  );
}

ProviderContainer _container({LaidOutGraph? laidOut}) {
  final container = ProviderContainer(
    overrides: [
      currentLaidOutGraphProvider.overrideWith(
        // A null fixture stays pending forever so the provider's
        // synchronous `.value` is null — the "nothing laid out yet"
        // branch the controller must not publish an overlay for.
        (ref) => laidOut ?? Completer<LaidOutGraph>().future,
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('TraceOverlayController.fromContainer', () {
    test('no selection leaves the overlay untouched', () {
      final container = _container(laidOut: _fixture());
      TraceOverlayController.fromContainer(container).showFanin();
      expect(container.read(traceOverlayProvider).isEmpty, isTrue);
    });

    test('no laid-out graph leaves the overlay untouched', () {
      final container = _container();
      container
          .read(selectedElementProvider.notifier)
          .select(const SelectedElement.cell(cellId: 'sink'));
      TraceOverlayController.fromContainer(container).showFanin();
      expect(container.read(traceOverlayProvider).isEmpty, isTrue);
    });

    test('an empty laid-out graph leaves the overlay untouched', () {
      final container = _container(
        laidOut: const LaidOutGraph(
          graph: SchematicGraph(
            moduleName: 'top',
            cells: <SchematicCell>[],
            boundaryPorts: <SchematicBoundaryPort>[],
            edges: <SchematicEdge>[],
          ),
          layout: NetlistLayout(
            bounds: BoundingBox(x: 0, y: 0, width: 0, height: 0),
            nodes: <NodePosition>[],
            edges: <EdgeRoute>[],
          ),
        ),
      );
      container
          .read(selectedElementProvider.notifier)
          .select(const SelectedElement.cell(cellId: 'sink'));
      TraceOverlayController.fromContainer(container).showFanin();
      expect(container.read(traceOverlayProvider).isEmpty, isTrue);
    });

    test('showFanin publishes the driver cone anchored on the selection', () {
      final container = _container(laidOut: _fixture());
      container
          .read(selectedElementProvider.notifier)
          .select(const SelectedElement.cell(cellId: 'sink'));

      TraceOverlayController.fromContainer(container).showFanin();

      final overlay = container.read(traceOverlayProvider);
      expect(overlay.mode, TraceOverlayMode.fanin);
      expect(
        overlay.highlightedCellIds,
        containsAll(<String>['driver', 'sink']),
      );
      expect(overlay.highlightedEdgeIds, contains('e_1_0'));
    });

    test('showFanout publishes the load cone anchored on the selection', () {
      final container = _container(laidOut: _fixture());
      container
          .read(selectedElementProvider.notifier)
          .select(const SelectedElement.cell(cellId: 'driver'));

      TraceOverlayController.fromContainer(container).showFanout();

      final overlay = container.read(traceOverlayProvider);
      expect(overlay.mode, TraceOverlayMode.fanout);
      expect(
        overlay.highlightedCellIds,
        containsAll(<String>['driver', 'sink']),
      );
    });

    test('the trace anchors on the primary (most recent) selection', () {
      final container = _container(laidOut: _fixture());
      container.read(selectedElementProvider.notifier)
        ..select(const SelectedElement.cell(cellId: 'driver'))
        ..select(const SelectedElement.cell(cellId: 'sink'));

      TraceOverlayController.fromContainer(container).showFanin();

      expect(container.read(traceOverlayProvider).mode, TraceOverlayMode.fanin);
      expect(
        container.read(traceOverlayProvider).highlightedCellIds,
        contains('driver'),
        reason: 'fanin of the newest selection (sink) reaches its driver',
      );
    });
  });

  group('TraceOverlayController(WidgetRef)', () {
    testWidgets('reads and writes through the surrounding widget scope', (
      tester,
    ) async {
      final container = _container(laidOut: _fixture());
      container
          .read(selectedElementProvider.notifier)
          .select(const SelectedElement.cell(cellId: 'sink'));

      late TraceOverlayController controller;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) {
                controller = TraceOverlayController(ref);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      controller.showFanout();
      await tester.pump();

      expect(
        container.read(traceOverlayProvider).mode,
        TraceOverlayMode.fanout,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
