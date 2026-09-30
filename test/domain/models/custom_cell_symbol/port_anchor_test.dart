// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/custom_cell_symbol/port_anchor.dart';

void main() {
  group('PortAnchor', () {
    test('equality + hashCode match across identical anchors', () {
      const a = PortAnchor(x: 0.25, y: 0.5, side: PortAnchorSide.left);
      const b = PortAnchor(x: 0.25, y: 0.5, side: PortAnchorSide.left);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('equality respects every field', () {
      const base = PortAnchor(x: 0.5, y: 0.5, side: PortAnchorSide.right);
      expect(base.copyWith(x: 0.6), isNot(equals(base)));
      expect(base.copyWith(y: 0.6), isNot(equals(base)));
      expect(
        base.copyWith(side: PortAnchorSide.top),
        isNot(equals(base)),
      );
      expect(base.copyWith(labelOffsetDx: 5), isNot(equals(base)));
      expect(base.copyWith(labelOffsetDy: -2), isNot(equals(base)));
    });

    test('copyWith returns an equal copy when no fields are overridden', () {
      const base = PortAnchor(
        x: 0.1,
        y: 0.2,
        side: PortAnchorSide.bottom,
        labelOffsetDx: 3,
        labelOffsetDy: -4,
      );
      expect(base.copyWith(), equals(base));
    });

    test('toJson omits zero label offsets', () {
      const a = PortAnchor(x: 0.5, y: 0.75, side: PortAnchorSide.top);
      expect(a.toJson(), <String, Object?>{
        'x': 0.5,
        'y': 0.75,
        'side': 'top',
      });
    });

    test('toJson includes non-zero label offsets', () {
      const a = PortAnchor(
        x: 0.5,
        y: 0.5,
        side: PortAnchorSide.right,
        labelOffsetDx: 4,
        labelOffsetDy: -1,
      );
      final json = a.toJson();
      expect(json['labelOffsetDx'], 4);
      expect(json['labelOffsetDy'], -1);
    });

    test('fromJson round-trip preserves all fields', () {
      const original = PortAnchor(
        x: 0.33,
        y: 0.66,
        side: PortAnchorSide.bottom,
        labelOffsetDx: 2,
        labelOffsetDy: 1.5,
      );
      final roundTripped = PortAnchor.fromJson(original.toJson());
      expect(roundTripped, equals(original));
    });

    test('fromJson tolerates missing optional fields', () {
      final anchor = PortAnchor.fromJson(const <String, Object?>{
        'x': 0.5,
        'y': 0.5,
        'side': 'left',
      });
      expect(anchor.labelOffsetDx, 0);
      expect(anchor.labelOffsetDy, 0);
    });

    test('fromJson falls back to left side for unknown side names', () {
      final anchor = PortAnchor.fromJson(const <String, Object?>{
        'x': 0.5,
        'y': 0.5,
        'side': 'diagonal-northeast', // unknown
      });
      expect(anchor.side, PortAnchorSide.left);
    });

    test('fromJson tolerates missing numeric fields by defaulting to 0', () {
      final anchor = PortAnchor.fromJson(const <String, Object?>{
        'side': 'top',
      });
      expect(anchor.x, 0);
      expect(anchor.y, 0);
      expect(anchor.side, PortAnchorSide.top);
    });

    test('toString carries every field for diagnostic logs', () {
      const a = PortAnchor(x: 0.5, y: 0.5, side: PortAnchorSide.top);
      expect(a.toString(), contains('0.5'));
      expect(a.toString(), contains('top'));
    });
  });
}
