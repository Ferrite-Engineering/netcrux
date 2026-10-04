// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart' show Color;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/services/schematic/schematic_crossing_overlay_provider.dart';

void main() {
  group('schematicCrossingOverlayProvider', () {
    test('default open-core value is null', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(schematicCrossingOverlayProvider), isNull);
    });

    test('override surfaces the supplied SchematicCrossingOverlay', () {
      const overlay = SchematicCrossingOverlay(
        sourceCellIds: <String>{'top.cpu.src_reg'},
        destinationCellIds: <String>{'top.cpu.sync_dest'},
        intermediateCellIds: <String>{'top.cpu.sync0', 'top.cpu.sync1'},
        severityColor: Color(0xFFE74C3C),
      );
      final container = ProviderContainer(
        overrides: <Override>[
          schematicCrossingOverlayProvider.overrideWithValue(overlay),
        ],
      );
      addTearDown(container.dispose);
      final read = container.read(schematicCrossingOverlayProvider);
      expect(read, isNotNull);
      expect(read, equals(overlay));
    });
  });

  group('SchematicCrossingOverlay', () {
    test('empty sentinel reports isEmpty + no involvement', () {
      expect(SchematicCrossingOverlay.empty.isEmpty, isTrue);
      expect(
        SchematicCrossingOverlay.empty.involvesCell('whatever'),
        isFalse,
      );
    });

    test('involvesCell returns true for any of the three role sets', () {
      const overlay = SchematicCrossingOverlay(
        sourceCellIds: <String>{'src'},
        destinationCellIds: <String>{'dst'},
        intermediateCellIds: <String>{'mid'},
        severityColor: Color(0xFF000000),
      );
      expect(overlay.involvesCell('src'), isTrue);
      expect(overlay.involvesCell('dst'), isTrue);
      expect(overlay.involvesCell('mid'), isTrue);
      expect(overlay.involvesCell('other'), isFalse);
    });

    test('equality compares by content not identity', () {
      const a = SchematicCrossingOverlay(
        sourceCellIds: <String>{'src'},
        destinationCellIds: <String>{'dst'},
        intermediateCellIds: <String>{},
        severityColor: Color(0xFFE74C3C),
      );
      const b = SchematicCrossingOverlay(
        sourceCellIds: <String>{'src'},
        destinationCellIds: <String>{'dst'},
        intermediateCellIds: <String>{},
        severityColor: Color(0xFFE74C3C),
      );
      const c = SchematicCrossingOverlay(
        sourceCellIds: <String>{'src'},
        destinationCellIds: <String>{'dst'},
        intermediateCellIds: <String>{},
        severityColor: Color(0xFFF1C40F),
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('equality and hash include the crossing net ids', () {
      const a = SchematicCrossingOverlay(
        sourceCellIds: <String>{'src'},
        destinationCellIds: <String>{},
        intermediateCellIds: <String>{},
        severityColor: Color(0xFFE74C3C),
        netIds: <int>{4, 5},
      );
      const b = SchematicCrossingOverlay(
        sourceCellIds: <String>{'src'},
        destinationCellIds: <String>{},
        intermediateCellIds: <String>{},
        severityColor: Color(0xFFE74C3C),
        netIds: <int>{5, 4},
      );
      const c = SchematicCrossingOverlay(
        sourceCellIds: <String>{'src'},
        destinationCellIds: <String>{},
        intermediateCellIds: <String>{},
        severityColor: Color(0xFFE74C3C),
        netIds: <int>{4},
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('non-empty overlay reports isEmpty=false', () {
      const overlay = SchematicCrossingOverlay(
        sourceCellIds: <String>{'src'},
        destinationCellIds: <String>{},
        intermediateCellIds: <String>{},
        severityColor: Color(0xFFE74C3C),
      );
      expect(overlay.isEmpty, isFalse);
    });
  });
}
