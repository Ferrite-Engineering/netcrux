// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/layout/edge_route.dart';

void main() {
  group('LayoutPoint', () {
    test('fromJson reads x and y', () {
      final p = LayoutPoint.fromJson(const <String, Object?>{
        'x': 1,
        'y': 2.5,
      });
      expect(p.x, 1);
      expect(p.y, 2.5);
    });

    test('toJson round-trips', () {
      const p = LayoutPoint(3, 4);
      expect(LayoutPoint.fromJson(p.toJson()), equals(p));
    });

    test('equality and hashCode are value-based', () {
      const a = LayoutPoint(1, 2);
      const b = LayoutPoint(1, 2);
      const c = LayoutPoint(1, 3);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
    });
  });

  group('EdgeRoute', () {
    test('fromJson parses modern sections shape', () {
      final edge = EdgeRoute.fromJson(const <String, Object?>{
        'id': 'e1',
        'source': 'u_and',
        'target': 'u_or',
        'sourcePort': 'Y',
        'targetPort': 'A',
        'sections': <Map<String, Object?>>[
          <String, Object?>{
            'startPoint': <String, Object?>{'x': 0, 'y': 5},
            'bendPoints': <Map<String, Object?>>[
              <String, Object?>{'x': 50, 'y': 5},
              <String, Object?>{'x': 50, 'y': 15},
            ],
            'endPoint': <String, Object?>{'x': 100, 'y': 15},
          },
        ],
      });
      expect(edge.id, 'e1');
      expect(edge.points.first, const LayoutPoint(0, 5));
      expect(edge.points.last, const LayoutPoint(100, 15));
      expect(edge.points, hasLength(4));
      expect(edge.sourceNodeId, 'u_and');
      expect(edge.targetPortId, 'A');
    });

    test('fromJson tolerates legacy bendPoints-only shape', () {
      final edge = EdgeRoute.fromJson(const <String, Object?>{
        'id': 'e_legacy',
        'bendPoints': <Map<String, Object?>>[
          <String, Object?>{'x': 0, 'y': 0},
          <String, Object?>{'x': 10, 'y': 10},
        ],
      });
      expect(edge.points, hasLength(2));
    });

    test('fromJson handles edge with no routing data', () {
      final edge = EdgeRoute.fromJson(const <String, Object?>{'id': 'e0'});
      expect(edge.points, isEmpty);
    });

    test('toJson serializes back to the modern sections shape', () {
      const edge = EdgeRoute(
        id: 'e',
        points: <LayoutPoint>[
          LayoutPoint(0, 0),
          LayoutPoint(5, 5),
          LayoutPoint(10, 5),
        ],
        sourceNodeId: 'a',
        targetNodeId: 'b',
      );
      final json = edge.toJson();
      expect(json['sections'], isA<List<Object?>>());
      final round = EdgeRoute.fromJson(json);
      expect(round, equals(edge));
    });

    test('equality and hashCode are value-based', () {
      const a = EdgeRoute(
        id: 'e',
        points: <LayoutPoint>[LayoutPoint(0, 0), LayoutPoint(1, 1)],
      );
      const b = EdgeRoute(
        id: 'e',
        points: <LayoutPoint>[LayoutPoint(0, 0), LayoutPoint(1, 1)],
      );
      const c = EdgeRoute(
        id: 'e',
        points: <LayoutPoint>[LayoutPoint(0, 0), LayoutPoint(2, 1)],
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
    });

    test('copyWith replaces only specified fields', () {
      const edge = EdgeRoute(
        id: 'e',
        points: <LayoutPoint>[LayoutPoint(0, 0), LayoutPoint(1, 1)],
      );
      final renamed = edge.copyWith(id: 'e2');
      expect(renamed.id, 'e2');
      expect(renamed.points, edge.points);
    });
  });
}
