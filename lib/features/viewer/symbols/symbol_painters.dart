// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:netcrux/domain/models/schematic/cell_kind.dart';

/// Paint configuration handed to every symbol painter. Keeps the
/// painters themselves stateless so they're easy to unit-test
/// against golden images.
@immutable
class SymbolPaintContext {
  /// Creates a paint context.
  const SymbolPaintContext({
    required this.body,
    required this.stroke,
    required this.accent,
    this.isSelected = false,
    this.isHovered = false,
  });

  /// Defaults derived from a Material 3 [ThemeData]. The waveform
  /// renderer composes this once per paint and reuses for every cell.
  factory SymbolPaintContext.fromTheme(ThemeData theme) {
    final scheme = theme.colorScheme;
    return SymbolPaintContext(
      body: Paint()..color = scheme.surfaceContainerHighest,
      stroke: Paint()
        ..color = scheme.onSurface
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
      accent: Paint()
        ..color = scheme.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
  }

  /// Solid body fill — drawn behind the outline.
  final Paint body;

  /// Outline of the symbol's body.
  final Paint stroke;

  /// Accent stroke used for selection / hover overlays. Symbol
  /// painters draw the body in [stroke]; the renderer wraps a
  /// selected cell with an outline in [accent].
  final Paint accent;

  /// Selection flag — symbols may swap their outline for [accent]
  /// when set. Wired by the renderer once selection lands.
  final bool isSelected;

  /// Hover flag — distinct from selection; both can be true.
  final bool isHovered;
}

/// Signature for a symbol painter.
///
/// Symbol painters draw the *body* of a cell — the outline that
/// communicates the cell's role at a glance. They paint into a
/// canvas already translated/scaled into the cell's local box; the
/// (0, 0) origin is the top-left of the body rectangle and (size.width,
/// size.height) is the bottom-right.
///
/// Pin stubs, labels, and selection overlays are layered on top by
/// the renderer.
typedef SymbolPainter =
    void Function(
      Canvas canvas,
      Size size,
      SymbolPaintContext ctx,
    );

/// Returns the painter for [kind]. Stable map so the renderer can
/// dispatch per cell with a single lookup.
SymbolPainter painterFor(CellKind kind) {
  switch (kind) {
    case CellKind.andGate:
      return paintAndGate;
    case CellKind.orGate:
      return paintOrGate;
    case CellKind.notGate:
      return paintNotGate;
    case CellKind.mux:
      return paintMux;
    case CellKind.flipFlop:
      return paintFlipFlop;
    case CellKind.latch:
      return paintLatch;
    case CellKind.generic:
      return paintGenericBox;
  }
}

void _drawFilledOutline(Canvas canvas, Path path, SymbolPaintContext ctx) {
  canvas
    ..drawPath(path, ctx.body)
    ..drawPath(path, ctx.stroke);
}

/// Standard ANSI/IEEE 91-style AND-gate body: flat back, rounded
/// front-right, drawn inside `[0, 0, size.width, size.height]`. A
/// small inset keeps the body off the rectangle's edges so the pin
/// stubs the renderer overlays look like they touch the body.
void paintAndGate(Canvas canvas, Size size, SymbolPaintContext ctx) {
  final inset = size.width * 0.06;
  final left = inset;
  final right = size.width - inset;
  final top = inset;
  final bottom = size.height - inset;
  final radius = (bottom - top) / 2;
  final flatRight = right - radius;
  final path = Path()
    ..moveTo(left, top)
    ..lineTo(flatRight, top)
    ..arcToPoint(
      Offset(flatRight, bottom),
      radius: Radius.circular(radius),
    )
    ..lineTo(left, bottom)
    ..close();
  _drawFilledOutline(canvas, path, ctx);
}

/// IEEE 91-style OR-gate body: curved back, pointed front.
void paintOrGate(Canvas canvas, Size size, SymbolPaintContext ctx) {
  final inset = size.width * 0.06;
  final left = inset;
  final right = size.width - inset;
  final top = inset;
  final bottom = size.height - inset;
  final midY = (top + bottom) / 2;
  final tip = right;
  // Back: a concave curve from top-left to bottom-left. Top arc and
  // bottom arc meet at the gate tip (right midpoint).
  final controlX = left + (right - left) * 0.55;
  final path = Path()
    ..moveTo(left, top)
    // Concave back.
    ..quadraticBezierTo(left + (right - left) * 0.2, midY, left, bottom)
    // Bottom curve toward the tip.
    ..quadraticBezierTo(controlX, bottom, tip, midY)
    // Top curve back to start.
    ..quadraticBezierTo(controlX, top, left, top)
    ..close();
  _drawFilledOutline(canvas, path, ctx);
}

/// Inverter: triangle with a bubble on the front. Pins on left and
/// right edges of the bounding box.
void paintNotGate(Canvas canvas, Size size, SymbolPaintContext ctx) {
  final inset = size.width * 0.06;
  final left = inset;
  final right = size.width - inset;
  final top = inset;
  final bottom = size.height - inset;
  final midY = (top + bottom) / 2;
  final bubbleRadius = (size.width - 2 * inset) * 0.06;
  final triangleRight = right - 2 * bubbleRadius;
  final triangle = Path()
    ..moveTo(left, top)
    ..lineTo(triangleRight, midY)
    ..lineTo(left, bottom)
    ..close();
  _drawFilledOutline(canvas, triangle, ctx);
  final bubbleCenter = Offset(triangleRight + bubbleRadius, midY);
  canvas
    ..drawCircle(bubbleCenter, bubbleRadius, ctx.body)
    ..drawCircle(bubbleCenter, bubbleRadius, ctx.stroke);
}

/// Mux: trapezoid, wider on the left (input side) than the right.
void paintMux(Canvas canvas, Size size, SymbolPaintContext ctx) {
  final inset = size.width * 0.06;
  final left = inset;
  final right = size.width - inset;
  final top = inset;
  final bottom = size.height - inset;
  final shrink = (bottom - top) * 0.18;
  final path = Path()
    ..moveTo(left, top)
    ..lineTo(right, top + shrink)
    ..lineTo(right, bottom - shrink)
    ..lineTo(left, bottom)
    ..close();
  _drawFilledOutline(canvas, path, ctx);
}

/// Flip-flop: rounded rectangle with a CLK triangle on the left side
/// (drawn pointing inward, near the bottom).
void paintFlipFlop(Canvas canvas, Size size, SymbolPaintContext ctx) {
  final inset = size.width * 0.06;
  final rect = RRect.fromRectAndRadius(
    Rect.fromLTRB(
      inset,
      inset,
      size.width - inset,
      size.height - inset,
    ),
    const Radius.circular(4),
  );
  canvas
    ..drawRRect(rect, ctx.body)
    ..drawRRect(rect, ctx.stroke);
  // Clock arrow — small inward triangle near the bottom-left.
  final clockY = size.height * 0.78;
  final triangleSize = size.height * 0.07;
  final clockArrow = Path()
    ..moveTo(inset, clockY - triangleSize)
    ..lineTo(inset + triangleSize * 1.4, clockY)
    ..lineTo(inset, clockY + triangleSize)
    ..close();
  canvas.drawPath(clockArrow, ctx.stroke);
}

/// Latch: rounded rectangle similar to a flip-flop but without the
/// edge-triangle clock arrow. Indicates level-sensitive enable.
void paintLatch(Canvas canvas, Size size, SymbolPaintContext ctx) {
  final inset = size.width * 0.06;
  final rect = RRect.fromRectAndRadius(
    Rect.fromLTRB(
      inset,
      inset,
      size.width - inset,
      size.height - inset,
    ),
    const Radius.circular(2),
  );
  canvas
    ..drawRRect(rect, ctx.body)
    ..drawRRect(rect, ctx.stroke);
  // Level-sensitive marker — a small horizontal bar on the left edge
  // mid-height, distinguishing the symbol from a flip-flop at a
  // glance even before the user reads the type label.
  final midY = size.height / 2;
  final barWidth = math.min(size.width * 0.15, 12);
  final bar = Path()
    ..moveTo(inset, midY - 3)
    ..lineTo(inset + barWidth, midY - 3)
    ..lineTo(inset + barWidth, midY + 3)
    ..lineTo(inset, midY + 3)
    ..close();
  canvas.drawPath(bar, ctx.stroke);
}

/// Generic catch-all: simple labeled rectangle. The renderer paints
/// the cell's display label on top.
void paintGenericBox(Canvas canvas, Size size, SymbolPaintContext ctx) {
  final inset = size.width * 0.06;
  final rect = Rect.fromLTRB(
    inset,
    inset,
    size.width - inset,
    size.height - inset,
  );
  canvas
    ..drawRect(rect, ctx.body)
    ..drawRect(rect, ctx.stroke);
}
