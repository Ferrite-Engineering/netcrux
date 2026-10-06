// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/bookmark.dart';
import 'package:netcrux/domain/models/layout/bounding_box.dart';
import 'package:netcrux/domain/models/layout/edge_route.dart';
import 'package:netcrux/domain/models/layout/netlist_layout.dart';
import 'package:netcrux/domain/models/layout/node_position.dart';
import 'package:netcrux/domain/models/netlist/port_direction.dart';
import 'package:netcrux/domain/models/schematic/cell_kind.dart';
import 'package:netcrux/domain/models/schematic/laid_out_graph.dart';
import 'package:netcrux/domain/models/schematic/schematic_graph.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/features/project/providers/current_laid_out_graph_provider.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/features/viewer/providers/viewport_transform_notifier.dart';
import 'package:netcrux/features/viewer/widgets/schematic_gesture_handler.dart';
import 'package:netcrux/services/schematic/schematic_annotation_markers_provider.dart';
import 'package:netcrux/services/session/bookmark_annotation_openers.dart';

const Size _kCanvasSize = Size(400, 300);

/// A non-empty laid-out graph whose layout bounds (2000 × 6000) are far
/// larger than the canvas — so a correct fit drives the zoom well below 1.0.
LaidOutGraph _bigLaidOutGraph() {
  const cell = SchematicCell(
    id: 'c0',
    kind: CellKind.andGate,
    type: r'$and',
    ports: <SchematicPort>[
      SchematicPort(
        id: 'c0:Y',
        name: 'Y',
        direction: PortDirection.output,
        side: SchematicPortSide.east,
      ),
    ],
  );
  const graph = SchematicGraph(
    moduleName: 'big',
    cells: <SchematicCell>[cell],
    boundaryPorts: <SchematicBoundaryPort>[],
    edges: <SchematicEdge>[],
  );
  const layout = NetlistLayout(
    nodes: <NodePosition>[
      NodePosition(
        id: 'c0',
        bounds: BoundingBox(x: 0, y: 0, width: 80, height: 60),
      ),
    ],
    edges: <EdgeRoute>[],
    bounds: BoundingBox(x: 0, y: 0, width: 2000, height: 6000),
  );
  return const LaidOutGraph(graph: graph, layout: layout);
}

/// A laid-out graph whose bounds match the canvas 1:1 and that holds a
/// single 80 × 60 cell at design (100, 100) — so the click-selection
/// tests can convert a design point to a canvas point with the transform
/// the auto-fit settled on.
LaidOutGraph _clickTargetGraph() {
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

/// Maps a design-space point to a global (screen) point under the
/// transform currently held by [container] — the same
/// `design * zoom + offset` mapping the painter and hit-tester use.
Offset _globalForDesign(
  WidgetTester tester,
  ProviderContainer container,
  Offset design,
) {
  final transform = container.read(viewportTransformProvider);
  final topLeft = tester.getTopLeft(find.byType(SchematicGestureHandler));
  return topLeft + design * transform.zoom + transform.offset;
}

Widget _harness({
  required ProviderContainer container,
  bool autofocus = true,
  Widget child = const ColoredBox(color: Color(0xFF202024)),
}) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox.fromSize(
            size: _kCanvasSize,
            child: SchematicGestureHandler(
              autofocus: autofocus,
              child: child,
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('SchematicGestureHandler — focus follows the pointer', () {
    final buttonFocus = FocusNode(debugLabel: 'panel button');
    final fieldFocus = FocusNode(debugLabel: 'filter field');
    tearDownAll(() {
      buttonFocus.dispose();
      fieldFocus.dispose();
    });

    /// The canvas beside a panel holding a button and a text field, the way
    /// the hierarchy dock sits beside the schematic.
    Future<ProviderContainer> pumpWithPanel(WidgetTester tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Row(
                children: <Widget>[
                  SizedBox(
                    width: 200,
                    child: Column(
                      children: <Widget>[
                        TextButton(
                          focusNode: buttonFocus,
                          onPressed: () {},
                          child: const Text('panel'),
                        ),
                        TextField(focusNode: fieldFocus),
                      ],
                    ),
                  ),
                  SizedBox.fromSize(
                    size: _kCanvasSize,
                    child: const SchematicGestureHandler(
                      autofocus: false,
                      child: ColoredBox(color: Color(0xFF202024)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return container;
    }

    Future<TestGesture> hoverOntoCanvas(WidgetTester tester) async {
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: const Offset(100, 500));
      await tester.pump();
      await mouse.moveTo(
        tester.getCenter(find.byType(SchematicGestureHandler)),
      );
      await tester.pump();
      return mouse;
    }

    testWidgets('the pointer entering the canvas takes focus from a panel, '
        'so the bare zoom keys work', (tester) async {
      final container = await pumpWithPanel(tester);
      buttonFocus.requestFocus();
      await tester.pump();

      await hoverOntoCanvas(tester);
      expect(buttonFocus.hasFocus, isFalse);

      await tester.sendKeyEvent(LogicalKeyboardKey.equal);
      await tester.pump();
      expect(container.read(viewportTransformProvider).zoom, greaterThan(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a text field mid-edit keeps focus when the pointer enters', (
      tester,
    ) async {
      final container = await pumpWithPanel(tester);
      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'add');
      await tester.pump();

      await hoverOntoCanvas(tester);
      expect(fieldFocus.hasFocus, isTrue);

      // `=` lands in the field, not on the canvas.
      await tester.sendKeyEvent(LogicalKeyboardKey.equal);
      await tester.pump();
      expect(container.read(viewportTransformProvider).zoom, 1);
    });

    testWidgets('a right-click on the canvas takes focus, even from a text '
        'field', (tester) async {
      final container = await pumpWithPanel(tester);
      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(fieldFocus.hasFocus, isTrue);

      final center = tester.getCenter(find.byType(SchematicGestureHandler));
      final mouse = await tester.startGesture(
        center,
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await mouse.up();
      await tester.pump();
      expect(fieldFocus.hasFocus, isFalse);

      await tester.sendKeyEvent(LogicalKeyboardKey.equal);
      await tester.pump();
      expect(container.read(viewportTransformProvider).zoom, greaterThan(1));
    });

    test('hoverMayTakeFocus is true when nothing has focus', () {
      expect(SchematicGestureHandler.hoverMayTakeFocus(null), isTrue);
    });
  });

  group('SchematicGestureHandler — scroll wheel', () {
    testWidgets('Cmd+wheel up zooms in around the pointer', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(_harness(container: container));
      await tester.pumpAndSettle();

      // Hold Cmd (we just check meta — the handler also accepts ctrl)
      // and emit a scroll event at a known canvas position.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      try {
        final center = tester.getCenter(find.byType(SchematicGestureHandler));
        final testPointer = TestPointer(1, PointerDeviceKind.mouse);
        await tester.sendEventToBinding(
          testPointer.hover(center),
        );
        await tester.sendEventToBinding(
          testPointer.scroll(const Offset(0, -120)),
        );
        await tester.pumpAndSettle();
      } finally {
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      }
      expect(
        container.read(viewportTransformProvider).zoom,
        greaterThan(1.0),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('plain scroll wheel pans the view (no zoom)', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(_harness(container: container));
      await tester.pumpAndSettle();
      final center = tester.getCenter(find.byType(SchematicGestureHandler));
      final testPointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(testPointer.hover(center));
      await tester.sendEventToBinding(
        testPointer.scroll(const Offset(40, 10)),
      );
      await tester.pumpAndSettle();
      final state = container.read(viewportTransformProvider);
      expect(state.zoom, 1.0);
      expect(state.offset, isNot(Offset.zero));
      expect(tester.takeException(), isNull);
    });
  });

  group('SchematicGestureHandler — auto-fit', () {
    testWidgets('fits the camera to the scope already present on mount', (
      tester,
    ) async {
      // The handler is only built once the layout has loaded, so the value
      // is present when it first mounts. Regression: a `ref.listen` never
      // fires for that already-present value, leaving a large scope at the
      // identity transform (top-left corner). It must `watch` + fit on the
      // first frame.
      final container = ProviderContainer(
        overrides: [
          currentLaidOutGraphProvider.overrideWith(
            (ref) async => _bigLaidOutGraph(),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(_harness(container: container));
      await tester.pumpAndSettle();

      final transform = container.read(viewportTransformProvider);
      // 2000×6000 bounds into a 400×300 canvas → height-limited fit far
      // below 1.0; before the fix it stayed at the identity transform.
      expect(transform.zoom, lessThan(0.2));
      expect(transform.offset, isNot(Offset.zero));
      expect(tester.takeException(), isNull);
    });
  });

  group('SchematicGestureHandler — keyboard', () {
    testWidgets('arrow keys pan; 0 fits the current scope to view', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(_harness(container: container));
      await tester.pumpAndSettle();
      // Focus is requested in initState. The handler's Focus node
      // should now own the keyboard.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      final pannedState = container.read(viewportTransformProvider);
      expect(pannedState.offset.dx, isNonZero);
      expect(pannedState.offset.dy, isNonZero);

      // `0` is Fit-All: it fits the loaded scope's bounds (the real fit math
      // lives in `viewport_transform_notifier_test.dart`). With no design
      // loaded in this harness there are no bounds to fit, so it is a no-op
      // — it no longer blindly snaps back to the identity transform, which
      // would throw away a large design's fitted camera.
      await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
      await tester.pumpAndSettle();
      expect(container.read(viewportTransformProvider), pannedState);
      expect(tester.takeException(), isNull);
    });

    testWidgets('+ zooms in, - zooms out, both bounded', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(_harness(container: container));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.equal);
      await tester.pumpAndSettle();
      expect(
        container.read(viewportTransformProvider).zoom,
        greaterThan(1.0),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.minus);
      await tester.pumpAndSettle();
      // Round-tripping should land close to 1.0 because the +/-
      // ratios are reciprocal, modulo clamp.
      expect(
        container.read(viewportTransformProvider).zoom,
        closeTo(1.0, 1e-9),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('SchematicGestureHandler — context menu wiring', () {
    testWidgets('wraps the canvas in the shared PlatformContextMenu', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(_harness(container: container));
      await tester.pumpAndSettle();

      final menu = tester.widget<PlatformContextMenu>(
        find.byType(PlatformContextMenu),
      );
      // The call site supplies the context-menu callback and leaves
      // isTouchLayout at the desktop default (NetCrux has no touch device
      // class); the shared widget still enables long-press on non-desktop
      // hosts via its own platform check.
      expect(menu.onContextMenu, isNotNull);
      expect(menu.isTouchLayout, isFalse);
    });

    testWidgets('right-click and long-press both route to the handler', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(_harness(container: container));
      await tester.pumpAndSettle();

      final center = tester.getCenter(find.byType(PlatformContextMenu));
      // Right-click (secondary tap-up) reaches _onContextMenu on every host.
      await tester.tapAt(center, buttons: kSecondaryMouseButton);
      await tester.pump();
      // Long-press reaches it on the touch-first test platform (the default
      // TargetPlatform in widget tests is non-desktop, so the shared widget
      // enables the long-press trigger). Empty canvas → the handler
      // hit-tests to none and returns without a menu.
      await tester.longPress(find.byType(PlatformContextMenu));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('SchematicGestureHandler — click selection', () {
    // Latency contract for every test in this group: the selection is
    // asserted on the FIRST frame after the click, with no artificial
    // clock advance. Selection used to hang off `GestureDetector.onTapUp`,
    // which cannot fire until the tap recognizer WINS the gesture arena —
    // and the sibling `onDoubleTap` (push into scope) HOLDS that arena for
    // the whole kDoubleTapTimeout (~300 ms). Advancing the clock before
    // asserting would hide exactly the defect these tests exist to catch.
    Future<ProviderContainer> pumpCanvas(WidgetTester tester) async {
      final container = ProviderContainer(
        overrides: [
          currentLaidOutGraphProvider.overrideWith(
            (ref) async => _clickTargetGraph(),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(_harness(container: container));
      await tester.pumpAndSettle();
      return container;
    }

    /// Drains the double-tap recognizer's disambiguation timer so it does
    /// not outlive the test. Always called AFTER the first-frame
    /// assertions — never before, or the latency contract above would go
    /// untested.
    Future<void> drainDoubleTapTimer(WidgetTester tester) =>
        tester.pump(const Duration(milliseconds: 400));

    testWidgets('a left click selects the cell under it on the next frame', (
      tester,
    ) async {
      final container = await pumpCanvas(tester);
      await tester.tapAt(
        _globalForDesign(tester, container, const Offset(140, 130)),
      );
      await tester.pump();

      expect(
        container.read(selectedElementProvider).primary,
        const SelectedElement.cell(cellId: 'u_alu'),
      );
      expect(tester.takeException(), isNull);
      await drainDoubleTapTimer(tester);
    });

    testWidgets('a left click on empty canvas clears the selection', (
      tester,
    ) async {
      final container = await pumpCanvas(tester);
      container
          .read(selectedElementProvider.notifier)
          .select(const SelectedElement.cell(cellId: 'u_alu'));

      await tester.tapAt(
        _globalForDesign(tester, container, const Offset(10, 10)),
      );
      await tester.pump();

      expect(container.read(selectedElementProvider).isEmpty, isTrue);
      await drainDoubleTapTimer(tester);
    });

    testWidgets('shift-click adds to the selection immediately', (
      tester,
    ) async {
      final container = await pumpCanvas(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      try {
        await tester.tapAt(
          _globalForDesign(tester, container, const Offset(140, 130)),
        );
        await tester.pump();
      } finally {
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      }
      expect(
        container.read(selectedElementProvider).elements,
        contains(const SelectedElement.cell(cellId: 'u_alu')),
      );
      await drainDoubleTapTimer(tester);
    });

    testWidgets('a drag past the tap slop pans without selecting', (
      tester,
    ) async {
      // Drag-to-cancel is the reason selection fires on pointer-UP with a
      // slop check rather than on pointer-down: pressing on a cell and
      // dragging pans the canvas and must leave the selection alone.
      final container = await pumpCanvas(tester);
      final start = _globalForDesign(tester, container, const Offset(140, 130));
      final gesture = await tester.startGesture(start);
      await gesture.moveBy(const Offset(60, 40));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(container.read(selectedElementProvider).isEmpty, isTrue);
      expect(
        container.read(viewportTransformProvider).offset,
        isNot(Offset.zero),
      );
      await drainDoubleTapTimer(tester);
    });

    testWidgets('a double click still pushes into the scope and clears', (
      tester,
    ) async {
      // The pointer-up selection must not cost the double-click its own
      // action: both taps select, then the double-tap runs its scope
      // change and clears the selection behind it.
      final container = await pumpCanvas(tester);
      final at = _globalForDesign(tester, container, const Offset(140, 130));
      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        container.read(selectedElementProvider).primary,
        const SelectedElement.cell(cellId: 'u_alu'),
      );
      await tester.tapAt(at);
      await tester.pumpAndSettle();

      expect(container.read(selectedElementProvider).isEmpty, isTrue);
      expect(tester.takeException(), isNull);
    });
  });

  group('SchematicGestureHandler — hit-test opacity', () {
    testWidgets('left-drag pans even when the canvas child reports no '
        'self-hit', (tester) async {
      // Regression guard for the dead drag-pan bug: the real
      // `SchematicCanvasRenderObject` is a pure painter with no
      // `hitTestSelf` override, and both GestureDetectors between it and
      // the handler's raw Listener are translucent — so under the
      // Listener's default deferToChild behavior the whole branch
      // reported "not hit" and the Listener dropped out of the hit path
      // (scale callbacks still fired via translucent self-registration,
      // which is what made the bug look "wired but dead"). The other
      // tests in this file mask that with a ColoredBox child, which IS
      // self-hit-testable; this one reproduces production with a child
      // that is not (SizedBox.expand → RenderConstrainedBox, no
      // self-hit).
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        _harness(container: container, child: const SizedBox.expand()),
      );
      await tester.pumpAndSettle();

      final center = tester.getCenter(find.byType(SchematicGestureHandler));
      final gesture = await tester.startGesture(
        center,
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(25, 35));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      final state = container.read(viewportTransformProvider);
      expect(state.offset.dx, closeTo(25, 1e-9));
      expect(state.offset.dy, closeTo(35, 1e-9));
      expect(tester.takeException(), isNull);
    });
  });

  group('SchematicGestureHandler — middle-button drag', () {
    testWidgets('middle-button drag pans the view', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(_harness(container: container));
      await tester.pumpAndSettle();
      final center = tester.getCenter(find.byType(SchematicGestureHandler));
      final testPointer = TestPointer(2, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(
        testPointer.down(center, buttons: kMiddleMouseButton),
      );
      await tester.sendEventToBinding(
        testPointer.move(center + const Offset(20, 30)),
      );
      await tester.sendEventToBinding(testPointer.up());
      await tester.pumpAndSettle();
      final state = container.read(viewportTransformProvider);
      expect(state.offset.dx, closeTo(20, 1e-9));
      expect(state.offset.dy, closeTo(30, 1e-9));
      expect(tester.takeException(), isNull);
    });
  });

  group('SchematicGestureHandler — annotation badge', () {
    // The cell u_alu spans design (100, 100) to (180, 160); its badge is
    // centred on the top-right corner, (180, 100).
    Future<(ProviderContainer, List<BookmarkAnnotationTarget>)> pumpBadged(
      WidgetTester tester, {
      SchematicAnnotationMarkers? markers,
    }) async {
      final opened = <BookmarkAnnotationTarget>[];
      final container = ProviderContainer(
        overrides: [
          currentLaidOutGraphProvider.overrideWith(
            (ref) async => _clickTargetGraph(),
          ),
          schematicAnnotationMarkersProvider.overrideWithValue(
            markers ??
                SchematicAnnotationMarkers.from(
                  const <SchematicAnnotationMarker>[
                    SchematicAnnotationMarker(
                      kind: BookmarkTargetKind.cell,
                      targetId: 'u_alu',
                      annotationIds: <String>['a1'],
                    ),
                  ],
                ),
          ),
          showAnnotationForTargetOpenerProvider.overrideWithValue(
            (_, _, target) => opened.add(target),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(_harness(container: container));
      await tester.pumpAndSettle();
      return (container, opened);
    }

    testWidgets('a click on the badge opens the annotation and selects', (
      tester,
    ) async {
      final (container, opened) = await pumpBadged(tester);
      await tester.tapAt(
        _globalForDesign(tester, container, const Offset(182, 98)),
      );
      await tester.pump();

      expect(opened, hasLength(1));
      expect(opened.single.kind, BookmarkTargetKind.cell);
      expect(opened.single.targetId, 'u_alu');
      expect(
        container.read(selectedElementProvider).primary,
        const SelectedElement.cell(cellId: 'u_alu'),
      );
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('a click on the cell body away from the badge only selects', (
      tester,
    ) async {
      final (container, opened) = await pumpBadged(tester);
      await tester.tapAt(
        _globalForDesign(tester, container, const Offset(120, 140)),
      );
      await tester.pump();

      expect(opened, isEmpty);
      expect(
        container.read(selectedElementProvider).primary,
        const SelectedElement.cell(cellId: 'u_alu'),
      );
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('with no annotations the badge corner selects as before', (
      tester,
    ) async {
      final (container, opened) = await pumpBadged(
        tester,
        markers: SchematicAnnotationMarkers.empty,
      );
      // Just outside the cell box, where the badge would overhang: empty
      // canvas, so the click clears.
      container
          .read(selectedElementProvider.notifier)
          .select(const SelectedElement.cell(cellId: 'u_alu'));
      await tester.tapAt(
        _globalForDesign(tester, container, const Offset(183, 97)),
      );
      await tester.pump();

      expect(opened, isEmpty);
      expect(container.read(selectedElementProvider).isEmpty, isTrue);
      await tester.pump(const Duration(milliseconds: 400));
    });
  });
}
