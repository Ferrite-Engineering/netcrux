// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/netlist/bit_ref.dart';
import 'package:netcrux/domain/models/netlist/cell.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/netlist/port_direction.dart';
import 'package:netcrux/services/schematic/declared_cell_ports.dart';

Map<String, Object?> _cell(
  String type,
  Map<String, String> directions,
  Map<String, List<Object>> connections,
) => <String, Object?>{
  'hide_name': 0,
  'type': type,
  'parameters': <String, Object?>{},
  'attributes': <String, Object?>{},
  'port_directions': directions,
  'connections': connections,
};

/// A top with a `$mul` missing `B`, a complete `$and`, an instance of the
/// black box `LUT2` missing `I1`, and a cell of a type nothing describes.
final Map<String, Object?> _json = <String, Object?>{
  'creator': 'hand-built',
  'modules': <String, Object?>{
    'LUT2': <String, Object?>{
      'attributes': <String, Object?>{'blackbox': '1'},
      'ports': <String, Object?>{
        'I0': <String, Object?>{
          'direction': 'input',
          'bits': <Object>[2],
        },
        'I1': <String, Object?>{
          'direction': 'input',
          'bits': <Object>[3],
        },
        'O': <String, Object?>{
          'direction': 'output',
          'bits': <Object>[4],
        },
      },
      'cells': <String, Object?>{},
      'netnames': <String, Object?>{},
    },
    'top': <String, Object?>{
      'attributes': <String, Object?>{'top': '1'},
      'ports': <String, Object?>{},
      'cells': <String, Object?>{
        'u_mul': _cell(
          r'$mul',
          <String, String>{'A': 'input', 'Y': 'output'},
          <String, List<Object>>{
            'A': <Object>[5],
            'Y': <Object>[6],
          },
        ),
        'u_and': _cell(
          r'$and',
          <String, String>{'A': 'input', 'B': 'input', 'Y': 'output'},
          <String, List<Object>>{
            'A': <Object>[5],
            'B': <Object>[6],
            'Y': <Object>[7],
          },
        ),
        'u_lut': _cell(
          'LUT2',
          <String, String>{'I0': 'input', 'O': 'output'},
          <String, List<Object>>{
            'O': <Object>[8],
            'I0': <Object>[7],
          },
        ),
        'u_odd': _cell(
          'MYSTERY',
          <String, String>{},
          <String, List<Object>>{
            'Z': <Object>[8],
          },
        ),
      },
      'netnames': <String, Object?>{},
    },
  },
};

void main() {
  final model = NetlistModel.fromJson(_json);
  final top = model.modules['top']!;

  group('declaredPortsFor', () {
    test('reads a module of the netlist first', () {
      expect(declaredPortsFor(model, 'LUT2'), <String, PortDirection>{
        'I0': PortDirection.input,
        'I1': PortDirection.input,
        'O': PortDirection.output,
      });
    });

    test('knows the parameter-independent Yosys cells', () {
      expect(declaredPortsFor(model, r'$mul'), <String, PortDirection>{
        'A': PortDirection.input,
        'B': PortDirection.input,
        'Y': PortDirection.output,
      });
      expect(declaredPortsFor(model, r'$_MUX_')!.keys, <String>[
        'A',
        'B',
        'S',
        'Y',
      ]);
    });

    test('is null for a type nothing describes', () {
      expect(declaredPortsFor(model, 'MYSTERY'), isNull);
      expect(declaredPortsFor(model, r'$dff'), isNull);
    });
  });

  group('withDeclaredCellPorts', () {
    final patched = withDeclaredCellPorts(model, top);

    test('adds a missing primitive port with no bits, in order', () {
      final mul = patched.cells['u_mul']!;
      expect(mul.connections.keys, <String>['A', 'B', 'Y']);
      expect(mul.connections['B'], isEmpty);
      expect(mul.portDirections['B'], PortDirection.input);
      expect(mul.connections['A'], const <BitRef>[NetBit(5)]);
    });

    test('adds a missing black-box port in declaration order', () {
      final lut = patched.cells['u_lut']!;
      expect(lut.connections.keys, <String>['I0', 'I1', 'O']);
      expect(lut.connections['I1'], isEmpty);
      expect(lut.portDirections['I1'], PortDirection.input);
    });

    test('keeps a complete cell and an undescribed one as they are', () {
      expect(identical(patched.cells['u_and'], top.cells['u_and']), isTrue);
      expect(identical(patched.cells['u_odd'], top.cells['u_odd']), isTrue);
    });

    test('returns the module itself when no cell misses a port', () {
      final complete = top.copyWith(
        cells: <String, Cell>{'u_and': top.cells['u_and']!},
      );
      expect(
        identical(withDeclaredCellPorts(model, complete), complete),
        isTrue,
      );
    });

    test('leaves the input module unchanged', () {
      expect(top.cells['u_mul']!.connections.keys, <String>['A', 'Y']);
    });
  });
}
