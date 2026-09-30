// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// LOCALE_SWEEP_EXEMPT: this file renders no text at all. `SchematicScrollbars`
// draws two geometric bands, and every assertion here is coordinate arithmetic
// — band thickness, hit rectangles, and the viewport offset a drag produces.
// The MaterialApp carries localization delegates only because the widget sits
// under one in production; swapping the locale would change nothing on screen
// and the sweep would assert that nothing changed.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/layout/bounding_box.dart';
import 'package:netcrux/features/viewer/providers/viewport_transform_notifier.dart';
import 'package:netcrux/features/viewer/widgets/schematic_gesture_handler.dart';
import 'package:netcrux/features/viewer/widgets/schematic_scrollbars.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

const Size _kCanvasSize = Size(400, 300);

/// Bounds much larger than the canvas so both axes are scrollable at the
/// identity transform (visible extent 386 × 286 < 2000 × 2000).
const BoundingBox _kBigBounds = BoundingBox(
  x: 0,
  y: 0,
  width: 2000,
  height: 2000,
);

Widget _harness({required ProviderContainer container}) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      localizationsDelegates: L10N.localizationsDelegates,
      supportedLocales: L10N.supportedLocales,
      home: Scaffold(
        body: Center(
          child: SizedBox.fromSize(
            size: _kCanvasSize,
            child: const SchematicScrollbars(
              bounds: _kBigBounds,
              // The real center child: the gesture handler, whose raw
              // Listener is HitTestBehavior.opaque (the drag-pan fix). The
              // scrollbar bands are siblings of that opaque region, so
              // they must keep receiving their own drags.
              child: SchematicGestureHandler(
                autofocus: false,
                child: SizedBox.expand(),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('SchematicScrollbars', () {
    testWidgets(
      'horizontal thumb drag pans even with the opaque gesture '
      'handler as the canvas child',
      (tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await tester.pumpWidget(_harness(container: container));
        await tester.pumpAndSettle();

        final rect = tester.getRect(find.byType(SchematicScrollbars));
        // At identity transform the thumb starts at the track origin;
        // grab it inside its first ~74 px and drag right.
        final grab = Offset(
          rect.left + 30,
          rect.bottom - SchematicScrollbars.bandThickness / 2,
        );
        final gesture = await tester.startGesture(grab);
        // Multiple moves: the first is consumed winning the drag arena
        // (pan-start), the rest produce pan-updates.
        await gesture.moveBy(const Offset(30, 0));
        await tester.pump();
        await gesture.moveBy(const Offset(30, 0));
        await tester.pump();
        await gesture.moveBy(const Offset(20, 0));
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();

        final state = container.read(viewportTransformProvider);
        // Dragging the thumb right scrolls the visible window right,
        // which pans the canvas offset negative along x.
        expect(state.offset.dx, lessThan(0));
        expect(state.offset.dy, 0);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'vertical thumb drag pans even with the opaque gesture '
      'handler as the canvas child',
      (tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await tester.pumpWidget(_harness(container: container));
        await tester.pumpAndSettle();

        final rect = tester.getRect(find.byType(SchematicScrollbars));
        final grab = Offset(
          rect.right - SchematicScrollbars.bandThickness / 2,
          rect.top + 30,
        );
        final gesture = await tester.startGesture(grab);
        await gesture.moveBy(const Offset(0, 30));
        await tester.pump();
        await gesture.moveBy(const Offset(0, 30));
        await tester.pump();
        await gesture.moveBy(const Offset(0, 20));
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();

        final state = container.read(viewportTransformProvider);
        expect(state.offset.dy, lessThan(0));
        expect(state.offset.dx, 0);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'a drag on the canvas area pans via the handler, not the scrollbars',
      (tester) async {
        // Sanity cross-check: a drag INSIDE the canvas region uses the
        // free-form pointer pan (both axes), proving the opaque Listener
        // and the scrollbar bands split the pane cleanly.
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await tester.pumpWidget(_harness(container: container));
        await tester.pumpAndSettle();

        final rect = tester.getRect(find.byType(SchematicScrollbars));
        final gesture = await tester.startGesture(
          rect.center - const Offset(20, 20),
        );
        await gesture.moveBy(const Offset(25, 35));
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();

        final state = container.read(viewportTransformProvider);
        expect(state.offset.dx, closeTo(25, 1e-9));
        expect(state.offset.dy, closeTo(35, 1e-9));
        expect(tester.takeException(), isNull);
      },
    );
  });
}
