// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/netlist/module.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/domain/models/source_location.dart';
import 'package:netcrux/services/host_bridge/element_source_location.dart';

Module _module() => Module.fromJson('top', const <String, Object?>{
  'attributes': <String, Object?>{'src': 'rtl/top.v:1.1-40.10'},
  'ports': <String, Object?>{
    'a': <String, Object?>{
      'direction': 'input',
      'bits': <Object?>[2],
    },
  },
  'cells': <String, Object?>{
    'u_add': <String, Object?>{
      'type': r'$add',
      'attributes': <String, Object?>{'src': 'rtl/top.v:14.5-14.20'},
      'port_directions': <String, Object?>{'A': 'input'},
      'connections': <String, Object?>{
        'A': <Object?>[2],
      },
    },
    'u_bare': <String, Object?>{
      'type': r'$and',
      'attributes': <String, Object?>{},
      'port_directions': <String, Object?>{},
      'connections': <String, Object?>{},
    },
  },
  'netnames': <String, Object?>{
    'sum': <String, Object?>{
      'bits': <Object?>[7],
      'attributes': <String, Object?>{'src': 'rtl/top.v:9.8-9.11'},
    },
  },
});

void main() {
  group('parseYosysSrc', () {
    test('reads a multi-line span', () {
      expect(parseYosysSrc('rtl/top.v:3.1-20.10'), const [
        SourceLocation(filePath: 'rtl/top.v', line: 3, column: 1),
      ]);
    });

    test('reads a one-line span Yosys writes as line.col-col', () {
      expect(parseYosysSrc('rtl/top.v:14.5-20'), const [
        SourceLocation(filePath: 'rtl/top.v', line: 14, column: 5),
      ]);
    });

    test('reads a bare file and line', () {
      expect(parseYosysSrc('top.v:7'), const [
        SourceLocation(filePath: 'top.v', line: 7),
      ]);
    });

    test('keeps every place of a multi-location src, in order', () {
      expect(parseYosysSrc('a.v:1.1-2.2|b.v:3.4-3.9'), const [
        SourceLocation(filePath: 'a.v', line: 1, column: 1),
        SourceLocation(filePath: 'b.v', line: 3, column: 4),
      ]);
    });

    test('skips Yosys own sources and keeps a path with spaces whole', () {
      expect(parseYosysSrc('proc_dff.cc:220|/my rtl/top.v:5.1-5.4'), const [
        SourceLocation(filePath: '/my rtl/top.v', line: 5, column: 1),
      ]);
    });

    test('returns nothing for an absent or unreadable src', () {
      expect(parseYosysSrc(null), isEmpty);
      expect(parseYosysSrc(''), isEmpty);
      expect(parseYosysSrc('no location here'), isEmpty);
      expect(parseYosysSrc('top.v:0.1-2.2'), isEmpty);
    });
  });

  group('sourceLocationOfElement', () {
    final module = _module();

    test('a cell and its pin take the cell src', () {
      const want = SourceLocation(
        filePath: 'rtl/top.v',
        line: 14,
        column: 5,
      );
      expect(
        sourceLocationOfElement(
          module,
          const SelectedElement.cell(cellId: 'u_add'),
        ),
        want,
      );
      expect(
        sourceLocationOfElement(
          module,
          const SelectedElement.port(
            cellId: 'u_add',
            portId: 'u_add.A',
            portName: 'A',
          ),
        ),
        want,
      );
    });

    test('a boundary port takes the module src', () {
      expect(
        sourceLocationOfElement(
          module,
          const SelectedElement.boundaryPort(portId: 'a', portName: 'a'),
        ),
        const SourceLocation(filePath: 'rtl/top.v', line: 1, column: 1),
      );
    });

    test('a wire takes the src of the net carrying its bit', () {
      expect(
        sourceLocationOfElement(
          module,
          const SelectedElement.wire(edgeId: 'e', netId: 7),
        ),
        const SourceLocation(filePath: 'rtl/top.v', line: 9, column: 8),
      );
    });

    test('is null where the netlist records nothing', () {
      expect(
        sourceLocationOfElement(
          module,
          const SelectedElement.cell(cellId: 'u_bare'),
        ),
        isNull,
      );
      expect(
        sourceLocationOfElement(
          module,
          const SelectedElement.cell(cellId: 'missing'),
        ),
        isNull,
      );
      expect(
        sourceLocationOfElement(
          module,
          const SelectedElement.wire(edgeId: 'e', netId: 99),
        ),
        isNull,
      );
      expect(
        sourceLocationOfElement(module, const SelectedElement.none()),
        isNull,
      );
    });
  });
}
