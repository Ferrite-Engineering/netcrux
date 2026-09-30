// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/netlist/port_direction.dart';
import 'package:netcrux/domain/models/schematic/cell_kind.dart';
import 'package:netcrux/domain/models/schematic/schematic_graph.dart';
import 'package:netcrux/features/viewer/symbols/cell_body_painter_factory.dart';
import 'package:netcrux/features/viewer/symbols/cell_body_painter_factory_provider.dart';
import 'package:netcrux/features/viewer/symbols/symbol_painters.dart';

void main() {
  group('defaultCellBodyPainterFactory', () {
    test('returns the built-in painter for the cell kind', () {
      const cell = SchematicCell(
        id: 'u_dff',
        kind: CellKind.flipFlop,
        type: r'$dff',
        ports: <SchematicPort>[],
      );
      final painter = defaultCellBodyPainterFactory(cell);
      // The built-in painter for flipFlop is paintFlipFlop. Identity
      // check confirms the default factory routes through painterFor.
      expect(identical(painter, paintFlipFlop), isTrue);
    });

    test('routes generic cells to paintGenericBox', () {
      const cell = SchematicCell(
        id: 'my_module',
        kind: CellKind.generic,
        type: 'my_module',
        ports: <SchematicPort>[],
      );
      final painter = defaultCellBodyPainterFactory(cell);
      expect(identical(painter, paintGenericBox), isTrue);
    });

    test('routes every CellKind to a non-null painter', () {
      for (final kind in CellKind.values) {
        final cell = SchematicCell(
          id: 'u',
          kind: kind,
          type: 't',
          ports: const <SchematicPort>[],
        );
        expect(defaultCellBodyPainterFactory(cell), isNotNull);
      }
    });
  });

  group('cellBodyPainterFactoryProvider', () {
    test('defaults to the open-core factory', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final factory = c.read(cellBodyPainterFactoryProvider);
      expect(identical(factory, defaultCellBodyPainterFactory), isTrue);
    });

    test('honours a Pro-style override', () {
      void customPainter(Canvas canvas, Size size, SymbolPaintContext ctx) {
        // Stand-in for the Pro SVG-rendering painter.
      }

      SymbolPainter customFactory(SchematicCell cell) => customPainter;

      final c = ProviderContainer(
        overrides: <Override>[
          cellBodyPainterFactoryProvider.overrideWithValue(customFactory),
        ],
      );
      addTearDown(c.dispose);
      final factory = c.read(cellBodyPainterFactoryProvider);
      const cell = SchematicCell(
        id: 'u',
        kind: CellKind.flipFlop,
        type: 'my_alu',
        ports: <SchematicPort>[
          SchematicPort(
            id: 'u:A',
            name: 'A',
            direction: PortDirection.input,
            side: SchematicPortSide.west,
          ),
        ],
      );
      // The factory's value is the customFactory function. Calling
      // it produces the customPainter we expect.
      expect(identical(factory(cell), customPainter), isTrue);
    });
  });
}
