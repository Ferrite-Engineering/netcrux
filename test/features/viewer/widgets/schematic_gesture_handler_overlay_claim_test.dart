// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_annotations/crux_annotations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/layout/bounding_box.dart';
import 'package:netcrux/domain/models/layout/edge_route.dart';
import 'package:netcrux/domain/models/layout/netlist_layout.dart';
import 'package:netcrux/domain/models/layout/node_position.dart';
import 'package:netcrux/domain/models/schematic/cell_kind.dart';
import 'package:netcrux/domain/models/schematic/laid_out_graph.dart';
import 'package:netcrux/domain/models/schematic/schematic_graph.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/features/project/providers/current_laid_out_graph_provider.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/features/viewer/providers/viewport_transform_notifier.dart';
import 'package:netcrux/features/viewer/widgets/schematic_gesture_handler.dart';
import 'package:netcrux/services/schematic/annotation_callout_seams.dart';

const Size _kCanvasSize = Size(400, 300);

/// One 80 × 60 cell at design (100, 100); bounds match the canvas 1:1.
LaidOutGraph _graph() {
  const cell = SchematicCell(
    id: 'u_alu',
    kind: CellKind.andGate,
    type: r'$and',
    ports: <SchematicPort>[],
  );
  const graph = SchematicGraph(
    moduleName: 'top',
    cells: <SchematicCell>[cell],
    boundaryPorts: <SchematicBoundaryPort>[],
    edges: <SchematicEdge>[],
  );
  const layout = NetlistLayout(
    nodes: <NodePosition>[
      NodePosition(
        id: 'u_alu',
        bounds: BoundingBox(x: 100, y: 100, width: 80, height: 60),
      ),
    ],
    edges: <EdgeRoute>[],
    bounds: BoundingBox(x: 0, y: 0, width: 400, height: 300),
  );
  return const LaidOutGraph(graph: graph, layout: layout);
}

/// The canvas with a callout label drawn over the cell, the way a callout
/// layer sits inside the gesture handler: a 60 × 30 label centred on the
/// cell, claiming the pointer through the open-core seam.
Widget _harness(ProviderContainer container, {required List<Offset> drags}) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox.fromSize(
              size: _kCanvasSize,
              child: SchematicGestureHandler(
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    const ColoredBox(color: Color(0xFF202024)),
                    Consumer(
                      builder: (context, ref, _) => Stack(
                        children: <Widget>[
                          Positioned(
                            key: const ValueKey<String>('callout'),
                            left: 110,
                            top: 115,
                            width: 60,
                            height: 30,
                            child: CruxCalloutDraggable(
                              onClaim: (value) =>
                                  ref
                                          .read(
                                            canvasOverlayGestureClaimProvider
                                                .notifier,
                                          )
                                          .active =
                                      value,
                              onDragUpdate: drags.add,
                              child: const ColoredBox(color: Colors.amber),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

void main() {
  Future<ProviderContainer> pump(
    WidgetTester tester,
    List<Offset> drags,
  ) async {
    final container = ProviderContainer(
      overrides: [
        currentLaidOutGraphProvider.overrideWith((ref) async => _graph()),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(_harness(container, drags: drags));
    await tester.pumpAndSettle();
    return container;
  }

  Offset calloutCentre(WidgetTester tester) =>
      tester.getCenter(find.byKey(const ValueKey<String>('callout')));

  testWidgets('a click on a callout does not select the cell under it', (
    tester,
  ) async {
    final container = await pump(tester, <Offset>[]);
    await tester.tapAt(calloutCentre(tester));
    await tester.pump();
    expect(container.read(selectedElementProvider).isEmpty, isTrue);
    expect(container.read(canvasOverlayGestureClaimProvider), isFalse);
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('dragging a callout moves the label and not the canvas', (
    tester,
  ) async {
    final drags = <Offset>[];
    final container = await pump(tester, drags);
    final before = container.read(viewportTransformProvider).offset;
    final gesture = await tester.startGesture(calloutCentre(tester));
    await gesture.moveBy(const Offset(40, 20));
    await tester.pump();
    await gesture.moveBy(const Offset(20, 10));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(container.read(viewportTransformProvider).offset, before);
    expect(drags, isNotEmpty);
    expect(container.read(canvasOverlayGestureClaimProvider), isFalse);
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('a double click on a callout does not leave the scope', (
    tester,
  ) async {
    final container = await pump(tester, <Offset>[]);
    container
        .read(selectedElementProvider.notifier)
        .select(const SelectedElement.cell(cellId: 'u_alu'));
    final at = calloutCentre(tester);
    await tester.tapAt(at);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(at);
    await tester.pumpAndSettle();
    expect(
      container.read(selectedElementProvider).primary,
      const SelectedElement.cell(cellId: 'u_alu'),
      reason:
          'a double click on the canvas pops out and clears; on a '
          "callout it is the callout's",
    );
  });

  testWidgets('a click beside the callout still selects as before', (
    tester,
  ) async {
    final container = await pump(tester, <Offset>[]);
    final transform = container.read(viewportTransformProvider);
    final topLeft = tester.getTopLeft(find.byType(SchematicGestureHandler));
    // Design (105, 105): inside the cell, outside the label.
    await tester.tapAt(
      topLeft + const Offset(105, 105) * transform.zoom + transform.offset,
    );
    await tester.pump();
    expect(
      container.read(selectedElementProvider).primary,
      const SelectedElement.cell(cellId: 'u_alu'),
    );
    await tester.pump(const Duration(milliseconds: 400));
  });
}
