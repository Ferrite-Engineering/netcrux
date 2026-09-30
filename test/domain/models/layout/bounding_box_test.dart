// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/layout/bounding_box.dart';

void main() {
  group('BoundingBox', () {
    test('fromJson reads x, y, width, height', () {
      final box = BoundingBox.fromJson(const <String, Object?>{
        'x': 1.5,
        'y': 2,
        'width': 30,
        'height': 40.25,
      });
      expect(box.x, 1.5);
      expect(box.y, 2);
      expect(box.width, 30);
      expect(box.height, 40.25);
    });

    test('fromJson defaults missing keys to 0', () {
      final box = BoundingBox.fromJson(const <String, Object?>{'x': 5});
      expect(box.x, 5);
      expect(box.y, 0);
      expect(box.width, 0);
      expect(box.height, 0);
    });

    test('fromJson tolerates int and string number forms', () {
      final box = BoundingBox.fromJson(const <String, Object?>{
        'x': 1,
        'y': '2.5',
        'width': 3,
        'height': '4',
      });
      expect(box.x, 1);
      expect(box.y, 2.5);
      expect(box.height, 4);
    });

    test('right/bottom derive from origin + size', () {
      const box = BoundingBox(x: 10, y: 20, width: 30, height: 40);
      expect(box.right, 40);
      expect(box.bottom, 60);
    });

    test('toJson round-trips through fromJson', () {
      const box = BoundingBox(x: 1, y: 2, width: 3, height: 4);
      expect(BoundingBox.fromJson(box.toJson()), equals(box));
    });

    test('equality and hashCode are value-based', () {
      const a = BoundingBox(x: 1, y: 2, width: 3, height: 4);
      const b = BoundingBox(x: 1, y: 2, width: 3, height: 4);
      const c = BoundingBox(x: 1, y: 2, width: 3, height: 5);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
    });

    test('copyWith replaces only specified fields', () {
      const box = BoundingBox(x: 1, y: 2, width: 3, height: 4);
      final shifted = box.copyWith(x: 10);
      expect(shifted.x, 10);
      expect(shifted.y, 2);
    });

    group('encompass', () {
      test('returns null for an empty iterable', () {
        expect(BoundingBox.encompass(const <BoundingBox>[]), isNull);
      });

      test('returns the single box unchanged', () {
        const box = BoundingBox(x: 5, y: 6, width: 7, height: 8);
        expect(BoundingBox.encompass(const <BoundingBox>[box]), box);
      });

      test('spans the union of several disjoint boxes', () {
        final union = BoundingBox.encompass(const <BoundingBox>[
          BoundingBox(x: 0, y: 0, width: 60, height: 40),
          BoundingBox(x: 200, y: 10, width: 60, height: 40),
          BoundingBox(x: 100, y: -20, width: 10, height: 10),
        ]);
        // min x/y = 0/-20; max right/bottom = 260/50.
        expect(union, const BoundingBox(x: 0, y: -20, width: 260, height: 70));
      });
    });
  });
}
