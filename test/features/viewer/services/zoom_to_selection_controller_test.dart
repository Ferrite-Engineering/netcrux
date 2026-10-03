// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:ui';

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
import 'package:netcrux/domain/models/trace/trace_overlay.dart';
import 'package:netcrux/features/project/providers/current_laid_out_graph_provider.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/features/viewer/providers/trace_overlay_notifier.dart';
import 'package:netcrux/features/viewer/providers/viewport_transform_notifier.dart';
import 'package:netcrux/features/viewer/services/zoom_to_selection_controller.dart';

/// A small cell near the origin and a far one, so framing one or both gives
/// visibly different cameras.
LaidOutGraph _fixture() => const LaidOutGraph(
  graph: SchematicGraph(
    moduleName: 'top',
    cells: <SchematicCell>[
      SchematicCell(
        id: 'near',
        kind: CellKind.generic,
        type: 'and',
        ports: <SchematicPort>[],
      ),
      SchematicCell(
        id: 'far',
        kind: CellKind.generic,
        type: 'or',
        ports: <SchematicPort>[],
      ),
    ],
    boundaryPorts: <SchematicBoundaryPort>[],
    edges: <SchematicEdge>[],
  ),
  layout: NetlistLayout(
    bounds: BoundingBox(x: 0, y: 0, width: 4000, height: 2000),
    nodes: <NodePosition>[
      NodePosition(
        id: 'near',
        bounds: BoundingBox(x: 100, y: 100, width: 60, height: 40),
      ),
      NodePosition(
        id: 'far',
        bounds: BoundingBox(x: 3900, y: 1900, width: 60, height: 40),
      ),
    ],
    edges: <EdgeRoute>[],
  ),
);

Future<ProviderContainer> _container() async {
  final container = ProviderContainer(
    overrides: [
      currentLaidOutGraphProvider.overrideWith((ref) async => _fixture()),
    ],
  );
  addTearDown(container.dispose);
  await container.read(currentLaidOutGraphProvider.future);
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const viewport = Size(800, 600);

  test('centres a lone selected cell at the comfort zoom', () async {
    final container = await _container();
    container
        .read(selectedElementProvider.notifier)
        .select(const SelectedElement.cell(cellId: 'near'));

    final framed = ZoomToSelectionController(
      container,
    ).run(viewport: viewport);

    expect(framed, isTrue);
    final transform = container.read(viewportTransformProvider);
    expect(transform.zoom, 1.5);
    // The cell's centre (130, 120) lands at the viewport centre.
    expect(transform.offset.dx, closeTo(400 - 130 * 1.5, 1e-9));
    expect(transform.offset.dy, closeTo(300 - 120 * 1.5, 1e-9));
  });

  test('takes in everything the trace overlay highlights', () async {
    final container = await _container();
    container
        .read(selectedElementProvider.notifier)
        .select(const SelectedElement.cell(cellId: 'near'));
    container
        .read(traceOverlayProvider.notifier)
        .set(
          const TraceOverlay(
            mode: TraceOverlayMode.fanout,
            highlightedCellIds: <String>{'near', 'far'},
            highlightedEdgeIds: <String>{},
            highlightedBoundaryPortIds: <String>{},
          ),
        );

    ZoomToSelectionController(container).run(viewport: viewport);

    // Both cells are in view: the zoom drops well below the single-cell
    // comfort zoom, and both corners project inside the viewport.
    final transform = container.read(viewportTransformProvider);
    expect(transform.zoom, lessThan(0.2));
    Offset project(double x, double y) =>
        Offset(x, y) * transform.zoom + transform.offset;
    final rect = Offset.zero & viewport;
    expect(rect.contains(project(100, 100)), isTrue);
    expect(rect.contains(project(3960, 1940)), isTrue);
  });

  test('leaves the camera alone with nothing selected', () async {
    final container = await _container();
    final before = container.read(viewportTransformProvider);

    final framed = ZoomToSelectionController(
      container,
    ).run(viewport: viewport);

    expect(framed, isFalse);
    expect(container.read(viewportTransformProvider), before);
  });

  test('leaves the camera alone when no canvas is laid out', () async {
    final container = await _container();
    container
        .read(selectedElementProvider.notifier)
        .select(const SelectedElement.cell(cellId: 'near'));
    final before = container.read(viewportTransformProvider);

    expect(ZoomToSelectionController(container).run(), isFalse);
    expect(container.read(viewportTransformProvider), before);
  });
}
