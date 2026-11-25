// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The parity gate: the native engine must produce the same layout as the
// Eclipse Layout Kernel itself for NetCrux's own inputs, coordinate for
// coordinate.
//
// `test/fixtures/layout/<scope>.elkjs.json.gz` is the output of elkjs 0.9.3
// (the GWT build of the Java ELK, an engine NetCrux no longer ships) for the
// ELK input `buildElkInput` makes of a committed netlist fixture, with the
// input's hash beside it. The references come from outside the engine under
// test. After a change to `buildElkInput`, regenerate them with elkjs under
// Node, the way the vendored crate makes its own goldens:
//
//     NETCRUX_WRITE_LAYOUT_INPUTS=1 flutter test \
//       test/services/layout/native_elk_parity_test.dart
//     npm install --prefix <dir> elkjs@0.9.3
//     NODE_PATH=<dir>/node_modules node native/vendor/elkrs/tools/elkjs_layout.js \
//       build/layout-inputs/<scope>.json <scope>.elkjs.json ...
//
// then gzip each result into `test/fixtures/layout/`. The first step also
// writes each input's fingerprint (`<scope>.elkjs.json.gz.input`) there.
//
// A stale reference fails, it does not skip: the hash check says so. The
// browser build's WebAssembly engine is held to the same references by
// `elk_wasm_web_test.dart`. A scope without a stored reference has no test,
// not a skipped one: the CI test-count guard caps skipped tests, and a skip
// here would hide a missing reference.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/services/layout/native_elk_solver.dart';

import '../../helpers/elk_ffi_library_gate.dart';
import '../../helpers/layout_parity.dart';

const _referenceDir = 'test/fixtures/layout';
const _inputDir = 'build/layout-inputs';

String _elkInputFor(LayoutParityScope scope) {
  final bytes = File(
    'test/fixtures/netlist/${scope.fixture}',
  ).readAsBytesSync();
  final text = scope.fixture.endsWith('.gz')
      ? utf8.decode(gzip.decode(bytes))
      : utf8.decode(bytes);
  return elkInputForModule(text, scope.module);
}

void main() {
  final writeInputs =
      Platform.environment['NETCRUX_WRITE_LAYOUT_INPUTS'] == '1';
  File referenceFor(LayoutParityScope scope) =>
      File('test/${scope.referencePath}');

  if (writeInputs) {
    test('writes the ELK inputs and fingerprints for regeneration', () {
      Directory(_inputDir).createSync(recursive: true);
      for (final scope in layoutParityScopes.where((s) => !s.large)) {
        final input = _elkInputFor(scope);
        final name = scope.name.replaceAll('/', '.');
        File('$_inputDir/$name.json').writeAsStringSync(input);
        File(
          '$_referenceDir/$name.elkjs.json.gz.input',
        ).writeAsStringSync('${layoutInputFingerprint(input)}\n');
      }
    });
  }

  group('native engine matches the stored ELK references', () {
    for (final scope in layoutParityScopes) {
      final reference = referenceFor(scope);
      // A scope without a stored reference has no test, not a skipped one.
      if (!reference.existsSync()) continue;
      test(scope.name, () {
        if (!requireElkFfiLibrary()) return;
        final fingerprintFile = File('${reference.path}.input');
        final input = _elkInputFor(scope);
        expect(
          fingerprintFile.existsSync()
              ? fingerprintFile.readAsStringSync().trim()
              : '',
          layoutInputFingerprint(input),
          reason:
              'the stored ELK reference for ${scope.name} was made from a '
              'different ELK input; regenerate it (see the comment at the top '
              'of this file)',
        );
        final expected = parseLayout(
          utf8.decode(gzip.decode(reference.readAsBytesSync())),
        );
        final solver = NativeElkSolver.open();
        addTearDown(solver.dispose);
        final actual = parseLayout(solver.solve(input));
        final diffs = layoutDifferences(actual, expected);
        expect(diffs, isEmpty, reason: diffs.take(8).join('\n'));
        // The reference honours the fixed port sides too: evidence that the
        // expectation itself is a layout NetCrux would accept.
        final sides = portSideViolations(expected, input);
        expect(sides, isEmpty, reason: sides.take(8).join('\n'));
      });
    }
  });
}
