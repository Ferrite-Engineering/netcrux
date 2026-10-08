// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/layout/bounding_box.dart';
import 'package:netcrux/features/viewer/providers/viewport_transform_notifier.dart';
import 'package:netcrux/features/viewer/rendering/schematic_painter.dart';

void main() {
  ProviderContainer makeContainer() {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    return container;
  }

  group('initial state', () {
    test('starts at the identity transform', () {
      final container = makeContainer();
      expect(
        container.read(viewportTransformProvider),
        ViewportTransform.identity,
      );
    });
  });

  group('pan', () {
    test('accumulates offset deltas; zoom unchanged', () {
      final container = makeContainer();
      final notifier = container.read(viewportTransformProvider.notifier)
        ..pan(const Offset(10, 20))
        ..pan(const Offset(5, -3));
      final state = container.read(viewportTransformProvider);
      expect(state.zoom, 1.0);
      expect(state.offset, const Offset(15, 17));
      expect(notifier, isNotNull);
    });
  });

  group('setZoom', () {
    test('respects the zoom clamp', () {
      final container = makeContainer();
      container.read(viewportTransformProvider.notifier).setZoom(0.001);
      expect(
        container.read(viewportTransformProvider).zoom,
        SchematicViewportLimits.minZoom,
      );
      container.read(viewportTransformProvider.notifier).setZoom(1000);
      expect(
        container.read(viewportTransformProvider).zoom,
        SchematicViewportLimits.maxZoom,
      );
    });

    test('setting the same zoom is a no-op', () {
      final container = makeContainer();
      final notifier = container.read(viewportTransformProvider.notifier)
        ..setZoom(1);
      final before = container.read(viewportTransformProvider);
      notifier.setZoom(1);
      expect(
        identical(before, container.read(viewportTransformProvider)),
        isTrue,
      );
    });
  });

  group('zoomAt', () {
    test('preserves the focal-point design coordinate', () {
      final container = makeContainer();
      final notifier = container.read(viewportTransformProvider.notifier);
      const focal = Offset(120, 80);

      // The design coordinate under `focal` before zoom must equal the
      // design coordinate under `focal` after zoom.
      Offset designCoord() {
        final t = container.read(viewportTransformProvider);
        return (focal - t.offset) / t.zoom;
      }

      final before = designCoord();
      notifier.zoomAt(focal, 1.5);
      final after = designCoord();
      expect(after.dx, closeTo(before.dx, 1e-9));
      expect(after.dy, closeTo(before.dy, 1e-9));
    });

    test('clamps zoom and skips when no change is possible', () {
      final container = makeContainer();
      // Push zoom to the ceiling, then try to zoom in again — should
      // be a no-op (zoom stays at maxZoom, offset stays where it was).
      container.read(viewportTransformProvider.notifier)
        ..setZoom(SchematicViewportLimits.maxZoom)
        ..zoomAt(const Offset(50, 50), 10);
      final after = container.read(viewportTransformProvider);
      expect(after.zoom, SchematicViewportLimits.maxZoom);
    });
  });

  group('reset', () {
    test('returns to the identity transform', () {
      final container = makeContainer();
      final notifier = container.read(viewportTransformProvider.notifier)
        ..pan(const Offset(30, 40))
        ..setZoom(2);
      expect(
        container.read(viewportTransformProvider),
        isNot(ViewportTransform.identity),
      );
      notifier.reset();
      expect(
        container.read(viewportTransformProvider),
        ViewportTransform.identity,
      );
    });

    test('reset from identity is a no-op (object identity)', () {
      final container = makeContainer();
      final before = container.read(viewportTransformProvider);
      container.read(viewportTransformProvider.notifier).reset();
      expect(
        identical(before, container.read(viewportTransformProvider)),
        isTrue,
      );
    });
  });

  group('fitToBounds', () {
    test('fits a tall layout into the viewport and centers the content', () {
      final container = makeContainer();
      container
          .read(viewportTransformProvider.notifier)
          .fitToBounds(
            const Size(800, 600),
            const BoundingBox(x: 0, y: 0, width: 1000, height: 4000),
          );
      final t = container.read(viewportTransformProvider);
      // zoom = min(800/1000, 600/4000) * 0.9 = 0.15 * 0.9 = 0.135.
      expect(t.zoom, closeTo(0.135, 1e-9));
      // Content centre (500, 2000) maps to the viewport centre (400, 300):
      // offset = viewportCentre - contentCentre * zoom.
      expect(t.offset.dx, closeTo(400 - 500 * 0.135, 1e-6));
      expect(t.offset.dy, closeTo(300 - 2000 * 0.135, 1e-6));
    });

    test('zooms IN (zoom > 1) for a design smaller than the viewport', () {
      // Regression: pressing "Fit" from a zoomed-out state on a small
      // design must ENLARGE it to fill the viewport, not only shrink large
      // designs. 200x150 into 1000x800: min(1000/200, 800/150) * 0.9 =
      // min(5, 5.333) * 0.9 = 4.5.
      final container = makeContainer();
      container
          .read(viewportTransformProvider.notifier)
          .fitToBounds(
            const Size(1000, 800),
            const BoundingBox(x: 0, y: 0, width: 200, height: 150),
          );
      final t = container.read(viewportTransformProvider);
      expect(t.zoom, closeTo(4.5, 1e-9));
      expect(t.zoom, greaterThan(1));
      // Content centre (100, 75) lands at the viewport centre (500, 400).
      expect(t.offset.dx, closeTo(500 - 100 * 4.5, 1e-6));
      expect(t.offset.dy, closeTo(400 - 75 * 4.5, 1e-6));
      // The whole design fits inside the viewport in BOTH directions.
      expect(200 * t.zoom, lessThanOrEqualTo(1000));
      expect(150 * t.zoom, lessThanOrEqualTo(800));
    });

    test('honours a non-zero bounds origin when centering', () {
      final container = makeContainer();
      container
          .read(viewportTransformProvider.notifier)
          .fitToBounds(
            const Size(1000, 1000),
            const BoundingBox(x: 200, y: 100, width: 500, height: 500),
          );
      final t = container.read(viewportTransformProvider);
      // zoom = min(1000/500, 1000/500) * 0.9 = 1.8.
      expect(t.zoom, closeTo(1.8, 1e-9));
      // Content centre is (450, 350) here, not (250, 250).
      expect(t.offset.dx, closeTo(500 - 450 * 1.8, 1e-6));
      expect(t.offset.dy, closeTo(500 - 350 * 1.8, 1e-6));
    });

    test('allows fitting a huge layout below the old 0.1 zoom floor', () {
      final container = makeContainer();
      // picorv32-scale core: ~15 000 × 43 000 px into a typical window.
      container
          .read(viewportTransformProvider.notifier)
          .fitToBounds(
            const Size(1400, 900),
            const BoundingBox(x: 0, y: 0, width: 15000, height: 43000),
          );
      final zoom = container.read(viewportTransformProvider).zoom;
      expect(zoom, lessThan(0.1)); // would have been clamped before
      expect(zoom, greaterThanOrEqualTo(SchematicViewportLimits.minZoom));
    });

    test('fits a hundred-thousand-cell flat scope in one view', () {
      final container = makeContainer();
      // grid_100k laid out natively: 472 368 × 276 779 px. The 0.01 floor
      // clamped this fit and centred the camera on empty space between
      // packed components; the whole scope must fit now.
      const bounds = BoundingBox(x: 0, y: 0, width: 472368, height: 276779);
      container
          .read(viewportTransformProvider.notifier)
          .fitToBounds(const Size(1400, 900), bounds);
      final t = container.read(viewportTransformProvider);
      expect(t.zoom, lessThan(0.01));
      expect(t.zoom, greaterThan(SchematicViewportLimits.minZoom));
      // Every corner of the bounds lands inside the viewport.
      expect(t.offset.dx + bounds.width * t.zoom, lessThanOrEqualTo(1400));
      expect(t.offset.dy + bounds.height * t.zoom, lessThanOrEqualTo(900));
      expect(t.offset.dx, greaterThanOrEqualTo(0));
      expect(t.offset.dy, greaterThanOrEqualTo(0));
    });

    test('zoomAboutCenter keeps the viewport centre where it is', () {
      final container = makeContainer();
      final notifier = container.read(viewportTransformProvider.notifier);
      const viewport = Size(1400, 900);
      // Somewhere far from the design origin, as in a big flat scope.
      notifier.fitToBounds(
        viewport,
        const BoundingBox(x: 200000, y: 150000, width: 4000, height: 3000),
      );
      final before = container.read(viewportTransformProvider);
      // The design point under the viewport centre before the step.
      final centreBefore = Offset(
        (viewport.width / 2 - before.offset.dx) / before.zoom,
        (viewport.height / 2 - before.offset.dy) / before.zoom,
      );
      notifier.zoomAboutCenter(1.25);
      final after = container.read(viewportTransformProvider);
      expect(after.zoom, closeTo(before.zoom * 1.25, 1e-12));
      final centreAfter = Offset(
        (viewport.width / 2 - after.offset.dx) / after.zoom,
        (viewport.height / 2 - after.offset.dy) / after.zoom,
      );
      expect(centreAfter.dx, closeTo(centreBefore.dx, 1e-6));
      expect(centreAfter.dy, closeTo(centreBefore.dy, 1e-6));
    });

    test('zoomAboutCenter before any layout falls back to a plain zoom', () {
      final container = makeContainer();
      container.read(viewportTransformProvider.notifier).zoomAboutCenter(2);
      expect(container.read(viewportTransformProvider).zoom, 2.0);
    });

    test('no-ops on a degenerate viewport', () {
      final container = makeContainer();
      container
          .read(viewportTransformProvider.notifier)
          .fitToBounds(
            Size.zero,
            const BoundingBox(x: 0, y: 0, width: 100, height: 100),
          );
      expect(
        container.read(viewportTransformProvider),
        ViewportTransform.identity,
      );
    });

    test('no-ops on empty bounds', () {
      final container = makeContainer();
      container
          .read(viewportTransformProvider.notifier)
          .fitToBounds(
            const Size(800, 600),
            const BoundingBox(x: 0, y: 0, width: 0, height: 0),
          );
      expect(
        container.read(viewportTransformProvider),
        ViewportTransform.identity,
      );
    });
  });

  group('revealBounds (reveal element)', () {
    test('centers a tiny cell and caps zoom at comfortZoom (not maxZoom)', () {
      final container = makeContainer();
      // A 40x30 cell in an 800x600 viewport: fitZoom would be ~12, far
      // above comfortZoom (1.5), so the cap wins — the cell is centered at
      // a readable scale rather than slammed to maxZoom.
      container
          .read(viewportTransformProvider.notifier)
          .revealBounds(
            const Size(800, 600),
            const BoundingBox(x: 1000, y: 2000, width: 40, height: 30),
          );
      final t = container.read(viewportTransformProvider);
      expect(t.zoom, closeTo(1.5, 1e-9));
      // Cell centre (1020, 2015) lands at the viewport centre (400, 300).
      expect(t.offset.dx, closeTo(400 - 1020 * 1.5, 1e-6));
      expect(t.offset.dy, closeTo(300 - 2015 * 1.5, 1e-6));
    });

    test('frames a large target with margin (zoom below comfortZoom)', () {
      final container = makeContainer();
      // A 4000x3000 target (e.g. a fan-out cone) can't fit at 1.5x — the
      // padded fit zoom (< comfortZoom) is used so the whole thing shows.
      container
          .read(viewportTransformProvider.notifier)
          .revealBounds(
            const Size(800, 600),
            const BoundingBox(x: 0, y: 0, width: 4000, height: 3000),
          );
      final t = container.read(viewportTransformProvider);
      // fitZoom = min(800/4000, 600/3000) * 0.6 = 0.2 * 0.6 = 0.12.
      expect(t.zoom, closeTo(0.12, 1e-9));
      expect(t.zoom, lessThan(1.5));
      // The whole target fits inside the viewport in both directions.
      expect(4000 * t.zoom, lessThanOrEqualTo(800));
      expect(3000 * t.zoom, lessThanOrEqualTo(600));
    });

    test('no-ops on a degenerate viewport or empty target', () {
      final container = makeContainer();
      container.read(viewportTransformProvider.notifier)
        ..revealBounds(
          Size.zero,
          const BoundingBox(x: 0, y: 0, width: 40, height: 30),
        )
        ..revealBounds(
          const Size(800, 600),
          const BoundingBox(x: 0, y: 0, width: 0, height: 0),
        );
      expect(
        container.read(viewportTransformProvider),
        ViewportTransform.identity,
      );
    });
  });

  group('handleViewportResize', () {
    const design = BoundingBox(x: 0, y: 0, width: 4000, height: 3000);

    test('re-fits a still-fitted view so a bigger pane shows a bigger '
        'design, not more empty space', () {
      final container = makeContainer();
      final notifier = container.read(viewportTransformProvider.notifier)
        ..fitToBounds(const Size(800, 600), design);
      final fittedZoom = container.read(viewportTransformProvider).zoom;

      notifier.handleViewportResize(
        const Size(800, 600),
        const Size(1600, 600),
      );
      final t = container.read(viewportTransformProvider);
      // Height still binds (3000 is the taller dimension relative to the
      // viewport), so the zoom is unchanged but the design re-centres in
      // the wider pane rather than staying pinned to the left.
      expect(t.zoom, closeTo(fittedZoom, 1e-9));
      expect(t.offset.dx, closeTo(800 - 2000 * t.zoom, 1e-6));

      // Growing both dimensions does scale the design up.
      notifier.handleViewportResize(
        const Size(1600, 600),
        const Size(1600, 1200),
      );
      expect(
        container.read(viewportTransformProvider).zoom,
        greaterThan(fittedZoom),
      );
    });

    test('keeps a hand-moved view at its own zoom and holds the centre', () {
      final container = makeContainer();
      final notifier = container.read(viewportTransformProvider.notifier)
        ..fitToBounds(const Size(800, 600), design)
        ..zoomAt(const Offset(400, 300), 4);
      final before = container.read(viewportTransformProvider);

      notifier.handleViewportResize(
        const Size(800, 600),
        const Size(1200, 900),
      );
      final after = container.read(viewportTransformProvider);

      // The user picked this scale; a resize must not overrule it.
      expect(after.zoom, before.zoom);
      // The design point under the old centre is under the new centre.
      Offset designAt(ViewportTransform t, Offset screen) =>
          (screen - t.offset) / t.zoom;
      expect(
        designAt(after, const Offset(600, 450)),
        _offsetCloseTo(designAt(before, const Offset(400, 300))),
      );
    });

    test('a pan un-fits the view — resizing after one must not snap back to '
        'the whole design', () {
      final container = makeContainer();
      final notifier = container.read(viewportTransformProvider.notifier)
        ..fitToBounds(const Size(800, 600), design);
      expect(notifier.isFitted, isTrue);
      notifier.pan(const Offset(50, 0));
      expect(notifier.isFitted, isFalse);

      final zoomBefore = container.read(viewportTransformProvider).zoom;
      notifier.handleViewportResize(const Size(800, 600), const Size(400, 300));
      expect(container.read(viewportTransformProvider).zoom, zoomBefore);
    });

    test(
      'a reveal un-fits the view so a resize keeps the revealed element',
      () {
        final container = makeContainer();
        final notifier = container.read(viewportTransformProvider.notifier)
          ..fitToBounds(const Size(800, 600), design)
          ..revealBounds(
            const Size(800, 600),
            const BoundingBox(x: 1000, y: 2000, width: 40, height: 30),
          );
        expect(notifier.isFitted, isFalse);
        final zoomBefore = container.read(viewportTransformProvider).zoom;
        notifier.handleViewportResize(
          const Size(800, 600),
          const Size(1600, 900),
        );
        expect(container.read(viewportTransformProvider).zoom, zoomBefore);
      },
    );

    test('no-ops on a degenerate or unchanged viewport', () {
      final container = makeContainer();
      final notifier = container.read(viewportTransformProvider.notifier)
        ..fitToBounds(const Size(800, 600), design);
      final before = container.read(viewportTransformProvider);

      notifier
        ..handleViewportResize(const Size(800, 600), Size.zero)
        ..handleViewportResize(const Size(800, 600), const Size(800, 600))
        // No previous viewport to preserve a centre against, and not fitted.
        ..pan(Offset.zero);
      final panned = container.read(viewportTransformProvider);
      notifier.handleViewportResize(Size.zero, const Size(800, 600));

      expect(container.read(viewportTransformProvider), panned);
      expect(before.zoom, panned.zoom);
    });
  });

  group('session camera restore', () {
    const saved = ViewportTransform(zoom: 1.25, offset: Offset(12.5, -8));

    test('a pending camera is taken once, for its own scope only', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(viewportTransformProvider.notifier)
        ..requestRestore(const <String>['u_cpu'], saved);
      expect(notifier.takePendingRestore(const <String>['u_cpu']), saved);
      expect(notifier.takePendingRestore(const <String>['u_cpu']), isNull);

      notifier.requestRestore(const <String>['u_cpu'], saved);
      expect(notifier.takePendingRestore(const <String>[]), isNull);
      expect(
        notifier.takePendingRestore(const <String>['u_cpu']),
        isNull,
        reason: 'a layout of another scope spends the request',
      );
    });

    test('restore sets the camera exactly and leaves it unfitted', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(viewportTransformProvider.notifier)
        ..fitToBounds(
          const Size(400, 300),
          const BoundingBox(x: 0, y: 0, width: 100, height: 100),
        )
        ..restore(saved);
      expect(container.read(viewportTransformProvider), saved);
      expect(notifier.isFitted, isFalse);
    });
  });

  group('camera in design space', () {
    const box = BoundingBox(x: 0, y: 0, width: 400, height: 200);
    const viewport = Size(800, 600);

    test('has no centre before the canvas reports a size', () {
      final notifier = makeContainer().read(viewportTransformProvider.notifier);
      expect(notifier.viewportSize, isNull);
      expect(notifier.designCenter, isNull);
      expect(notifier.transformCenteredOn(Offset.zero, 1), isNull);
    });

    test('centring on a design point and reading it back agree', () {
      final container = makeContainer();
      final notifier = container.read(viewportTransformProvider.notifier)
        ..fitToBounds(viewport, box);
      expect(notifier.viewportSize, viewport);
      final target = notifier.transformCenteredOn(const Offset(120, 40), 2);
      notifier.restore(target!);
      final centre = notifier.designCenter!;
      expect(centre.dx, closeTo(120, 1e-9));
      expect(centre.dy, closeTo(40, 1e-9));
      expect(container.read(viewportTransformProvider).zoom, 2);
    });

    test('the same design centre frames the same place in any window', () {
      // Two canvases of different sizes, one design point: each puts it at
      // its own centre, which is what a pixel offset could not do.
      final a = makeContainer().read(viewportTransformProvider.notifier)
        ..fitToBounds(const Size(800, 600), box);
      final b = makeContainer().read(viewportTransformProvider.notifier)
        ..fitToBounds(const Size(1600, 900), box);
      final ta = a.transformCenteredOn(const Offset(50, 50), 1.5)!;
      final tb = b.transformCenteredOn(const Offset(50, 50), 1.5)!;
      expect(const Offset(50, 50) * 1.5 + ta.offset, const Offset(400, 300));
      expect(const Offset(50, 50) * 1.5 + tb.offset, const Offset(800, 450));
    });
  });

  group('lastChangeWasGesture', () {
    test('pans and zooms are gestures; fits and restores are not', () {
      final container = makeContainer();
      final notifier = container.read(viewportTransformProvider.notifier);
      final seen = <bool>[];
      container.listen(
        viewportTransformProvider,
        (_, _) => seen.add(notifier.lastChangeWasGesture),
      );

      notifier
        ..fitToBounds(
          const Size(800, 600),
          const BoundingBox(x: 0, y: 0, width: 400, height: 200),
        )
        ..pan(const Offset(5, 5))
        ..zoomAt(Offset.zero, 2)
        ..setZoom(1)
        ..restore(ViewportTransform.identity)
        ..zoomAboutCenter(2)
        ..handleViewportResize(const Size(800, 600), const Size(900, 600))
        ..revealBounds(
          const Size(900, 600),
          const BoundingBox(x: 0, y: 0, width: 10, height: 10),
        )
        ..reset();

      expect(seen, [false, true, true, true, false, true, false, false, false]);
    });
  });
}

/// Matches an [Offset] within a pixel-ish tolerance, so the assertions above
/// read as geometry rather than as two float comparisons.
Matcher _offsetCloseTo(Offset expected, [double tolerance = 1e-6]) =>
    predicate<Offset>(
      (actual) =>
          (actual.dx - expected.dx).abs() < tolerance &&
          (actual.dy - expected.dy).abs() < tolerance,
      'within $tolerance of $expected',
    );
