// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:netcrux/domain/models/schematic/cell_kind.dart';
import 'package:netcrux/domain/models/schematic/symbol_shapes.dart';

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
        ..strokeWidth = symbolStrokeWidth,
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

/// Draws [shape], pieces in order, into [canvas] already translated into
/// the cell's local box. The one painter behind every built-in symbol; the
/// SVG export writes the same pieces (see `symbol_shapes.dart`).
void paintSymbolShape(
  Canvas canvas,
  List<SymbolPrimitive> shape,
  SymbolPaintContext ctx,
) {
  for (final piece in shape) {
    final filled = piece.style == SymbolPrimitiveStyle.filledOutline;
    switch (piece) {
      case SymbolPath(:final commands):
        final path = _pathOf(commands);
        if (filled) canvas.drawPath(path, ctx.body);
        canvas.drawPath(path, ctx.stroke);
      case SymbolCircle(:final cx, :final cy, :final radius):
        final centre = Offset(cx, cy);
        if (filled) canvas.drawCircle(centre, radius, ctx.body);
        canvas.drawCircle(centre, radius, ctx.stroke);
      case SymbolRect(
        :final left,
        :final top,
        :final right,
        :final bottom,
        :final cornerRadius,
      ):
        final rect = Rect.fromLTRB(left, top, right, bottom);
        if (cornerRadius > 0) {
          final rrect = RRect.fromRectAndRadius(
            rect,
            Radius.circular(cornerRadius),
          );
          if (filled) canvas.drawRRect(rrect, ctx.body);
          canvas.drawRRect(rrect, ctx.stroke);
        } else {
          if (filled) canvas.drawRect(rect, ctx.body);
          canvas.drawRect(rect, ctx.stroke);
        }
    }
  }
}

Path _pathOf(List<SymbolPathCommand> commands) {
  final path = Path();
  for (final command in commands) {
    switch (command) {
      case SymbolMoveTo(:final x, :final y):
        path.moveTo(x, y);
      case SymbolLineTo(:final x, :final y):
        path.lineTo(x, y);
      case SymbolArcTo(:final x, :final y, :final radius):
        path.arcToPoint(Offset(x, y), radius: Radius.circular(radius));
      case SymbolQuadTo(:final cx, :final cy, :final x, :final y):
        path.quadraticBezierTo(cx, cy, x, y);
      case SymbolClose():
        path.close();
    }
  }
  return path;
}

/// AND-gate body ([andGateShape]).
void paintAndGate(Canvas canvas, Size size, SymbolPaintContext ctx) =>
    paintSymbolShape(canvas, andGateShape(size.width, size.height), ctx);

/// OR-gate body ([orGateShape]).
void paintOrGate(Canvas canvas, Size size, SymbolPaintContext ctx) =>
    paintSymbolShape(canvas, orGateShape(size.width, size.height), ctx);

/// Inverter body ([notGateShape]).
void paintNotGate(Canvas canvas, Size size, SymbolPaintContext ctx) =>
    paintSymbolShape(canvas, notGateShape(size.width, size.height), ctx);

/// Mux body ([muxShape]).
void paintMux(Canvas canvas, Size size, SymbolPaintContext ctx) =>
    paintSymbolShape(canvas, muxShape(size.width, size.height), ctx);

/// Flip-flop body ([flipFlopShape]).
void paintFlipFlop(Canvas canvas, Size size, SymbolPaintContext ctx) =>
    paintSymbolShape(canvas, flipFlopShape(size.width, size.height), ctx);

/// Latch body ([latchShape]).
void paintLatch(Canvas canvas, Size size, SymbolPaintContext ctx) =>
    paintSymbolShape(canvas, latchShape(size.width, size.height), ctx);

/// Generic catch-all body ([genericBoxShape]). The renderer paints the
/// cell's display label on top.
void paintGenericBox(Canvas canvas, Size size, SymbolPaintContext ctx) =>
    paintSymbolShape(canvas, genericBoxShape(size.width, size.height), ctx);
