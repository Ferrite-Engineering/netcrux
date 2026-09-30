// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Regression for the toolbar "Fit to screen" bug: the fit action must
// frame the whole current scope in the viewport. It used to route to
// `viewportTransformProvider.reset()` (identity zoom at the origin, which
// framed nothing on a large design). The fix fits to bounds against the
// REAL canvas size, which the gesture handler now publishes to
// `canvasFitTargetProvider` — the seam the chrome-level dispatcher reads.
// This test pins both halves: the published target carries the measured
// canvas size + bounds, and fitting with it frames them (not the identity).
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
import 'package:netcrux/features/viewer/providers/canvas_fit_target_provider.dart'
    show canvasFitTargetProvider;
import 'package:netcrux/features/viewer/providers/schematic_canvas_key_provider.dart';
import 'package:netcrux/features/viewer/providers/viewport_transform_notifier.dart';
import 'package:netcrux/features/viewer/rendering/schematic_painter.dart';
import 'package:netcrux/features/viewer/widgets/schematic_gesture_handler.dart';

const _canvasSize = Size(400, 300);
const _bounds = BoundingBox(x: 0, y: 0, width: 2000, height: 1000);

// A small design (smaller than a maximised pane) for the zoom-in regression.
const _smallBounds = BoundingBox(x: 0, y: 0, width: 300, height: 200);

LaidOutGraph _smallGraph() {
  return const LaidOutGraph(
    graph: SchematicGraph(
      moduleName: 'small',
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
      bounds: _smallBounds,
    ),
  );
}

/// The live viewport size the chrome-level fit measures off the canvas'
/// per-tab `RepaintBoundary` render object — mirrors
/// `WorkspaceActionDispatcher._liveCanvasSize`.
Size? liveCanvasSize(ProviderContainer container) {
  final box = container
      .read(schematicCanvasKeyProvider)
      .currentContext
      ?.findRenderObject();
  if (box is RenderBox && box.hasSize && !box.size.isEmpty) return box.size;
  return null;
}

LaidOutGraph _wideGraph() {
  return const LaidOutGraph(
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
}

void main() {
  Widget host(ProviderContainer container) => UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox.fromSize(
            size: _canvasSize,
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

  testWidgets(
    'gesture handler publishes the measured canvas size and auto-fits '
    'to the laid-out bounds',
    (tester) async {
      final container = ProviderContainer(
        overrides: <Override>[
          currentLaidOutGraphProvider.overrideWith((ref) async => _wideGraph()),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(host(container));
      await tester.pumpAndSettle();

      // The published fit target carries the real canvas RenderBox size
      // and the laid-out bounds — the seam the toolbar/palette fit reads.
      final published = container.read(canvasFitTargetProvider);
      expect(published, isNotNull);
      expect(published!.size, _canvasSize);
      expect(published.bounds, _bounds);

      // The auto-fit already framed the bounds via fitToBounds(size,
      // bounds): zoom = min(400/2000, 300/1000) * 0.9 = 0.18, centered.
      final t = container.read(viewportTransformProvider);
      expect(t.zoom, closeTo(0.18, 1e-9));
      expect(t.zoom, lessThan(1)); // not the old identity reset
      expect(t.offset.dx, closeTo(200 - 1000 * 0.18, 1e-6));
      expect(t.offset.dy, closeTo(150 - 500 * 0.18, 1e-6));
    },
  );

  testWidgets(
    'a restored session camera wins over the fit for the scope it was saved in',
    (tester) async {
      final container = ProviderContainer(
        overrides: <Override>[
          currentLaidOutGraphProvider.overrideWith((ref) async => _wideGraph()),
        ],
      );
      addTearDown(container.dispose);
      const saved = ViewportTransform(zoom: 1.25, offset: Offset(12.5, -8));
      // No hierarchy model here, so the laid-out scope is the root path.
      container
          .read(viewportTransformProvider.notifier)
          .requestRestore(const <String>[], saved);

      await tester.pumpWidget(host(container));
      await tester.pumpAndSettle();

      expect(container.read(viewportTransformProvider), saved);
      // The fit target is still published for the toolbar fit.
      expect(container.read(canvasFitTargetProvider)?.bounds, _bounds);
    },
  );

  testWidgets(
    'a camera saved for another scope is dropped and the layout is fitted',
    (tester) async {
      final container = ProviderContainer(
        overrides: <Override>[
          currentLaidOutGraphProvider.overrideWith((ref) async => _wideGraph()),
        ],
      );
      addTearDown(container.dispose);
      container.read(viewportTransformProvider.notifier).requestRestore(
        const <String>['u_cpu'],
        const ViewportTransform(zoom: 3, offset: Offset(1, 1)),
      );

      await tester.pumpWidget(host(container));
      await tester.pumpAndSettle();

      expect(
        container.read(viewportTransformProvider).zoom,
        closeTo(0.18, 1e-9),
      );
      expect(
        container.read(viewportTransformProvider.notifier).takePendingRestore(
          const <String>['u_cpu'],
        ),
        isNull,
        reason: 'the request is spent on the first layout either way',
      );
    },
  );

  testWidgets(
    'the fit seam (published size + bounds -> fitToBounds) reframes after '
    'the transform is disturbed',
    (tester) async {
      final container = ProviderContainer(
        overrides: <Override>[
          currentLaidOutGraphProvider.overrideWith((ref) async => _wideGraph()),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(host(container));
      await tester.pumpAndSettle();

      // Disturb the camera (as panning/zooming would).
      container.read(viewportTransformProvider.notifier).reset();
      expect(
        container.read(viewportTransformProvider),
        ViewportTransform.identity,
      );

      // Reproduce exactly what WorkspaceActionDispatcher.zoomFitAll does:
      // read the published fit target and fit — never touching the async
      // layout provider.
      final target = container.read(canvasFitTargetProvider);
      expect(target, isNotNull);
      container
          .read(viewportTransformProvider.notifier)
          .fitToBounds(target!.size, target.bounds);

      final t = container.read(viewportTransformProvider);
      expect(t.zoom, closeTo(0.18, 1e-9));
      // Framed and centered — the whole design fits inside the viewport.
      expect(_bounds.width * t.zoom, lessThanOrEqualTo(_canvasSize.width));
      expect(_bounds.height * t.zoom, lessThanOrEqualTo(_canvasSize.height));
    },
  );

  testWidgets(
    'chrome-level fit measures the canvas size LIVE, so it zooms IN to fill '
    'a pane that grew after load (published size went stale)',
    (tester) async {
      // Reproduces the "fit never zooms in" bug: after a pane/window resize
      // with no scope change the gesture handler does NOT rebuild, so the
      // size cached in canvasFitTargetProvider is stale. The chrome fit must
      // therefore read the size LIVE off the canvas render object.
      // Default test surface is 800x600; make room for the grown pane.
      await tester.binding.setSurfaceSize(const Size(1400, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final sizeListenable = ValueNotifier<Size>(const Size(400, 300));
      addTearDown(sizeListenable.dispose);

      final container = ProviderContainer(
        overrides: <Override>[
          currentLaidOutGraphProvider.overrideWith(
            (ref) async => _smallGraph(),
          ),
        ],
      );
      addTearDown(container.dispose);

      // The per-tab canvas key, attached to the RepaintBoundary that wraps
      // the canvas — exactly as project_tab_content does. Its render object
      // is what the dispatcher measures live.
      final canvasKey = container.read(schematicCanvasKeyProvider);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: ValueListenableBuilder<Size>(
                  valueListenable: sizeListenable,
                  builder: (context, size, child) =>
                      SizedBox.fromSize(size: size, child: child),
                  child: SchematicGestureHandler(
                    autofocus: false,
                    child: RepaintBoundary(
                      key: canvasKey,
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Published on load against the 400x300 pane.
      expect(
        container.read(canvasFitTargetProvider)!.size,
        const Size(400, 300),
      );

      // Grow the pane (window maximise / panel collapse) — no scope change,
      // so the gesture handler never rebuilds and never republishes.
      sizeListenable.value = const Size(1200, 800);
      await tester.pumpAndSettle();

      // The cached size is now STALE, but the live measurement is current.
      expect(
        container.read(canvasFitTargetProvider)!.size,
        const Size(400, 300),
        reason: 'cached size does not track a resize (the bug source)',
      );
      final live = liveCanvasSize(container);
      expect(live, const Size(1200, 800), reason: 'live size is current');

      // Fit exactly as WorkspaceActionDispatcher.zoomFitAll now does:
      // bounds from the (fresh) target, size measured LIVE.
      final target = container.read(canvasFitTargetProvider)!;
      container
          .read(viewportTransformProvider.notifier)
          .fitToBounds(live ?? target.size, target.bounds);
      final t = container.read(viewportTransformProvider);

      // 300x200 into 1200x800: min(1200/300, 800/200) * 0.9 = 4 * 0.9 = 3.6.
      expect(t.zoom, closeTo(3.6, 1e-9));
      expect(t.zoom, greaterThan(1), reason: 'small design must zoom IN');
      // Fills the grown viewport in both directions and stays inside it.
      expect(_smallBounds.width * t.zoom, closeTo(1080, 1e-6));
      expect(_smallBounds.width * t.zoom, lessThanOrEqualTo(1200));
      expect(_smallBounds.height * t.zoom, lessThanOrEqualTo(800));
      // Centered.
      expect(t.offset.dx, closeTo(600 - 150 * 3.6, 1e-6));
      expect(t.offset.dy, closeTo(400 - 100 * 3.6, 1e-6));

      // Contrast: fitting against the STALE cached size would leave the
      // design tiny — this is the regressed behaviour the fix removes.
      container
          .read(viewportTransformProvider.notifier)
          .fitToBounds(target.size, target.bounds);
      final stale = container.read(viewportTransformProvider);
      expect(stale.zoom, closeTo(1.2, 1e-9)); // 400/300 fit, way under-filled
      expect(_smallBounds.width * stale.zoom, lessThan(600));
    },
  );
}
