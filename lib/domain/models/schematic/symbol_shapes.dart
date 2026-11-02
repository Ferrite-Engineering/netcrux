// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The one description of each built-in cell symbol, and of the marks the
// detail band draws around a cell (pin dots, tie stubs, name placement).
//
// Pure Dart with no `dart:ui`, so the canvas painters (`symbol_painters.dart`,
// `SchematicCanvas`) and the SVG exporter (`SvgExporter`) read the same
// numbers: a change to a shape here changes the canvas and the export
// together.

import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:netcrux/domain/models/layout/bounding_box.dart';
import 'package:netcrux/domain/models/schematic/cell_kind.dart';
import 'package:netcrux/domain/models/schematic/schematic_graph.dart';

/// How a [SymbolPrimitive] is drawn.
enum SymbolPrimitiveStyle {
  /// Filled with the body colour, then outlined with the stroke.
  filledOutline,

  /// Outlined with the stroke only.
  strokeOnly,
}

/// One drawn piece of a symbol, in the cell's local box: (0, 0) is the
/// top-left of the node and (width, height) its bottom-right.
@immutable
sealed class SymbolPrimitive {
  const SymbolPrimitive(this.style);

  /// Whether the piece is filled before it is outlined.
  final SymbolPrimitiveStyle style;
}

/// A path of [commands].
final class SymbolPath extends SymbolPrimitive {
  /// Creates a path piece.
  const SymbolPath(
    this.commands, {
    SymbolPrimitiveStyle style = SymbolPrimitiveStyle.filledOutline,
  }) : super(style);

  /// The path, in order.
  final List<SymbolPathCommand> commands;
}

/// A circle centred on ([cx], [cy]).
final class SymbolCircle extends SymbolPrimitive {
  /// Creates a circle piece.
  const SymbolCircle(
    this.cx,
    this.cy,
    this.radius, {
    SymbolPrimitiveStyle style = SymbolPrimitiveStyle.filledOutline,
  }) : super(style);

  /// Centre x.
  final double cx;

  /// Centre y.
  final double cy;

  /// Radius.
  final double radius;
}

/// An axis-aligned rectangle, its corners rounded by [cornerRadius] (zero
/// for square corners).
final class SymbolRect extends SymbolPrimitive {
  /// Creates a rectangle piece.
  const SymbolRect(
    this.left,
    this.top,
    this.right,
    this.bottom, {
    this.cornerRadius = 0,
    SymbolPrimitiveStyle style = SymbolPrimitiveStyle.filledOutline,
  }) : super(style);

  /// Left edge.
  final double left;

  /// Top edge.
  final double top;

  /// Right edge.
  final double right;

  /// Bottom edge.
  final double bottom;

  /// Corner radius; zero for a plain rectangle.
  final double cornerRadius;
}

/// One step of a [SymbolPath].
@immutable
sealed class SymbolPathCommand {
  const SymbolPathCommand();
}

/// Starts a subpath at ([x], [y]).
final class SymbolMoveTo extends SymbolPathCommand {
  /// Creates the step.
  const SymbolMoveTo(this.x, this.y);

  /// Target x.
  final double x;

  /// Target y.
  final double y;
}

/// A straight line to ([x], [y]).
final class SymbolLineTo extends SymbolPathCommand {
  /// Creates the step.
  const SymbolLineTo(this.x, this.y);

  /// Target x.
  final double x;

  /// Target y.
  final double y;
}

/// A clockwise, small circular arc of [radius] to ([x], [y]).
final class SymbolArcTo extends SymbolPathCommand {
  /// Creates the step.
  const SymbolArcTo(this.x, this.y, this.radius);

  /// Target x.
  final double x;

  /// Target y.
  final double y;

  /// Arc radius.
  final double radius;
}

/// A quadratic Bezier through control point ([cx], [cy]) to ([x], [y]).
final class SymbolQuadTo extends SymbolPathCommand {
  /// Creates the step.
  const SymbolQuadTo(this.cx, this.cy, this.x, this.y);

  /// Control point x.
  final double cx;

  /// Control point y.
  final double cy;

  /// Target x.
  final double x;

  /// Target y.
  final double y;
}

/// Closes the current subpath.
final class SymbolClose extends SymbolPathCommand {
  /// Creates the step.
  const SymbolClose();
}

/// Width of the outline every built-in symbol is stroked with.
const double symbolStrokeWidth = 1.4;

/// The pieces that draw a cell of [kind] in a [width] by [height] box, in
/// paint order.
///
/// With [clockAtPins], a flip-flop is drawn without the clock wedge at its
/// fixed place: the cell marks its clock pins, and [clockWedgeShapes] draws
/// a wedge at each of them, where the layout put it.
List<SymbolPrimitive> symbolShapeFor(
  CellKind kind,
  double width,
  double height, {
  bool clockAtPins = false,
}) => switch (kind) {
  CellKind.andGate => andGateShape(width, height),
  CellKind.orGate => orGateShape(width, height),
  CellKind.notGate => notGateShape(width, height),
  CellKind.mux => muxShape(width, height),
  CellKind.flipFlop =>
    clockAtPins
        ? flipFlopBodyShape(width, height)
        : flipFlopShape(width, height),
  CellKind.latch => latchShape(width, height),
  CellKind.generic => genericBoxShape(width, height),
  CellKind.buffer => bufferShape(width, height),
  CellKind.nandGate => nandGateShape(width, height),
  CellKind.norGate => norGateShape(width, height),
  CellKind.xorGate => xorGateShape(width, height),
  CellKind.xnorGate => xnorGateShape(width, height),
};

/// The AND body between [left] and [right]: flat back, rounded front.
SymbolPath _andBody(double left, double right, double top, double bottom) {
  final radius = (bottom - top) / 2;
  final flatRight = math.max(left, right - radius);
  return SymbolPath(<SymbolPathCommand>[
    SymbolMoveTo(left, top),
    SymbolLineTo(flatRight, top),
    SymbolArcTo(flatRight, bottom, radius),
    SymbolLineTo(left, bottom),
    const SymbolClose(),
  ]);
}

/// The OR body between [left] and [tip]: curved back, pointed front.
SymbolPath _orBody(double left, double tip, double top, double bottom) {
  final midY = (top + bottom) / 2;
  // Back: a concave curve from top-left to bottom-left. Top arc and
  // bottom arc meet at the gate tip (right midpoint).
  final controlX = left + (tip - left) * 0.55;
  return SymbolPath(<SymbolPathCommand>[
    SymbolMoveTo(left, top),
    // Concave back.
    SymbolQuadTo(left + (tip - left) * 0.2, midY, left, bottom),
    // Bottom curve toward the tip.
    SymbolQuadTo(controlX, bottom, tip, midY),
    // Top curve back to start.
    SymbolQuadTo(controlX, top, left, top),
    const SymbolClose(),
  ]);
}

/// The radius of the inversion bubble on a [width]-wide gate with [inset].
double _bubbleRadius(double width, double inset) => (width - 2 * inset) * 0.06;

/// ANSI/IEEE 91-style AND-gate body: flat back, rounded front-right. A
/// small inset keeps the body off the box's edges so the pin stubs look
/// like they touch the body.
List<SymbolPrimitive> andGateShape(double width, double height) {
  final inset = width * 0.06;
  return <SymbolPrimitive>[
    _andBody(inset, width - inset, inset, height - inset),
  ];
}

/// IEEE 91-style OR-gate body: curved back, pointed front.
List<SymbolPrimitive> orGateShape(double width, double height) {
  final inset = width * 0.06;
  return <SymbolPrimitive>[
    _orBody(inset, width - inset, inset, height - inset),
  ];
}

/// NAND: the AND body, shortened to leave room for a bubble on the output.
List<SymbolPrimitive> nandGateShape(double width, double height) {
  final inset = width * 0.06;
  final bubble = _bubbleRadius(width, inset);
  final bodyRight = width - inset - 2 * bubble;
  return <SymbolPrimitive>[
    _andBody(inset, bodyRight, inset, height - inset),
    SymbolCircle(bodyRight + bubble, height / 2, bubble),
  ];
}

/// NOR: the OR body, shortened to leave room for a bubble on the output.
List<SymbolPrimitive> norGateShape(double width, double height) {
  final inset = width * 0.06;
  final bubble = _bubbleRadius(width, inset);
  final tip = width - inset - 2 * bubble;
  return <SymbolPrimitive>[
    _orBody(inset, tip, inset, height - inset),
    SymbolCircle(tip + bubble, height / 2, bubble),
  ];
}

/// The second curve behind an XOR body, at [left], drawn as a stroke.
SymbolPath _xorBack(double left, double width, double top, double bottom) {
  final midY = (top + bottom) / 2;
  return SymbolPath(<SymbolPathCommand>[
    SymbolMoveTo(left, top),
    SymbolQuadTo(left + width * 0.2, midY, left, bottom),
  ], style: SymbolPrimitiveStyle.strokeOnly);
}

/// XOR: the OR body moved right, with a second curve behind its back.
List<SymbolPrimitive> xorGateShape(double width, double height) {
  final inset = width * 0.06;
  final right = width - inset;
  final gap = (right - inset) * 0.1;
  final top = inset;
  final bottom = height - inset;
  return <SymbolPrimitive>[
    _orBody(inset + gap, right, top, bottom),
    _xorBack(inset, right - inset - gap, top, bottom),
  ];
}

/// XNOR: the XOR body, shortened to leave room for a bubble on the output.
List<SymbolPrimitive> xnorGateShape(double width, double height) {
  final inset = width * 0.06;
  final bubble = _bubbleRadius(width, inset);
  final tip = width - inset - 2 * bubble;
  final gap = (width - 2 * inset) * 0.1;
  final top = inset;
  final bottom = height - inset;
  return <SymbolPrimitive>[
    _orBody(inset + gap, tip, top, bottom),
    _xorBack(inset, tip - inset - gap, top, bottom),
    SymbolCircle(tip + bubble, height / 2, bubble),
  ];
}

/// Buffer: the inverter's triangle without the bubble, its point on the
/// output.
List<SymbolPrimitive> bufferShape(double width, double height) {
  final inset = width * 0.06;
  final top = inset;
  final bottom = height - inset;
  return <SymbolPrimitive>[
    SymbolPath(<SymbolPathCommand>[
      SymbolMoveTo(inset, top),
      SymbolLineTo(width - inset, (top + bottom) / 2),
      SymbolLineTo(inset, bottom),
      const SymbolClose(),
    ]),
  ];
}

/// Inverter: triangle with a bubble on the front.
List<SymbolPrimitive> notGateShape(double width, double height) {
  final inset = width * 0.06;
  final left = inset;
  final right = width - inset;
  final top = inset;
  final bottom = height - inset;
  final midY = (top + bottom) / 2;
  final bubbleRadius = (width - 2 * inset) * 0.06;
  final triangleRight = right - 2 * bubbleRadius;
  return <SymbolPrimitive>[
    SymbolPath(<SymbolPathCommand>[
      SymbolMoveTo(left, top),
      SymbolLineTo(triangleRight, midY),
      SymbolLineTo(left, bottom),
      const SymbolClose(),
    ]),
    SymbolCircle(triangleRight + bubbleRadius, midY, bubbleRadius),
  ];
}

/// Mux: trapezoid, wider on the left (input side) than the right.
List<SymbolPrimitive> muxShape(double width, double height) {
  final inset = width * 0.06;
  final left = inset;
  final right = width - inset;
  final top = inset;
  final bottom = height - inset;
  final shrink = (bottom - top) * 0.18;
  return <SymbolPrimitive>[
    SymbolPath(<SymbolPathCommand>[
      SymbolMoveTo(left, top),
      SymbolLineTo(right, top + shrink),
      SymbolLineTo(right, bottom - shrink),
      SymbolLineTo(left, bottom),
      const SymbolClose(),
    ]),
  ];
}

/// Flip-flop: rounded rectangle with a clock triangle on the left side,
/// pointing inward near the bottom.
List<SymbolPrimitive> flipFlopShape(double width, double height) {
  final inset = width * 0.06;
  final clockY = height * 0.78;
  final triangleSize = height * 0.07;
  return <SymbolPrimitive>[
    SymbolRect(inset, inset, width - inset, height - inset, cornerRadius: 4),
    SymbolPath(<SymbolPathCommand>[
      SymbolMoveTo(inset, clockY - triangleSize),
      SymbolLineTo(inset + triangleSize * 1.4, clockY),
      SymbolLineTo(inset, clockY + triangleSize),
      const SymbolClose(),
    ], style: SymbolPrimitiveStyle.strokeOnly),
  ];
}

/// A flip-flop's rounded rectangle alone, for a cell whose clock pins are
/// marked one by one ([clockWedgeShapes]).
List<SymbolPrimitive> flipFlopBodyShape(double width, double height) {
  final inset = width * 0.06;
  return <SymbolPrimitive>[
    SymbolRect(inset, inset, width - inset, height - inset, cornerRadius: 4),
  ];
}

/// The clock wedge of each clock pin of [cell] on the west face of its
/// [width] by [height] node, at the pin's laid-out place: [pinBoxes] maps a
/// pin id to its box relative to the node. A clock pin the layout put on
/// another face, or did not place, gets no wedge. Empty for a cell with no
/// clock pins, so a cell whose kind draws a fixed wedge keeps that one.
List<SymbolPrimitive> clockWedgeShapes(
  SchematicCell cell,
  double width,
  double height,
  Map<String, BoundingBox> pinBoxes,
) {
  if (!cell.hasClockPins) return const <SymbolPrimitive>[];
  final inset = width * 0.06;
  final size = math.min(height * 0.07, 4).toDouble();
  return <SymbolPrimitive>[
    for (final port in cell.ports)
      if (port.clock)
        if (pinBoxes[port.id] case final box?)
          if (symbolPinFace(box, width, height) == SchematicPortSide.west)
            SymbolPath(<SymbolPathCommand>[
              SymbolMoveTo(inset, box.y + box.height / 2 - size),
              SymbolLineTo(inset + size * 1.4, box.y + box.height / 2),
              SymbolLineTo(inset, box.y + box.height / 2 + size),
              const SymbolClose(),
            ], style: SymbolPrimitiveStyle.strokeOnly),
  ];
}

/// Latch: rounded rectangle like a flip-flop's, without the clock triangle,
/// and a small bar on the left edge at mid-height marking the level-sensitive
/// enable.
List<SymbolPrimitive> latchShape(double width, double height) {
  final inset = width * 0.06;
  final midY = height / 2;
  final barWidth = math.min(width * 0.15, 12).toDouble();
  return <SymbolPrimitive>[
    SymbolRect(inset, inset, width - inset, height - inset, cornerRadius: 2),
    SymbolPath(<SymbolPathCommand>[
      SymbolMoveTo(inset, midY - 3),
      SymbolLineTo(inset + barWidth, midY - 3),
      SymbolLineTo(inset + barWidth, midY + 3),
      SymbolLineTo(inset, midY + 3),
      const SymbolClose(),
    ], style: SymbolPrimitiveStyle.strokeOnly),
  ];
}

/// Generic catch-all: a plain rectangle. The cell's label goes on top.
List<SymbolPrimitive> genericBoxShape(double width, double height) {
  final inset = width * 0.06;
  return <SymbolPrimitive>[
    SymbolRect(inset, inset, width - inset, height - inset),
  ];
}

/// The marks the detail band draws around a cell besides its body, shared
/// by the canvas and the SVG export.
abstract final class SchematicDetailMarks {
  /// Radius of the dot on every cell pin.
  static const double pinDotRadius = 2.5;

  /// Radius of the dot on a selected cell pin.
  static const double selectedPinDotRadius = 3.5;

  /// Length of the stub drawn out of a constant-tied or undriven pin. Short
  /// enough to stay inside the gap the layout leaves between layers.
  static const double tieStubLength = 9;

  /// Stroke width of a constant pin's stub.
  static const double constantStubWidth = 1.2;

  /// Stroke width of an undriven pin's stub and ring.
  static const double undrivenStubWidth = 1.6;

  /// Radius of the open ring that ends an undriven pin's stub.
  static const double undrivenRingRadius = 2;

  /// Font size of the value beside a constant pin's stub.
  static const double tieLabelFontSize = 8;

  /// Gap between a constant pin's stub and its value.
  static const double tieLabelGap = 1;

  /// Gap between a module port and its name.
  static const double boundaryLabelGap = 4;

  /// Inset of a pin name from the edge of a custom symbol's drawing.
  static const double pinNameInset = 3;

  /// The widest an outside label may be, in layout units, when its cell is
  /// narrower: a symbol node can be small, and the name should stay legible.
  static const double outsideLabelMinWidth = 120;

  /// Gap between a symbol cell's drawing and its outside label.
  static const double outsideLabelGap = 2;
}

/// Which way the tie stub of the pin at [box] (relative to a node
/// [nodeWidth] wide) leaves the cell: `-1` leftwards from a pin on the west
/// half, `1` rightwards from one on the east.
double tieStubOutward(BoundingBox box, double nodeWidth) =>
    box.x + box.width / 2 < nodeWidth / 2 ? -1.0 : 1.0;

/// The face of a symbol node that a pin [box] (relative to the node, of
/// [width] by [height]) sits on: the layout puts west pins wholly left of
/// the node, east pins at its right edge, north pins above it and south
/// pins at its bottom edge.
SchematicPortSide symbolPinFace(BoundingBox box, double width, double height) {
  const slop = 0.5;
  if (box.x + box.width <= slop) return SchematicPortSide.west;
  if (box.x >= width - slop) return SchematicPortSide.east;
  if (box.y + box.height <= slop) return SchematicPortSide.north;
  return SchematicPortSide.south;
}

/// Where the outside label of a cell at [cell] goes, for a label [width] by
/// [height]: centred under the cell, [SchematicDetailMarks.outsideLabelGap]
/// below it, when [isFree] says that space is clear; otherwise the same
/// distance above when that is clear; otherwise below regardless. Never
/// inside [cell].
BoundingBox outsideLabelBox(
  BoundingBox cell,
  double width,
  double height, {
  required bool Function(BoundingBox candidate) isFree,
}) {
  final left = cell.x + cell.width / 2 - width / 2;
  final below = BoundingBox(
    x: left,
    y: cell.bottom + SchematicDetailMarks.outsideLabelGap,
    width: width,
    height: height,
  );
  if (isFree(below)) return below;
  final above = BoundingBox(
    x: left,
    y: cell.y - SchematicDetailMarks.outsideLabelGap - height,
    width: width,
    height: height,
  );
  return isFree(above) ? above : below;
}
