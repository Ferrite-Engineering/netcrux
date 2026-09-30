// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/schematic/cell_kind.dart';
import 'package:netcrux/features/viewer/symbols/symbol_painters.dart';

/// Hosts a [SymbolPainter] inside a [CustomPaint] at a fixed pixel
/// size. Goldens capture the resulting bitmap so visual regressions
/// (a stray stroke, a missing arc) trip the test suite.
class _SymbolHarness extends StatelessWidget {
  const _SymbolHarness({required this.kind, required this.size});

  final CellKind kind;
  final Size size;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData.dark();
    final ctx = SymbolPaintContext.fromTheme(theme);
    return ColoredBox(
      color: theme.colorScheme.surface,
      child: Center(
        child: CustomPaint(
          size: size,
          painter: _DelegatePainter(painterFor(kind), ctx),
        ),
      ),
    );
  }
}

class _DelegatePainter extends CustomPainter {
  _DelegatePainter(this.painter, this.ctx);

  final SymbolPainter painter;
  final SymbolPaintContext ctx;

  @override
  void paint(Canvas canvas, Size size) => painter(canvas, size, ctx);

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

void main() {
  const standardSize = Size(120, 80);
  // Bound the surface tightly so golden files stay small and the
  // shape dominates the frame.
  const surfaceSize = Size(160, 120);

  Future<void> pumpSymbol(WidgetTester tester, CellKind kind) async {
    await tester.binding.setSurfaceSize(surfaceSize);
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: _SymbolHarness(kind: kind, size: standardSize),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  group('SymbolPainter — paints without throwing', () {
    for (final kind in CellKind.values) {
      testWidgets('paintFor(${kind.name})', (tester) async {
        await pumpSymbol(tester, kind);
        // Golden lives under test/features/viewer/symbols/goldens/.
        // Goldens are platform-sensitive; we accept the host-machine
        // baseline (auto-recorded on first run via --update-goldens)
        // and lock in subsequent regressions.
        await expectLater(
          find.byType(CustomPaint).first,
          matchesGoldenFile('goldens/${kind.name}.png'),
        );
      });
    }
  });

  group('painterFor dispatch', () {
    test('returns a distinct painter per kind', () {
      // Distinct dispatch is part of the contract — the renderer
      // relies on it for per-cell symbol routing. We assert pairwise
      // identity to catch accidental dispatch collapses.
      final painters = <CellKind, SymbolPainter>{
        for (final kind in CellKind.values) kind: painterFor(kind),
      };
      final entries = painters.entries.toList();
      for (var i = 0; i < entries.length; i++) {
        for (var j = i + 1; j < entries.length; j++) {
          expect(
            identical(entries[i].value, entries[j].value),
            isFalse,
            reason:
                '${entries[i].key.name} and ${entries[j].key.name} share a painter',
          );
        }
      }
    });
  });

  group('SymbolPaintContext', () {
    test('fromTheme composes paints from the active ColorScheme', () {
      final ctx = SymbolPaintContext.fromTheme(ThemeData.dark());
      expect(ctx.body.style, PaintingStyle.fill);
      expect(ctx.stroke.style, PaintingStyle.stroke);
      expect(ctx.stroke.strokeWidth, greaterThan(0));
      expect(ctx.accent.style, PaintingStyle.stroke);
      expect(ctx.isSelected, isFalse);
      expect(ctx.isHovered, isFalse);
    });
  });
}
