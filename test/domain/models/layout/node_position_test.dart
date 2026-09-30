// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/layout/bounding_box.dart';
import 'package:netcrux/domain/models/layout/node_position.dart';

void main() {
  group('NodePosition', () {
    test('fromJson reads id, bounds, and port positions', () {
      final node = NodePosition.fromJson(const <String, Object?>{
        'id': 'u_and',
        'x': 10,
        'y': 20,
        'width': 30,
        'height': 40,
        'ports': <Map<String, Object?>>[
          <String, Object?>{
            'id': 'A',
            'x': 0,
            'y': 5,
            'width': 2,
            'height': 2,
          },
          <String, Object?>{
            'id': 'B',
            'x': 0,
            'y': 25,
            'width': 2,
            'height': 2,
          },
        ],
      });
      expect(node.id, 'u_and');
      expect(node.bounds.x, 10);
      expect(node.bounds.width, 30);
      expect(node.ports.keys, containsAll(<String>['A', 'B']));
      expect(node.ports['A']!.y, 5);
    });

    test('fromJson tolerates missing ports array', () {
      final node = NodePosition.fromJson(const <String, Object?>{
        'id': 'n',
        'x': 0,
        'y': 0,
        'width': 1,
        'height': 1,
      });
      expect(node.ports, isEmpty);
    });

    test('toJson round-trips through fromJson', () {
      const node = NodePosition(
        id: 'x',
        bounds: BoundingBox(x: 1, y: 2, width: 3, height: 4),
        ports: <String, BoundingBox>{
          'a': BoundingBox(x: 0, y: 0, width: 1, height: 1),
        },
      );
      expect(NodePosition.fromJson(node.toJson()), equals(node));
    });

    test('equality and hashCode are value-based', () {
      const a = NodePosition(
        id: 'n',
        bounds: BoundingBox(x: 0, y: 0, width: 1, height: 1),
      );
      const b = NodePosition(
        id: 'n',
        bounds: BoundingBox(x: 0, y: 0, width: 1, height: 1),
      );
      const c = NodePosition(
        id: 'n',
        bounds: BoundingBox(x: 0, y: 0, width: 2, height: 1),
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
    });

    test('copyWith replaces only specified fields', () {
      const node = NodePosition(
        id: 'n',
        bounds: BoundingBox(x: 0, y: 0, width: 1, height: 1),
      );
      final renamed = node.copyWith(id: 'm');
      expect(renamed.id, 'm');
      expect(renamed.bounds, node.bounds);
    });
  });
}
