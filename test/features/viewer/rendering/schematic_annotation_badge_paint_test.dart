// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/annotation_target.dart';
import 'package:netcrux/domain/models/schematic/laid_out_graph.dart';
import 'package:netcrux/features/viewer/rendering/annotation_badge_layout.dart';
import 'package:netcrux/features/viewer/rendering/schematic_painter.dart';
import 'package:netcrux/services/schematic/schematic_annotation_markers_provider.dart';

import 'annotation_badge_layout_test.dart' show badgeGraph, marker;

final ThemeData _theme = ThemeData.light();

/// Paints [graph] at [zoom] with [markers] and returns every recorded
/// canvas call.
List<RecordedInvocation> _paint(
  LaidOutGraph graph,
  SchematicAnnotationMarkers? markers, {
  double zoom = 1,
}) {
  final renderObject = SchematicCanvasRenderObject(
    laidOut: graph,
    transform: ViewportTransform(zoom: zoom, offset: Offset.zero),
    theme: _theme,
    statsSink: const NoopRenderStatsSink(),
    annotationMarkers: markers,
  )..layout(BoxConstraints.tight(const Size(800, 800)));
  final context = TestRecordingPaintingContext(TestRecordingCanvas());
  renderObject.paint(context, Offset.zero);
  return (context.canvas as TestRecordingCanvas).invocations;
}

/// Centres of the circles painted in the badge disc colour.
List<Offset> _badgeDiscs(List<RecordedInvocation> calls) {
  final fill = AnnotationBadgeColors.of(_theme).fill;
  return <Offset>[
    for (final call in calls)
      if (call.invocation.memberName == #drawCircle &&
          (call.invocation.positionalArguments[2] as Paint).color.toARGB32() ==
              fill.toARGB32() &&
          (call.invocation.positionalArguments[2] as Paint).style ==
              PaintingStyle.fill)
        call.invocation.positionalArguments[0] as Offset,
  ];
}

String _describe(List<RecordedInvocation> calls) => <String>[
  for (final call in calls)
    '${call.invocation.memberName} ${call.invocation.positionalArguments}',
].join('\n');

void main() {
  final cellOnly = SchematicAnnotationMarkers.from(<SchematicAnnotationMarker>[
    marker(AnnotationTargetKind.cell, 'u_and'),
  ]);

  test('an annotated cell gets one badge, an unannotated one none', () {
    final discs = _badgeDiscs(_paint(badgeGraph(), cellOnly));
    expect(discs, <Offset>[const Offset(100, 30)]);
  });

  test('badges paint in the detail and mid bands', () {
    expect(_badgeDiscs(_paint(badgeGraph(), cellOnly)), hasLength(1));
    expect(
      _badgeDiscs(_paint(badgeGraph(), cellOnly, zoom: 0.5)),
      hasLength(1),
    );
  });

  test('badges do not paint in the overview band', () {
    expect(_badgeDiscs(_paint(badgeGraph(), cellOnly, zoom: 0.1)), isEmpty);
  });

  test('an annotated pin and boundary port are badged beside themselves', () {
    final markers = SchematicAnnotationMarkers.from(<SchematicAnnotationMarker>[
      marker(AnnotationTargetKind.port, 'u_and:Y'),
      marker(AnnotationTargetKind.boundaryPort, 'port:y'),
    ]);
    expect(_badgeDiscs(_paint(badgeGraph(), markers)), <Offset>[
      const Offset(100, 58),
      const Offset(176, 30),
    ]);
  });

  test('net and scope annotations put no badge on the canvas', () {
    final markers = SchematicAnnotationMarkers.from(<SchematicAnnotationMarker>[
      marker(AnnotationTargetKind.net, 'e_4_0'),
      marker(AnnotationTargetKind.scope, 'top'),
    ]);
    expect(markers.isEmpty, isTrue);
    expect(_badgeDiscs(_paint(badgeGraph(), markers)), isEmpty);
  });

  test('with no annotations the canvas paints exactly as without the seam', () {
    // Ordinary rendering must not move: the same calls in the same order
    // with the seam unset, empty, or naming only elements not on screen.
    final without = _describe(_paint(badgeGraph(), null));
    expect(
      _describe(_paint(badgeGraph(), SchematicAnnotationMarkers.empty)),
      without,
    );
    expect(
      _describe(
        _paint(
          badgeGraph(),
          SchematicAnnotationMarkers.from(<SchematicAnnotationMarker>[
            marker(AnnotationTargetKind.cell, 'u_elsewhere'),
          ]),
        ),
      ),
      without,
    );
  });

  test('a badge adds draw calls only on top of the ordinary pass', () {
    final without = _paint(badgeGraph(), null);
    final with_ = _paint(badgeGraph(), cellOnly);
    // The ordinary pass is a prefix of the badged one: the badge paints
    // after everything else and changes nothing before it.
    expect(
      _describe(with_.sublist(0, without.length - 1)),
      _describe(without.sublist(0, without.length - 1)),
    );
    expect(with_.length, greaterThan(without.length));
  });
}
