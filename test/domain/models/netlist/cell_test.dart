// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/netlist/bit_ref.dart';
import 'package:netcrux/domain/models/netlist/cell.dart';
import 'package:netcrux/domain/models/netlist/port_direction.dart';

void main() {
  group('Cell', () {
    test('fromJson parses type, parameters, connections, and directions', () {
      final cell = Cell.fromJson('u_and', const <String, Object?>{
        'hide_name': 0,
        'type': r'$and',
        'parameters': <String, Object?>{'WIDTH': '32'},
        'attributes': <String, Object?>{'src': 'foo.v:3'},
        'port_directions': <String, Object?>{
          'A': 'input',
          'B': 'input',
          'Y': 'output',
        },
        'connections': <String, Object?>{
          'A': <Object>[2],
          'B': <Object>[3],
          'Y': <Object>[4],
        },
      });
      expect(cell.name, 'u_and');
      expect(cell.type, r'$and');
      expect(cell.hideName, isFalse);
      expect(cell.parameters['WIDTH'], '32');
      expect(cell.attributes['src'], 'foo.v:3');
      expect(cell.portDirections['A'], PortDirection.input);
      expect(cell.portDirections['Y'], PortDirection.output);
      expect(cell.connections['A'], const <BitRef>[NetBit(2)]);
      expect(cell.connections['Y'], const <BitRef>[NetBit(4)]);
    });

    test('fromJson tolerates a hide_name flag set to 1', () {
      final cell = Cell.fromJson(r'$auto$0', const <String, Object?>{
        'hide_name': 1,
        'type': r'$not',
        'parameters': <String, Object?>{},
        'attributes': <String, Object?>{},
        'port_directions': <String, Object?>{},
        'connections': <String, Object?>{},
      });
      expect(cell.hideName, isTrue);
    });

    test('toJson round-trips through fromJson', () {
      const cell = Cell(
        name: 'u_mux',
        type: r'$mux',
        parameters: <String, String>{'WIDTH': '8'},
        attributes: <String, String>{'src': 'a.v:10'},
        portDirections: <String, PortDirection>{
          'A': PortDirection.input,
          'B': PortDirection.input,
          'S': PortDirection.input,
          'Y': PortDirection.output,
        },
        connections: <String, List<BitRef>>{
          'A': <BitRef>[NetBit(1)],
          'B': <BitRef>[NetBit(2)],
          'S': <BitRef>[NetBit(3)],
          'Y': <BitRef>[NetBit(4)],
        },
      );
      final json = cell.toJson();
      final parsed = Cell.fromJson('u_mux', json);
      expect(parsed, equals(cell));
    });

    test('equality is value-based across all fields', () {
      const a = Cell(
        name: 'c',
        type: 't',
        parameters: <String, String>{'k': 'v'},
        attributes: <String, String>{},
        portDirections: <String, PortDirection>{'P': PortDirection.input},
        connections: <String, List<BitRef>>{
          'P': <BitRef>[NetBit(1)],
        },
      );
      const b = Cell(
        name: 'c',
        type: 't',
        parameters: <String, String>{'k': 'v'},
        attributes: <String, String>{},
        portDirections: <String, PortDirection>{'P': PortDirection.input},
        connections: <String, List<BitRef>>{
          'P': <BitRef>[NetBit(1)],
        },
      );
      const c = Cell(
        name: 'c',
        type: 't',
        parameters: <String, String>{'k': 'v2'},
        attributes: <String, String>{},
        portDirections: <String, PortDirection>{'P': PortDirection.input},
        connections: <String, List<BitRef>>{
          'P': <BitRef>[NetBit(1)],
        },
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
    });

    test('copyWith replaces only specified fields', () {
      const cell = Cell(
        name: 'c',
        type: 't',
        parameters: <String, String>{},
        attributes: <String, String>{},
        portDirections: <String, PortDirection>{},
        connections: <String, List<BitRef>>{},
      );
      final renamed = cell.copyWith(name: 'd');
      expect(renamed.name, 'd');
      expect(renamed.type, 't');
    });
  });
}
