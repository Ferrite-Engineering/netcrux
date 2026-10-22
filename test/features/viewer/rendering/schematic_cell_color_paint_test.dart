// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/schematic/laid_out_graph.dart';
import 'package:netcrux/features/viewer/rendering/schematic_painter.dart';

import 'annotation_badge_layout_test.dart' show badgeGraph;

final ThemeData _theme = ThemeData.light();

const Color _red = Color(0xFFC62828);

/// Paints [graph] at [zoom] with [colors] and returns every recorded canvas
/// call.
List<RecordedInvocation> _paint(
  LaidOutGraph graph,
  Map<String, Color>? colors, {
  double zoom = 1,
}) {
  final renderObject = SchematicCanvasRenderObject(
    laidOut: graph,
    transform: ViewportTransform(zoom: zoom, offset: Offset.zero),
    theme: _theme,
    statsSink: const NoopRenderStatsSink(),
    cellColorOverride: colors,
  )..layout(BoxConstraints.tight(const Size(800, 800)));
  final context = TestRecordingPaintingContext(TestRecordingCanvas());
  renderObject.paint(context, Offset.zero);
  return (context.canvas as TestRecordingCanvas).invocations;
}

/// The rectangles painted with [style] in a color of [rgb] (alpha ignored).
List<Rect> _rects(
  List<RecordedInvocation> calls,
  PaintingStyle style,
  Color rgb,
) {
  final want = rgb.toARGB32() & 0xFFFFFF;
  return <Rect>[
    for (final call in calls)
      if (call.invocation.memberName == #drawRect &&
          (call.invocation.positionalArguments[1] as Paint).style == style &&
          ((call.invocation.positionalArguments[1] as Paint).color.toARGB32() &
                  0xFFFFFF) ==
              want)
        call.invocation.positionalArguments[0] as Rect,
  ];
}

String _describe(List<RecordedInvocation> calls) => <String>[
  for (final call in calls)
    '${call.invocation.memberName} ${call.invocation.positionalArguments}',
].join('\n');

void main() {
  test('a named cell is filled and outlined, in two marks', () {
    final calls = _paint(badgeGraph(), <String, Color>{'u_and': _red});
    // The cell box is (20, 30) 80 x 60.
    expect(_rects(calls, PaintingStyle.fill, _red), <Rect>[
      const Rect.fromLTWH(20, 30, 80, 60),
    ]);
    expect(_rects(calls, PaintingStyle.stroke, _red), <Rect>[
      const Rect.fromLTWH(20, 30, 80, 60).inflate(1.5),
    ]);
  });

  test('the fill is translucent and the outline opaque', () {
    final calls = _paint(badgeGraph(), <String, Color>{'u_and': _red});
    final fill = calls.firstWhere(
      (c) =>
          c.invocation.memberName == #drawRect &&
          (c.invocation.positionalArguments[1] as Paint).style ==
              PaintingStyle.fill &&
          ((c.invocation.positionalArguments[1] as Paint).color.toARGB32() &
                  0xFFFFFF) ==
              (_red.toARGB32() & 0xFFFFFF),
    );
    expect(
      (fill.invocation.positionalArguments[1] as Paint).color.a,
      lessThan(1),
    );
  });

  test('every band draws it, the overview band included', () {
    for (final zoom in <double>[1, 0.5, 0.1]) {
      final calls = _paint(badgeGraph(), <String, Color>{
        'u_and': _red,
      }, zoom: zoom);
      expect(
        _rects(calls, PaintingStyle.fill, _red),
        hasLength(1),
        reason: 'zoom $zoom',
      );
    }
  });

  test('two cells each get their own colors', () {
    const blue = Color(0xFF3D6BF0);
    final calls = _paint(badgeGraph(), <String, Color>{
      'u_and': _red,
      'u_or': blue,
    });
    expect(_rects(calls, PaintingStyle.fill, _red), hasLength(1));
    expect(_rects(calls, PaintingStyle.fill, blue), hasLength(1));
  });

  test('with no map the canvas paints exactly as without the seam', () {
    // Ordinary rendering must not move: the same calls in the same order with
    // the seam unset, empty, or naming only cells that are not on screen.
    final without = _describe(_paint(badgeGraph(), null));
    expect(_describe(_paint(badgeGraph(), <String, Color>{})), without);
    expect(
      _describe(_paint(badgeGraph(), <String, Color>{'u_elsewhere': _red})),
      without,
    );
  });

  test('the pass adds draw calls only on top of the ordinary pass', () {
    final without = _paint(badgeGraph(), null);
    final withColors = _paint(badgeGraph(), <String, Color>{'u_and': _red});
    // The cells, wires and boundary ports come first and are unchanged.
    expect(
      _describe(withColors.sublist(0, without.length - 1)),
      _describe(without.sublist(0, without.length - 1)),
    );
    expect(withColors.length, greaterThan(without.length));
  });
}
