// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The headless render pipeline behind `tool/render_schematic.dart`: finding a
// scope by its path, laying it out as the canvas does, and sizing the picture.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/layout/bounding_box.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/services/export/scope_render.dart';
import 'package:netcrux/services/layout/native_elk_solver.dart';
import 'package:netcrux/services/yosys/streaming_yosys_json_reader.dart';

import '../../helpers/elk_ffi_library_gate.dart';

/// `top` instantiates `sub` as `u_sub`; `sub` is one AND gate between its
/// ports.
const String _netlist = r'''
{
  "modules": {
    "top": {
      "attributes": {"top": "00000000000000000000000000000001"},
      "ports": {
        "a": {"direction": "input", "bits": [2]},
        "b": {"direction": "input", "bits": [3]},
        "y": {"direction": "output", "bits": [4]}
      },
      "cells": {
        "u_sub": {
          "type": "sub",
          "port_directions": {"a": "input", "b": "input", "y": "output"},
          "connections": {"a": [2], "b": [3], "y": [4]}
        }
      },
      "netnames": {}
    },
    "sub": {
      "attributes": {},
      "ports": {
        "a": {"direction": "input", "bits": [2]},
        "b": {"direction": "input", "bits": [3]},
        "y": {"direction": "output", "bits": [4]}
      },
      "cells": {
        "g": {
          "type": "$and",
          "parameters": {},
          "port_directions": {"A": "input", "B": "input", "Y": "output"},
          "connections": {"A": [2], "B": [3], "Y": [4]}
        }
      },
      "netnames": {}
    }
  }
}
''';

NetlistModel _model() => const StreamingYosysJsonReader().parse(_netlist);

void main() {
  group('scopeAtPath', () {
    test('an empty path is the top module', () {
      final node = scopeAtPath(_model(), '');
      expect(node.isRoot, isTrue);
      expect(node.moduleName, 'top');
    });

    test('an instance path walks down, with or without the top name', () {
      final model = _model();
      expect(scopeAtPath(model, 'u_sub').moduleName, 'sub');
      expect(scopeAtPath(model, 'top.u_sub').path, <String>['u_sub']);
    });

    test('a path naming no instance says which segment and where', () {
      expect(
        () => scopeAtPath(_model(), 'u_sub.u_missing'),
        throwsA(
          isA<ScopeRenderException>().having(
            (e) => e.message,
            'message',
            allOf(contains('u_missing'), contains('top.u_sub')),
          ),
        ),
      );
    });
  });

  group('layOutScope', () {
    test('hands the solver the scope ELK input and keeps the graph', () {
      final model = _model();
      String? seen;
      final laidOut = layOutScope(model, scopeAtPath(model, 'u_sub'), (input) {
        seen = input;
        return jsonEncode(<String, Object?>{
          'id': 'root',
          'width': 120,
          'height': 40,
          'children': <Object?>[
            <String, Object?>{
              'id': 'g',
              'x': 40,
              'y': 0,
              'width': 80,
              'height': 40,
            },
          ],
          'edges': <Object?>[],
        });
      });
      final input = jsonDecode(seen!) as Map<String, Object?>;
      final ids = <String>[
        for (final c
            in (input['children']! as List<Object?>)
                .cast<Map<String, Object?>>())
          c['id']! as String,
      ];
      expect(ids, containsAll(<String>['g', 'port:a', 'port:b', 'port:y']));
      expect(laidOut.graph.moduleName, 'sub');
      expect(laidOut.layout.findNode('g'), isNotNull);
    });

    test('lays a real scope out with the native engine', () {
      if (!requireElkFfiLibrary()) return;
      final model = _model();
      final solver = NativeElkSolver.open();
      addTearDown(solver.dispose);
      final laidOut = layOutScope(
        model,
        scopeAtPath(model, 'u_sub'),
        solver.solve,
      );
      expect(laidOut.layout.findNode('g'), isNotNull);
      expect(laidOut.layout.edges, isNotEmpty);
    });
  });

  group('parseRenderRegion', () {
    test('reads x,y,width,height', () {
      final r = parseRenderRegion('10, -5, 200,100.5');
      expect(
        <double>[r.x, r.y, r.width, r.height],
        <double>[
          10,
          -5,
          200,
          100.5,
        ],
      );
    });

    test('refuses the wrong count, a non-number and an empty box', () {
      expect(() => parseRenderRegion('1,2,3'), throwsFormatException);
      expect(() => parseRenderRegion('1,2,x,4'), throwsFormatException);
      expect(() => parseRenderRegion('1,2,0,4'), throwsFormatException);
    });
  });

  group('renderPixelSize', () {
    test('scales the frame by the zoom, rounding up', () {
      const frame = BoundingBox(x: 0, y: 0, width: 100.2, height: 50);
      expect(renderPixelSize(frame, 2), (width: 201, height: 100));
    });

    test('refuses a picture too large to paint and names a zoom that fits', () {
      // The size of the eduBOS5 ALU that first needed this.
      const frame = BoundingBox(x: 0, y: 0, width: 1922, height: 23081);
      expect(
        () => renderPixelSize(frame, 1),
        throwsA(
          isA<ScopeRenderException>().having(
            (e) => e.message,
            'message',
            contains('--zoom 0.709'),
          ),
        ),
      );
    });
  });
}
