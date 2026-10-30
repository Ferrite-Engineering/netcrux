// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/services/liberty/liberty_library.dart';
import 'package:netcrux/services/liberty/liberty_parser.dart';
import 'package:netcrux/services/verilog/native_netlist_reader.dart';
import 'package:path/path.dart' as p;

import '../support/netlist_equivalence.dart';
import '../support/yosys_reference_model.dart';

const _dir = 'test/fixtures/gate_level';

/// The `src` comparison this Yosys supports: every column from Yosys 0.60 on
/// (checked against 0.69), the start line before that, when older builds
/// numbered a few source ranges differently.
SrcComparison _srcComparison(String yosys) {
  final banner = Process.runSync(yosys, <String>['-V']).stdout as String;
  final match = RegExp(r'Yosys 0\.(\d+)').firstMatch(banner);
  final minor = match == null ? 0 : int.parse(match.group(1)!);
  return minor >= 60 ? SrcComparison.exact : SrcComparison.line;
}

/// Reads [sources] natively and through Yosys and expects the same design.
void _expectEquivalent({
  required List<String> sources,
  required String top,
  required String yosys,
  List<String> models = const <String>[],
  List<LibertyLibrary> libraries = const <LibertyLibrary>[],
}) {
  final scratch = Directory.systemTemp.createTempSync('native_vs_yosys');
  addTearDown(() => scratch.deleteSync(recursive: true));
  final outcome = readGateLevelNetlist(
    NativeReadRequest(
      sourceFiles: sources,
      cellModelFiles: models,
      libertyLibraries: libraries,
      topModule: top,
    ),
  );
  expect(
    outcome,
    isA<NativeReadSuccess>(),
    reason: outcome is NativeReadFallbackOutcome
        ? outcome.diagnosticLine
        : '$outcome',
  );
  final native = outcome! as NativeReadSuccess;
  final reference = yosysReferenceModel(
    sources: sources,
    cellModelFiles: models,
    libertyLibraries: libraries,
    scratch: scratch,
    top: top,
  );
  final differences = compareNetlists(
    native.model,
    reference.model,
    options: EquivalenceOptions(src: _srcComparison(yosys)),
  );
  expect(differences, isEmpty, reason: differences.join('\n'));
  expect(native.report, reference.report);
}

void main() {
  final yosys = findYosys();
  final skip = yosys == null ? 'yosys is not installed' : false;

  group('native reader against the Yosys route', () {
    final cases = <(String file, String top)>[
      ('awkward.v', 'top'),
      ('awkward.v', 'sub'),
      ('hierarchy.v', 'top2'),
      ('declarations.v', 'm3'),
      ('declarations.v', 'm4'),
      ('declarations.v', 'm5'),
    ];
    for (final (file, top) in cases) {
      test('$file with top $top', () {
        _expectEquivalent(
          sources: ['$_dir/$file'],
          models: ['$_dir/cell_models.v'],
          top: top,
          yosys: yosys!,
        );
      }, skip: skip);
    }
  });

  group('the same design written differently', () {
    String fixture(String name) => File('$_dir/$name').readAsStringSync();

    test('with Windows line endings and tab indentation', () {
      final scratch = Directory.systemTemp.createTempSync('native_style');
      addTearDown(() => scratch.deleteSync(recursive: true));
      final text = fixture(
        'awkward.v',
      ).replaceAll('\n  ', '\n\t').replaceAll('\n', '\r\n');
      final file = File('${scratch.path}/crlf.v')..writeAsStringSync(text);
      _expectEquivalent(
        sources: [file.path],
        models: ['$_dir/cell_models.v'],
        top: 'top',
        yosys: yosys!,
      );
    }, skip: skip);

    test('split over two files, a module before its use and one after', () {
      final scratch = Directory.systemTemp.createTempSync('native_split');
      addTearDown(() => scratch.deleteSync(recursive: true));
      final text = fixture('hierarchy.v');
      final cut = text.indexOf('module leafb');
      final first = File('${scratch.path}/a_top.v')
        ..writeAsStringSync(text.substring(0, cut));
      final second = File('${scratch.path}/b_leaf.v')
        ..writeAsStringSync(text.substring(cut));
      _expectEquivalent(
        sources: [first.path, second.path],
        models: ['$_dir/cell_models.v'],
        top: 'top2',
        yosys: yosys!,
      );
    }, skip: skip);

    test('a file name with a space and non-ASCII text in comments', () {
      final scratch = Directory.systemTemp.createTempSync('native_names');
      addTearDown(() => scratch.deleteSync(recursive: true));
      final file = File('${scratch.path}/my design.v')
        ..writeAsStringSync(
          '// caf\u00e9 \u00b5s\n${fixture('declarations.v')}',
        );
      _expectEquivalent(
        sources: [file.path],
        models: ['$_dir/cell_models.v'],
        top: 'm3',
        yosys: yosys!,
      );
    }, skip: skip);
  });

  group('the structural fixtures of the repository', () {
    test('a black-box prototype and the module that instantiates it', () {
      _expectEquivalent(
        sources: ['test/fixtures/mixed/top.v'],
        top: 'top',
        yosys: yosys!,
      );
    }, skip: skip);

    test('standard cells with power pins the library lacks, a macro nothing '
        'defines', () {
      const dir = 'test/fixtures/prebuilt/supply_pins';
      _expectEquivalent(
        sources: ['$dir/top.v'],
        libraries: [LibertyParser.parseFile('$dir/cells.lib')],
        top: 'top',
        yosys: yosys!,
      );
    }, skip: skip);
  });

  group('RTL fixtures are left to Yosys', () {
    // The reader never makes an RTL design worse than the Yosys route does:
    // each of these declines, naming the construct and the line.
    final rtl = <String>[
      ...Directory('test/fixtures/verilog')
          .listSync()
          .whereType<File>()
          .map((f) => f.path)
          .where((path) => path.endsWith('.v')),
      'test/fixtures/netlist/chain_1k/generated/chain_1k.v',
      'test/fixtures/netlist/design_seed/generated/design_seed.v',
      'test/fixtures/netlist/grid_100k/generated/grid_100k.v',
      'test/fixtures/netlist/picorv32/captured/picorv32.v',
      'test/fixtures/netlist/vexriscv/captured/vexriscv.v',
    ]..sort();
    for (final path in rtl) {
      test(p.basename(path), () {
        final outcome = readGateLevelNetlist(
          NativeReadRequest(sourceFiles: [path]),
        );
        expect(outcome, isA<NativeReadFallbackOutcome>());
        final declined = outcome! as NativeReadFallbackOutcome;
        expect(declined.path, path);
        expect(declined.line, greaterThan(0));
        expect(declined.message, isNot(startsWith('an internal error')));
        expect(declined.diagnosticLine, contains(':${declined.line}: Warning'));
      });
    }
  });

  group('generated netlists with the awkward forms', () {
    var haveGenerator = false;
    try {
      haveGenerator =
          Process.runSync('python3', <String>['--version']).exitCode == 0;
    } on ProcessException {
      // No python3 on this machine: the generated cases skip.
    }

    for (final seed in const [1, 2, 3]) {
      test('seed $seed', () {
        final scratch = Directory.systemTemp.createTempSync('native_gen');
        addTearDown(() => scratch.deleteSync(recursive: true));
        final d = scratch.path;
        final run = Process.runSync('python3', <String>[
          'tool/gen_gate_netlist.py',
          '--gates',
          '${4000 + seed * 1000}',
          '--awkward',
          '${300 + seed * 100}',
          '--seed',
          '$seed',
          '--out',
          '$d/g.v',
          '--lib-out',
          '$d/cells.lib',
          '--models-out',
          '$d/models.v',
        ]);
        expect(run.exitCode, 0, reason: '${run.stderr}');
        _expectEquivalent(
          sources: ['$d/g.v'],
          models: ['$d/models.v'],
          libraries: [LibertyParser.parseFile('$d/cells.lib')],
          top: 'top',
          yosys: yosys!,
        );
      }, skip: yosys == null ? skip : (haveGenerator ? false : 'no python3'));
    }
  });
}
