// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/netlist/bit_ref.dart';
import 'package:netcrux/domain/models/netlist/cell.dart';
import 'package:netcrux/domain/models/netlist/module.dart';
import 'package:netcrux/domain/models/netlist/net.dart';
import 'package:netcrux/domain/models/netlist/port.dart';
import 'package:netcrux/domain/models/netlist/port_direction.dart';

const _moduleJson = <String, Object?>{
  'attributes': <String, Object?>{'top': '1', 'src': 'and2.v:1'},
  'ports': <String, Object?>{
    'a': <String, Object?>{
      'direction': 'input',
      'bits': <Object>[2],
    },
    'b': <String, Object?>{
      'direction': 'input',
      'bits': <Object>[3],
    },
    'y': <String, Object?>{
      'direction': 'output',
      'bits': <Object>[4],
    },
  },
  'cells': <String, Object?>{
    'u_and': <String, Object?>{
      'hide_name': 0,
      'type': r'$and',
      'parameters': <String, Object?>{
        'A_WIDTH': '1',
        'B_WIDTH': '1',
        'Y_WIDTH': '1',
      },
      'attributes': <String, Object?>{},
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
    },
  },
  'netnames': <String, Object?>{
    'a': <String, Object?>{
      'hide_name': 0,
      'bits': <Object>[2],
      'attributes': <String, Object?>{},
    },
    'b': <String, Object?>{
      'hide_name': 0,
      'bits': <Object>[3],
      'attributes': <String, Object?>{},
    },
    'y': <String, Object?>{
      'hide_name': 0,
      'bits': <Object>[4],
      'attributes': <String, Object?>{},
    },
  },
};

void main() {
  group('Module', () {
    test('fromJson parses ports, cells, and netnames', () {
      final module = Module.fromJson('and2', _moduleJson);
      expect(module.name, 'and2');
      expect(module.ports.keys, containsAll(<String>['a', 'b', 'y']));
      expect(module.ports['a']!.direction, PortDirection.input);
      expect(module.cells['u_and']!.type, r'$and');
      expect(module.cells['u_and']!.connections['Y'], const <BitRef>[
        NetBit(4),
      ]);
      expect(module.nets.keys, containsAll(<String>['a', 'b', 'y']));
      expect(module.isTop, isTrue);
    });

    test('isTop is true for top=00000001 bit-string attribute encoding', () {
      const json = <String, Object?>{
        'attributes': <String, Object?>{'top': '00000001'},
        'ports': <String, Object?>{},
        'cells': <String, Object?>{},
        'netnames': <String, Object?>{},
      };
      final module = Module.fromJson('top_bit_encoded', json);
      expect(module.isTop, isTrue);
    });

    test(
      'isTop is true for the 32-bit bit-string encoding Yosys 0.65+ emits',
      () {
        const json = <String, Object?>{
          'attributes': <String, Object?>{
            'top': '00000000000000000000000000000001',
          },
          'ports': <String, Object?>{},
          'cells': <String, Object?>{},
          'netnames': <String, Object?>{},
        };
        final module = Module.fromJson('top_32bit', json);
        expect(module.isTop, isTrue);
      },
    );

    test('isTop is false for an all-zeros top attribute (corner case)', () {
      const json = <String, Object?>{
        'attributes': <String, Object?>{
          'top': '00000000000000000000000000000000',
        },
        'ports': <String, Object?>{},
        'cells': <String, Object?>{},
        'netnames': <String, Object?>{},
      };
      final module = Module.fromJson('not_top', json);
      expect(module.isTop, isFalse);
    });

    test('isTop is false when no top attribute is present', () {
      const json = <String, Object?>{
        'attributes': <String, Object?>{},
        'ports': <String, Object?>{},
        'cells': <String, Object?>{},
        'netnames': <String, Object?>{},
      };
      final module = Module.fromJson('child', json);
      expect(module.isTop, isFalse);
    });

    test('toJson round-trips through fromJson', () {
      final module = Module.fromJson('and2', _moduleJson);
      final parsed = Module.fromJson('and2', module.toJson());
      expect(parsed, equals(module));
    });

    test('equality and hashCode are value-based', () {
      final a = Module.fromJson('m', _moduleJson);
      final b = Module.fromJson('m', _moduleJson);
      const c = Module(
        name: 'm',
        attributes: <String, String>{},
        ports: <String, Port>{},
        cells: <String, Cell>{},
        nets: <String, Net>{},
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
    });

    test('copyWith replaces only specified fields', () {
      final module = Module.fromJson('m', _moduleJson);
      final renamed = module.copyWith(name: 'm2');
      expect(renamed.name, 'm2');
      expect(renamed.ports, module.ports);
    });
  });
}
