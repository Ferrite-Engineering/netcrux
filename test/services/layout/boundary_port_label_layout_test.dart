// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Module ports are named beside their boxes. The layout leaves room for each
// name on the side the port's wire does not use, so a neighbouring port or
// cell never covers the name and the name never lies over its own wire. The
// design is the shape of a small gate-level block with supply ports: `vccd1`
// and `vssd1` are inout and nothing else drives their nets, so each one
// drives its wires out of the east face of its box, like an input.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/layout/bounding_box.dart';
import 'package:netcrux/domain/models/netlist/port_direction.dart';
import 'package:netcrux/domain/models/schematic/boundary_port_label.dart';
import 'package:netcrux/domain/models/schematic/symbol_shapes.dart';
import 'package:netcrux/services/layout/native_elk_solver.dart';

import '../../helpers/elk_ffi_library_gate.dart';
import '../../helpers/layout_parity.dart';

Map<String, Object?> _cell(
  String type,
  Map<String, String> directions,
  Map<String, int> bits,
) => <String, Object?>{
  'type': type,
  'port_directions': directions,
  'connections': <String, Object?>{
    for (final e in bits.entries) e.key: <int>[e.value],
  },
};

const Map<String, String> _supply = <String, String>{
  'VPWR': 'inout',
  'VGND': 'inout',
};

/// `top(inout vccd1_supply, inout vssd1_supply, input clk_in, input
/// data_in, input enable, output q_out)`: an AND of `data_in` and `enable`,
/// a flip-flop, a buffer and a second flip-flop, every cell on both supplies.
final String _netlist = jsonEncode(<String, Object?>{
  'creator': 'hand-written for the boundary label test',
  'modules': <String, Object?>{
    'top': <String, Object?>{
      'attributes': <String, Object?>{
        'top': '00000000000000000000000000000001',
      },
      'ports': <String, Object?>{
        'vccd1_supply': <String, Object?>{
          'direction': 'inout',
          'bits': <int>[2],
        },
        'vssd1_supply': <String, Object?>{
          'direction': 'inout',
          'bits': <int>[3],
        },
        'clk_in': <String, Object?>{
          'direction': 'input',
          'bits': <int>[4],
        },
        'data_in': <String, Object?>{
          'direction': 'input',
          'bits': <int>[5],
        },
        'enable': <String, Object?>{
          'direction': 'input',
          'bits': <int>[6],
        },
        'q_out': <String, Object?>{
          'direction': 'output',
          'bits': <int>[7],
        },
      },
      'cells': <String, Object?>{
        'u0': _cell(
          'cell_and2',
          <String, String>{
            'A': 'input',
            'B': 'input',
            'X': 'output',
            ..._supply,
          },
          <String, int>{'A': 5, 'B': 6, 'X': 8, 'VPWR': 2, 'VGND': 3},
        ),
        'u1': _cell(
          'cell_dff',
          <String, String>{
            'CLK': 'input',
            'D': 'input',
            'Q': 'output',
            ..._supply,
          },
          <String, int>{'CLK': 4, 'D': 8, 'Q': 9, 'VPWR': 2, 'VGND': 3},
        ),
        'u2': _cell(
          'cell_buf',
          <String, String>{'A': 'input', 'X': 'output', ..._supply},
          <String, int>{'A': 9, 'X': 10, 'VPWR': 2, 'VGND': 3},
        ),
        'u3': _cell(
          'cell_dff',
          <String, String>{
            'CLK': 'input',
            'D': 'input',
            'Q': 'output',
            ..._supply,
          },
          <String, int>{'CLK': 4, 'D': 10, 'Q': 7, 'VPWR': 2, 'VGND': 3},
        ),
      },
      'netnames': <String, Object?>{
        'vccd1_supply': <String, Object?>{
          'bits': <int>[2],
        },
        'vssd1_supply': <String, Object?>{
          'bits': <int>[3],
        },
        'clk_in': <String, Object?>{
          'bits': <int>[4],
        },
        'data_in': <String, Object?>{
          'bits': <int>[5],
        },
        'enable': <String, Object?>{
          'bits': <int>[6],
        },
        'q_out': <String, Object?>{
          'bits': <int>[7],
        },
        'a': <String, Object?>{
          'bits': <int>[8],
        },
        'b': <String, Object?>{
          'bits': <int>[9],
        },
        'c': <String, Object?>{
          'bits': <int>[10],
        },
      },
    },
  },
});

/// Every module port of the design and which side its name goes on: the
/// inputs and the two supplies (which drive their nets) on the west, the
/// output on the east.
const Map<String, bool> _westByPort = <String, bool>{
  'vccd1_supply': true,
  'vssd1_supply': true,
  'clk_in': true,
  'data_in': true,
  'enable': true,
  'q_out': false,
};

Map<String, Map<String, Object?>> _portNodes(String input) {
  final doc = jsonDecode(input) as Map<String, Object?>;
  return <String, Map<String, Object?>>{
    for (final child
        in (doc['children']! as List<Object?>).cast<Map<String, Object?>>())
      if ((child['id']! as String).startsWith('port:'))
        (child['id']! as String).substring(5): child,
  };
}

void main() {
  group('BoundaryPortLabel.onWest', () {
    test('an input, and an inout that drives its net, are named on the west '
        'side', () {
      expect(
        BoundaryPortLabel.onWest(
          direction: PortDirection.input,
          drivesWire: true,
        ),
        isTrue,
      );
      expect(
        BoundaryPortLabel.onWest(
          direction: PortDirection.inout,
          drivesWire: true,
        ),
        isTrue,
      );
    });

    test('an output, and an inout another driver drives, on the east', () {
      expect(
        BoundaryPortLabel.onWest(
          direction: PortDirection.output,
          drivesWire: false,
        ),
        isFalse,
      );
      expect(
        BoundaryPortLabel.onWest(
          direction: PortDirection.inout,
          drivesWire: false,
        ),
        isFalse,
      );
    });

    test('a long name is given the width it is drawn at, no more', () {
      expect(BoundaryPortLabel.widthFor('vdd'), 3 * 7);
      expect(
        BoundaryPortLabel.widthFor('a_very_long_supply_port_name'),
        BoundaryPortLabel.maxWidth,
      );
    });
  });

  test('every port node carries its sized name on the side away from its '
      'wire', () {
    final nodes = _portNodes(elkInputForModule(_netlist, 'top'));
    expect(nodes.keys.toSet(), _westByPort.keys.toSet());
    for (final MapEntry(key: name, value: west) in _westByPort.entries) {
      final node = nodes[name]!;
      final label =
          (node['labels']! as List<Object?>).single! as Map<String, Object?>;
      expect(label['text'], name);
      expect(label['width'], BoundaryPortLabel.widthFor(name));
      expect(label['height'], BoundaryPortLabel.height);
      final options = node['layoutOptions']! as Map<String, Object?>;
      expect(
        options['elk.nodeLabels.placement'],
        west ? '[OUTSIDE, H_LEFT, V_CENTER]' : '[OUTSIDE, H_RIGHT, V_CENTER]',
        reason: name,
      );
      // The importer reads `layoutOptions` or `properties`, never both.
      expect(node.containsKey('properties'), isFalse);
    }
  });

  test('laid out, no name is covered by another node or crosses its own '
      'wire', () {
    if (!requireElkFfiLibrary()) return;
    final input = elkInputForModule(_netlist, 'top');
    final solver = NativeElkSolver.open();
    addTearDown(solver.dispose);
    final layout = parseLayout(solver.solve(input));

    final doc = jsonDecode(input) as Map<String, Object?>;
    final edgesOf = <String, Set<String>>{};
    for (final edge
        in (doc['edges']! as List<Object?>).cast<Map<String, Object?>>()) {
      for (final end in <Object?>[
        ...edge['sources']! as List<Object?>,
        ...edge['targets']! as List<Object?>,
      ]) {
        edgesOf
            .putIfAbsent(end! as String, () => <String>{})
            .add(
              edge['id']! as String,
            );
      }
    }

    bool overlaps(BoundingBox a, BoundingBox b) =>
        a.x < b.x + b.width &&
        b.x < a.x + a.width &&
        a.y < b.y + b.height &&
        b.y < a.y + a.height;

    final labels = <String, BoundingBox>{};
    for (final MapEntry(key: name, value: west) in _westByPort.entries) {
      final box = layout.findNode('port:$name')!.bounds;
      final width = BoundaryPortLabel.widthFor(name);
      const gap = SchematicDetailMarks.boundaryLabelGap;
      labels[name] = BoundingBox(
        x: west ? box.x - gap - width : box.x + box.width + gap,
        y: box.y + box.height / 2 - BoundaryPortLabel.height / 2,
        width: width,
        height: BoundaryPortLabel.height,
      );
    }

    for (final MapEntry(key: name, value: label) in labels.entries) {
      for (final node in layout.nodes) {
        if (node.id == 'port:$name') continue;
        expect(
          overlaps(label, node.bounds),
          isFalse,
          reason: 'the name of $name lies under ${node.id}',
        );
      }
      for (final MapEntry(key: other, value: otherLabel) in labels.entries) {
        if (other == name) continue;
        expect(
          overlaps(label, otherLabel),
          isFalse,
          reason: 'the names of $name and $other overlap',
        );
      }
      for (final route in layout.edges) {
        if (!(edgesOf['port:$name']?.contains(route.id) ?? false)) continue;
        for (var i = 0; i + 1 < route.points.length; i++) {
          final a = route.points[i];
          final b = route.points[i + 1];
          final x0 = a.x < b.x ? a.x : b.x;
          final y0 = a.y < b.y ? a.y : b.y;
          final segment = BoundingBox(
            x: x0 - 0.5,
            y: y0 - 0.5,
            width: (a.x - b.x).abs() + 1,
            height: (a.y - b.y).abs() + 1,
          );
          expect(
            overlaps(label, segment),
            isFalse,
            reason: 'the name of $name lies over its own wire ${route.id}',
          );
        }
      }
    }
  });
}
