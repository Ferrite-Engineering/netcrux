// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The expected areas are sums worked out by hand from the cell areas in the
// library below and the instance counts in the netlist.

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/services/liberty/liberty_cell_index.dart';
import 'package:netcrux/services/liberty/liberty_library.dart';
import 'package:netcrux/services/liberty/liberty_parser.dart';
import 'package:netcrux/services/liberty/module_area_rollup.dart';

final LibertyLibrary _library = LibertyParser.parseString('''
library (l) {
  cell (INV) { area : 1.5 ; pin (A) { direction : input ; } pin (Y) { direction : output ; } }
  cell (NAND2) { area : 2.25 ; pin (A) { direction : input ; } pin (B) { direction : input ; } pin (Y) { direction : output ; } }
  cell (NOAREA) { pin (A) { direction : input ; } }
}
''');

Map<String, Object?> _cell(String type) => <String, Object?>{
  'type': type,
  'connections': <String, Object?>{},
};

Map<String, Object?> _module(
  Map<String, String> cells, {
  bool blackBox = false,
}) => <String, Object?>{
  'attributes': <String, Object?>{
    if (blackBox) 'blackbox': '1',
  },
  'ports': <String, Object?>{},
  'cells': <String, Object?>{
    for (final entry in cells.entries) entry.key: _cell(entry.value),
  },
  'netnames': <String, Object?>{},
};

NetlistModel _model(Map<String, Map<String, Object?>> modules) =>
    NetlistModel.fromJson(<String, Object?>{
      'creator': 'test',
      'modules': modules,
    });

ModuleAreaRollup _rollup(NetlistModel model) =>
    ModuleAreaRollup(model, LibertyCellIndex(<LibertyLibrary>[_library]));

void main() {
  test('sums leaf cells and multiplies a submodule by its instances', () {
    final model = _model(<String, Map<String, Object?>>{
      'top': _module(<String, String>{
        'u_a': 'sub',
        'u_b': 'sub',
        'u_inv': 'INV',
      }),
      'sub': _module(<String, String>{
        'n0': 'NAND2',
        'n1': 'NAND2',
        'i0': 'INV',
      }),
      // The black-box module a library cell becomes on the Yosys route.
      'INV': _module(const <String, String>{}, blackBox: true),
    });
    final rollup = _rollup(model);
    // sub = 2 × 2.25 + 1.5 = 6; top = 2 × 6 + 1.5 = 13.5.
    expect(rollup.areaOf('sub'), const ModuleArea(area: 6, partial: false));
    expect(rollup.areaOf('top'), const ModuleArea(area: 13.5, partial: false));
    expect(rollup.areaOf('nothing'), isNull);
  });

  test('a leaf with no area makes the sum partial, and the parents too', () {
    final model = _model(<String, Map<String, Object?>>{
      'top': _module(<String, String>{'u': 'sub', 'i': 'INV'}),
      'sub': _module(<String, String>{
        'n': 'NAND2',
        'x': 'NOAREA',
        'y': r'$and',
        'z': 'undefined_box',
      }),
    });
    final rollup = _rollup(model);
    expect(rollup.areaOf('sub'), const ModuleArea(area: 2.25, partial: true));
    expect(rollup.areaOf('top'), const ModuleArea(area: 3.75, partial: true));
  });

  test('a module with no library cell at all says nothing', () {
    final model = _model(<String, Map<String, Object?>>{
      'top': _module(<String, String>{'a': r'$and', 'b': r'$or'}),
    });
    final area = _rollup(model).areaOf('top')!;
    expect(area.isKnown, isFalse);
    expect(area.partial, isTrue);
  });

  test("Yosys's bookkeeping cells are neither area nor missing area", () {
    final model = _model(<String, Map<String, Object?>>{
      'top': _module(<String, String>{
        'i': 'INV',
        's': r'$scopeinfo',
        'm': r'$meminit_v2',
      }),
    });
    expect(
      _rollup(model).areaOf('top'),
      const ModuleArea(area: 1.5, partial: false),
    );
  });

  test('a module of the design wins over a library cell of its name', () {
    final model = _model(<String, Map<String, Object?>>{
      'top': _module(<String, String>{'u': 'INV'}),
      // The source defines INV as two NAND2s.
      'INV': _module(<String, String>{'a': 'NAND2', 'b': 'NAND2'}),
    });
    expect(
      _rollup(model).areaOf('top'),
      const ModuleArea(area: 4.5, partial: false),
    );
  });

  test('a module that instantiates itself ends, counted as partial', () {
    final model = _model(<String, Map<String, Object?>>{
      'top': _module(<String, String>{'u': 'loop', 'i': 'INV'}),
      'loop': _module(<String, String>{'self': 'loop', 'n': 'NAND2'}),
    });
    final rollup = _rollup(model);
    expect(rollup.areaOf('loop'), const ModuleArea(area: 2.25, partial: true));
    expect(rollup.areaOf('top'), const ModuleArea(area: 3.75, partial: true));
  });

  test('each module is summed once, however often it is asked for', () {
    final model = _model(<String, Map<String, Object?>>{
      'top': _module(<String, String>{'i': 'INV'}),
    });
    final rollup = _rollup(model);
    expect(identical(rollup.areaOf('top'), rollup.areaOf('top')), isTrue);
  });
}
