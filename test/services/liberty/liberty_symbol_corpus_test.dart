// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Every cell of four real standard-cell libraries, and a library of edge
// cases, drawn the way an independent description says it should be.
//
// The expectations are not NetCrux's output. For the PDK libraries they come
// from `test/fixtures/liberty/pdk/liberty_oracle.py`, which has its own
// Liberty reader and its own expression evaluator and follows the rules in
// `docs-site/docs/files-and-projects.md`; where it and the PDK's cell names
// disagree, `test/fixtures/liberty/pdk/REVIEW.md` records the decision. The
// edge-case expectations are written by hand. A difference here is a finding
// against NetCrux's reader or classifier, or against the oracle, and is
// settled by reading the cell's Liberty text.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/schematic/cell_kind.dart';
import 'package:netcrux/services/liberty/liberty_cell_index.dart';
import 'package:netcrux/services/liberty/liberty_library.dart';
import 'package:netcrux/services/liberty/liberty_parser.dart';
import 'package:path/path.dart' as p;

const String _pdkRoot = 'test/fixtures/liberty/pdk';

/// Every library of the corpus. Listed rather than discovered so a missing
/// file fails instead of shrinking the corpus; the test below checks the
/// list against the directory in the other direction.
const List<String> _pdkLibraries = <String>[
  'sky130_fd_sc_hd/sky130_fd_sc_hd__tt_025C_1v80.lib.gz',
  'gf180mcu_fd_sc_mcu7t5v0/gf180mcu_fd_sc_mcu7t5v0__tt_025C_5v00.lib.gz',
  'sg13g2_stdcell/sg13g2_stdcell_typ_1p20V_25C.lib.gz',
  'asap7sc7p5t/asap7sc7p5t_AO_RVT_TT_nldm_211120.lib.gz',
  'asap7sc7p5t/asap7sc7p5t_INVBUF_RVT_TT_nldm_220122.lib.gz',
  'asap7sc7p5t/asap7sc7p5t_OA_RVT_TT_nldm_211120.lib.gz',
  'asap7sc7p5t/asap7sc7p5t_SEQ_RVT_TT_nldm_220123.lib.gz',
  'asap7sc7p5t/asap7sc7p5t_SIMPLE_RVT_TT_nldm_211120.lib.gz',
];

const String _edgeCases = 'test/fixtures/liberty/edge_cases.lib';

/// `<name>.expected_symbols.json` beside [library], `<name>` being the file
/// name without `.gz` and `.lib`.
String _expectedPathFor(String library) {
  var base = p.basename(library);
  for (final suffix in const <String>['.gz', '.lib', '.liberty']) {
    if (base.endsWith(suffix)) {
      base = base.substring(0, base.length - suffix.length);
    }
  }
  return p.join(p.dirname(library), '$base.expected_symbols.json');
}

/// The oracle's word for each symbol.
String _kindName(CellKind kind) => switch (kind) {
  CellKind.buffer => 'buffer',
  CellKind.notGate => 'inverter',
  CellKind.andGate => 'and',
  CellKind.nandGate => 'nand',
  CellKind.orGate => 'or',
  CellKind.norGate => 'nor',
  CellKind.xorGate => 'xor',
  CellKind.xnorGate => 'xnor',
  CellKind.mux => 'mux2',
  CellKind.flipFlop => 'dff',
  CellKind.latch => 'latch',
  CellKind.generic => 'box',
};

List<String> _sorted(Iterable<Object?> values) =>
    <String>[for (final v in values) v! as String]..sort();

/// What NetCrux draws for [cell], in the expected file's shape.
({String kind, List<String> clock, List<String> power, List<String> ground})
_drawn(LibertyCell cell) {
  final symbol = libertyCellSymbolFor(cell);
  return (
    kind: symbol == null ? 'box' : _kindName(symbol.kind),
    clock: _sorted(symbol?.clockPins ?? const <String>{}),
    power: _sorted(symbol?.powerPins ?? const <String>{}),
    ground: _sorted(symbol?.groundPins ?? const <String>{}),
  );
}

/// Every difference between what [library] draws and [expected], one line
/// each.
List<String> _differences(
  LibertyLibrary library,
  Map<String, Object?> expected,
) {
  final out = <String>[];
  final cells = <String, LibertyCell>{
    for (final cell in library.cells) cell.name: cell,
  };
  for (final name in expected.keys.where((n) => !cells.containsKey(n))) {
    out.add('$name: in the expected file, not read from the library');
  }
  for (final name in cells.keys.where((n) => !expected.containsKey(n))) {
    out.add('$name: read from the library, not in the expected file');
  }
  for (final entry in cells.entries) {
    final want = expected[entry.key] as Map<String, Object?>?;
    if (want == null) continue;
    final got = _drawn(entry.value);
    void check(String field, Object? actual, Object? wanted) {
      if (jsonEncode(actual) != jsonEncode(wanted)) {
        out.add('${entry.key}: $field is $actual, expected $wanted');
      }
    }

    check('kind', got.kind, want['kind']);
    check('clock pins', got.clock, _sorted(want['clock']! as List<Object?>));
    check('power pins', got.power, _sorted(want['power']! as List<Object?>));
    check(
      'ground pins',
      got.ground,
      _sorted(want['ground']! as List<Object?>),
    );
    final area = (want['area'] as num?)?.toDouble();
    final actualArea = entry.value.area;
    if ((area == null) != (actualArea == null) ||
        (area != null && (actualArea! - area).abs() > 1e-9)) {
      out.add('${entry.key}: area is $actualArea, expected $area');
    }
  }
  return out;
}

Map<String, Object?> _expectedCells(String library) {
  final file = File(_expectedPathFor(library));
  expect(file.existsSync(), isTrue, reason: '${file.path} is missing');
  final json = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  return json['cells']! as Map<String, Object?>;
}

void main() {
  group('PDK libraries match the independent oracle', () {
    test('the corpus list and the fixture directory agree', () {
      final root = Directory(_pdkRoot);
      expect(root.existsSync(), isTrue, reason: '$_pdkRoot is missing');
      final onDisk = <String>[
        for (final entity in root.listSync(recursive: true))
          if (entity is File && entity.path.endsWith('.lib.gz'))
            p.posix.joinAll(p.split(p.relative(entity.path, from: _pdkRoot))),
      ]..sort();
      expect(onDisk, <String>[..._pdkLibraries]..sort());
    });

    for (final relative in _pdkLibraries) {
      test(relative, () {
        final path = p.join(_pdkRoot, relative);
        expect(File(path).existsSync(), isTrue, reason: '$path is missing');
        final library = LibertyParser.parseFile(path);
        final expected = _expectedCells(path);
        expect(library.cells, isNotEmpty);
        final differences = _differences(library, expected);
        expect(
          differences,
          isEmpty,
          reason:
              '${differences.length} of ${library.cells.length} cells differ '
              'from ${_expectedPathFor(path)}:\n${differences.join('\n')}',
        );
      });
    }

    test('sky130_fd_sc_hd draws 184 of its 428 cells as gates', () {
      final expected = _expectedCells(p.join(_pdkRoot, _pdkLibraries.first));
      final gates = expected.values
          .where((e) => (e! as Map<String, Object?>)['kind'] != 'box')
          .length;
      expect((gates, expected.length), (184, 428));
    });
  });

  test('the edge-case library matches its hand-written expectations', () {
    expect(File(_edgeCases).existsSync(), isTrue);
    final library = LibertyParser.parseFile(_edgeCases);
    final differences = _differences(library, _expectedCells(_edgeCases));
    expect(
      differences,
      isEmpty,
      reason:
          '${differences.length} of ${library.cells.length} edge cases '
          'differ:\n${differences.join('\n')}',
    );
  });
}
