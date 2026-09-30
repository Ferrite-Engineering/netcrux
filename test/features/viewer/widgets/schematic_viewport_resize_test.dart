// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Resizing the canvas — a window resize or a panel-splitter drag — used to
// do nothing to the camera. The offset is absolute, so a growing pane pinned
// the design to the top-left corner and a shrinking one pushed it off-screen,
// which read as "the diagram doesn't resize".
//
// These pin the widget-level half of the fix: the gesture handler notices the
// viewport size change during layout (nothing rebuilds it on a resize) and
// hands the old and new sizes to the transform notifier. The notifier's own
// two cases are covered in viewport_transform_notifier_test.dart.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/layout/bounding_box.dart';
import 'package:netcrux/domain/models/layout/edge_route.dart';
import 'package:netcrux/domain/models/layout/netlist_layout.dart';
import 'package:netcrux/domain/models/layout/node_position.dart';
import 'package:netcrux/domain/models/schematic/cell_kind.dart';
import 'package:netcrux/domain/models/schematic/laid_out_graph.dart';
import 'package:netcrux/domain/models/schematic/schematic_graph.dart';
import 'package:netcrux/features/project/providers/current_laid_out_graph_provider.dart';
import 'package:netcrux/features/viewer/providers/viewport_transform_notifier.dart';
import 'package:netcrux/features/viewer/rendering/schematic_painter.dart';
import 'package:netcrux/features/viewer/widgets/schematic_gesture_handler.dart';

const _bounds = BoundingBox(x: 0, y: 0, width: 2000, height: 1000);

LaidOutGraph _graph() => const LaidOutGraph(
  graph: SchematicGraph(
    moduleName: 'wide',
    cells: <SchematicCell>[
      SchematicCell(
        id: 'c0',
        kind: CellKind.andGate,
        type: r'$and',
        ports: <SchematicPort>[],
      ),
    ],
    boundaryPorts: <SchematicBoundaryPort>[],
    edges: <SchematicEdge>[],
  ),
  layout: NetlistLayout(
    nodes: <NodePosition>[
      NodePosition(
        id: 'c0',
        bounds: BoundingBox(x: 0, y: 0, width: 8, height: 8),
      ),
    ],
    edges: <EdgeRoute>[],
    bounds: _bounds,
  ),
);

/// The design-space point sitting under the centre of a [size] viewport.
Offset _designAtCentre(ViewportTransform t, Size size) =>
    (Offset(size.width / 2, size.height / 2) - t.offset) / t.zoom;

void main() {
  Widget host(ProviderContainer container, Size canvas) =>
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox.fromSize(
                size: canvas,
                // autofocus:false keeps focus deterministic in the test.
                child: const SchematicGestureHandler(
                  autofocus: false,
                  child: SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
      );

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: <Override>[
        currentLaidOutGraphProvider.overrideWith((ref) async => _graph()),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  testWidgets('a still-fitted canvas re-fits when the pane grows', (
    tester,
  ) async {
    final container = makeContainer();

    await tester.pumpWidget(host(container, const Size(400, 300)));
    await tester.pumpAndSettle();
    // min(400/2000, 300/1000) * 0.9 = 0.18.
    expect(container.read(viewportTransformProvider).zoom, closeTo(0.18, 1e-9));

    await tester.pumpWidget(host(container, const Size(800, 600)));
    await tester.pumpAndSettle();

    // Doubling the pane doubles the fit: the design got bigger, rather than
    // staying at 0.18 with the extra space left empty around it.
    final t = container.read(viewportTransformProvider);
    expect(t.zoom, closeTo(0.36, 1e-9));
    expect(t.offset.dx, closeTo(400 - 1000 * 0.36, 1e-6));
    expect(t.offset.dy, closeTo(300 - 500 * 0.36, 1e-6));
  });

  testWidgets('a panned canvas keeps its zoom and its centre', (tester) async {
    final container = makeContainer();

    await tester.pumpWidget(host(container, const Size(400, 300)));
    await tester.pumpAndSettle();

    // Any hand movement means the view is no longer "the design" — it is a
    // place at a scale the user chose.
    container
        .read(viewportTransformProvider.notifier)
        .pan(const Offset(60, 20));
    final before = container.read(viewportTransformProvider);
    final centredOn = _designAtCentre(before, const Size(400, 300));

    await tester.pumpWidget(host(container, const Size(700, 500)));
    await tester.pumpAndSettle();

    final after = container.read(viewportTransformProvider);
    expect(after.zoom, before.zoom);
    final nowCentredOn = _designAtCentre(after, const Size(700, 500));
    expect(nowCentredOn.dx, closeTo(centredOn.dx, 1e-6));
    expect(nowCentredOn.dy, closeTo(centredOn.dy, 1e-6));
  });

  testWidgets('the first layout only records the size — it must not move a '
      'camera that has nothing to move relative to', (tester) async {
    final container = makeContainer();

    await tester.pumpWidget(host(container, const Size(400, 300)));
    await tester.pumpAndSettle();

    // Exactly the auto-fit's framing, undisturbed by the resize path.
    final t = container.read(viewportTransformProvider);
    expect(t.zoom, closeTo(0.18, 1e-9));
    expect(t.offset.dx, closeTo(200 - 1000 * 0.18, 1e-6));
    expect(t.offset.dy, closeTo(150 - 500 * 0.18, 1e-6));
  });
}
