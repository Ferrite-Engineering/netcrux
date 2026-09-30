// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/schematic/laid_out_graph.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/features/viewer/rendering/schematic_painter.dart';
import 'package:netcrux/features/viewer/rendering/schematic_scene_index.dart';
import 'package:netcrux/features/viewer/selection/schematic_hit_test.dart';
import 'package:netcrux/features/viewer/selection/schematic_keyboard_navigator.dart';

import '../../helpers/flattened_scope.dart';
import 'scene_reference.dart';

/// The scene index changes how the canvas finds elements, never which ones
/// it finds. Each test runs the index-backed code and the full scan it
/// replaced ([referenceHitTest] and friends, kept verbatim) side by side
/// and requires identical answers — on random scenes built to contain the
/// geometry an index gets wrong (NaN and infinite boxes, inverted and
/// zero-size rectangles, far outliers, wires with no or one point, clicks
/// exactly on half-open rectangle edges and at the slop boundary), and on
/// a real design.
void main() {
  const transforms = <ViewportTransform>[
    ViewportTransform.identity,
    ViewportTransform(zoom: 0.37, offset: Offset(210, -35)),
    ViewportTransform(zoom: 2.5, offset: Offset(-900, 400)),
    ViewportTransform(zoom: 0.01, offset: Offset(3, 7)),
    ViewportTransform(zoom: 10, offset: Offset(-5000, -2000)),
  ];

  test('hit-test answers exactly as the full scan did, on random scenes', () {
    final rng = Random(20260921);
    var clicks = 0;
    final kinds = <Type, int>{};
    for (var s = 0; s < 400; s++) {
      final laidOut = randomScene(rng);
      for (var c = 0; c < 60; c++) {
        final transform = transforms[rng.nextInt(transforms.length)];
        final slop = <double>[6, 0, 12.5][rng.nextInt(3)];
        final design = randomClick(rng, laidOut);
        final viewport = design * transform.zoom + transform.offset;
        final expected = referenceHitTest(
          laidOut,
          transform,
          viewport,
          wireSlop: slop,
        );
        final actual = SchematicHitTester(
          laidOut: laidOut,
          transform: transform,
          wireSlop: slop,
        ).hitTest(viewport);
        expect(
          actual,
          expected,
          reason: 'scene $s click $c at $design ($transform, slop $slop)',
        );
        kinds[expected.runtimeType] = (kinds[expected.runtimeType] ?? 0) + 1;
        clicks++;
      }
    }
    // The comparison proves something only if every kind of answer came up
    // often.
    expect(clicks, 24000);
    for (final kind in <Type>[
      SelectedElementPort,
      SelectedElementCell,
      SelectedElementBoundaryPort,
      SelectedElementWire,
      SelectedElementNone,
    ]) {
      expect(kinds[kind] ?? 0, greaterThan(300), reason: '$kind: $kinds');
    }
  });

  test('hit-test answers exactly as the full scan did, on picorv32', () {
    final laidOut = laidOutFixture(
      'test/fixtures/netlist/picorv32/captured/picorv32.netlist.json.gz',
    );
    final rng = Random(7);
    final bounds = laidOut.layout.bounds;
    var hits = 0;
    for (var c = 0; c < 4000; c++) {
      final design = c.isEven
          ? randomClick(rng, laidOut)
          : Offset(
              bounds.x + rng.nextDouble() * bounds.width,
              bounds.y + rng.nextDouble() * bounds.height,
            );
      final expected = referenceHitTest(
        laidOut,
        ViewportTransform.identity,
        design,
      );
      expect(
        SchematicHitTester(
          laidOut: laidOut,
          transform: ViewportTransform.identity,
        ).hitTest(design),
        expected,
        reason: 'click $c at $design',
      );
      if (expected is! SelectedElementNone) hits++;
    }
    expect(hits, greaterThan(1000));
  });

  test('the cull keeps exactly the cells and wires the full scan kept, on '
      'random scenes', () {
    final rng = Random(31);
    for (var s = 0; s < 400; s++) {
      final laidOut = randomScene(rng);
      final scene = SchematicSceneIndex.of(laidOut);
      for (var v = 0; v < 12; v++) {
        final Rect visible;
        switch (rng.nextInt(8)) {
          case 0:
            visible = Rect.largest; // culling disabled
          case 1:
            visible = const Rect.fromLTRB(5000, 5000, 6000, 6000); // off scene
          default:
            final left = -600 + rng.nextDouble() * 2400;
            final top = -600 + rng.nextDouble() * 2400;
            final extent = <double>[0, 1, 40, 300, 1500][rng.nextInt(5)];
            visible = Rect.fromLTWH(left, top, extent, extent * 0.75);
        }
        // What the painter's loops do: the index's candidates, then the cull
        // test on each.
        var cells = 0;
        final cellCandidates = scene.cellsIn(visible);
        for (
          var k = 0;
          k < (cellCandidates?.length ?? scene.cells.length);
          k++
        ) {
          final i = cellCandidates == null ? k : cellCandidates[k];
          final b = scene.cellNodes[i].bounds;
          if (visible.overlaps(Rect.fromLTWH(b.x, b.y, b.width, b.height))) {
            cells++;
          }
        }
        var wires = 0;
        final wireCandidates = scene.wiresIn(visible);
        for (
          var k = 0;
          k < (wireCandidates?.length ?? scene.wires.length);
          k++
        ) {
          final i = wireCandidates == null ? k : wireCandidates[k];
          if (visible.overlaps(scene.wireBounds(i))) wires++;
        }
        expect(
          (cells: cells, wires: wires),
          referenceCull(laidOut, visible),
          reason: 'scene $s view $visible',
        );
      }
    }
  });

  testWidgets('the painter draws exactly the cells and wires the full-scan '
      'cull drew', (tester) async {
    final rng = Random(99);
    final scenes = <LaidOutGraph>[
      for (var s = 0; s < 40; s++) randomScene(rng, wellFormed: true),
      laidOutFixture(
        'test/fixtures/netlist/picorv32/captured/picorv32.netlist.json.gz',
      ),
    ];
    for (var s = 0; s < scenes.length; s++) {
      final laidOut = scenes[s];
      for (var v = 0; v < 6; v++) {
        final zoom = <double>[1, 0.4, 0.05, 3][rng.nextInt(4)];
        final transform = ViewportTransform(
          zoom: zoom,
          offset: Offset(
            (rng.nextDouble() - 0.3) * -1800 * zoom,
            (rng.nextDouble() - 0.3) * -1800 * zoom,
          ),
        );
        final sink = RecordingRenderStatsSink();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 640,
                  height: 480,
                  child: SchematicCanvas(
                    laidOut: laidOut,
                    transform: transform,
                    statsSink: sink,
                    theme: ThemeData.light(useMaterial3: true),
                  ),
                ),
              ),
            ),
          ),
        );
        // The painter's visible rect: the viewport inverted into design
        // space, inflated by its 96-unit cull margin.
        final visible = Rect.fromLTRB(
          -transform.offset.dx / zoom,
          -transform.offset.dy / zoom,
          (640 - transform.offset.dx) / zoom,
          (480 - transform.offset.dy) / zoom,
        ).inflate(96);
        // An empty scope paints nothing at all, before any culling.
        final expected = laidOut.isEmpty
            ? (cells: 0, wires: 0)
            : referenceCull(laidOut, visible);
        final stats = sink.last!;
        expect(
          (cells: stats.visibleCells, wires: stats.visibleEdges),
          expected,
          reason: 'scene $s view $v ($transform)',
        );
      }
    }
  });

  test('keyboard navigation answers exactly as the full scan did', () {
    final rng = Random(5);
    for (var s = 0; s < 300; s++) {
      final laidOut = randomScene(rng);
      final navigator = SchematicKeyboardNavigator(laidOut);
      final order = referenceReadingOrder(laidOut);
      expect(navigator.elements, order, reason: 'scene $s reading order');
      // Every placed element and a few that are not, as the step origin.
      final origins = <SelectedElement>[
        ...order,
        const SelectedElement.none(),
        const SelectedElement.cell(cellId: 'absent'),
        for (final edge in laidOut.graph.edges)
          SelectedElement.wire(edgeId: edge.id, netId: edge.netId),
      ];
      for (final origin in origins) {
        for (final forward in <bool>[true, false]) {
          final list = order;
          final anchor = switch (origin) {
            SelectedElementWire(:final edgeId) => referenceDriverOf(
              laidOut,
              edgeId,
            ),
            _ => origin,
          };
          final at = list.indexOf(anchor);
          final expected = list.isEmpty
              ? const SelectedElement.none()
              : at == -1
              ? (forward ? list.first : list.last)
              : list[(at + (forward ? 1 : -1)) % list.length];
          expect(
            navigator.stepElement(origin, forward: forward),
            expected,
            reason: 'scene $s step from $origin',
          );
        }
        final anchor = navigator.anchorFor(origin);
        expect(
          navigator.connectionsOf(anchor),
          referenceConnectionsOf(laidOut, anchor),
          reason: 'scene $s connections of $anchor',
        );
      }
    }
  });
}
