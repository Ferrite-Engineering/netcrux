// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/layout/bounding_box.dart';
import 'package:netcrux/domain/models/layout/edge_route.dart';
import 'package:netcrux/domain/models/layout/netlist_layout.dart';
import 'package:netcrux/domain/models/layout/node_position.dart';

const _layoutJson = <String, Object?>{
  'id': 'root',
  'x': 0,
  'y': 0,
  'width': 200,
  'height': 100,
  'children': <Map<String, Object?>>[
    <String, Object?>{
      'id': 'u_and',
      'x': 10,
      'y': 10,
      'width': 50,
      'height': 30,
      'ports': <Map<String, Object?>>[
        <String, Object?>{
          'id': 'A',
          'x': 0,
          'y': 10,
          'width': 2,
          'height': 2,
        },
      ],
    },
    <String, Object?>{
      'id': 'u_or',
      'x': 100,
      'y': 10,
      'width': 50,
      'height': 30,
    },
  ],
  'edges': <Map<String, Object?>>[
    <String, Object?>{
      'id': 'n_data',
      'source': 'u_and',
      'target': 'u_or',
      'sections': <Map<String, Object?>>[
        <String, Object?>{
          'startPoint': <String, Object?>{'x': 60, 'y': 25},
          'endPoint': <String, Object?>{'x': 100, 'y': 25},
        },
      ],
    },
  ],
};

void main() {
  group('NetlistLayout', () {
    test('fromJson parses bounds, nodes, and edges', () {
      final layout = NetlistLayout.fromJson(_layoutJson);
      expect(layout.bounds.width, 200);
      expect(layout.bounds.height, 100);
      expect(layout.nodes, hasLength(2));
      expect(layout.edges, hasLength(1));
      expect(layout.nodes.first.id, 'u_and');
      expect(layout.edges.first.id, 'n_data');
    });

    test('fromJson tolerates missing children and edges', () {
      final layout = NetlistLayout.fromJson(const <String, Object?>{
        'id': 'root',
        'x': 0,
        'y': 0,
        'width': 0,
        'height': 0,
      });
      expect(layout.nodes, isEmpty);
      expect(layout.edges, isEmpty);
    });

    test('findNode returns the matching position or null', () {
      final layout = NetlistLayout.fromJson(_layoutJson);
      expect(layout.findNode('u_and'), isNotNull);
      expect(layout.findNode('u_and')!.bounds.x, 10);
      expect(layout.findNode('missing'), isNull);
    });

    test('findEdge returns the matching route or null', () {
      final layout = NetlistLayout.fromJson(_layoutJson);
      expect(layout.findEdge('n_data'), isNotNull);
      expect(layout.findEdge('nope'), isNull);
    });

    test('toJson round-trips through fromJson', () {
      final layout = NetlistLayout.fromJson(_layoutJson);
      final round = NetlistLayout.fromJson(layout.toJson());
      expect(round, equals(layout));
    });

    test('equality and hashCode are value-based', () {
      final a = NetlistLayout.fromJson(_layoutJson);
      final b = NetlistLayout.fromJson(_layoutJson);
      const c = NetlistLayout(
        nodes: <NodePosition>[],
        edges: <EdgeRoute>[],
        bounds: BoundingBox(x: 0, y: 0, width: 0, height: 0),
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
    });

    test('copyWith replaces only specified fields', () {
      final layout = NetlistLayout.fromJson(_layoutJson);
      final cleared = layout.copyWith(edges: const <EdgeRoute>[]);
      expect(cleared.edges, isEmpty);
      expect(cleared.nodes, layout.nodes);
    });
  });
}
