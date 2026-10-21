// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The parity gate: the native engine must produce the same layout as elkjs
// for NetCrux's own inputs, coordinate for coordinate. Two forms, so the gate
// holds on every runner:
//
// - **Stored references.** `test/fixtures/layout/<scope>.elkjs.json.gz` is
//   elkjs's output for the ELK input `buildElkInput` makes of a committed
//   netlist fixture, with the input's hash beside it. Regenerate them on a
//   machine with a JavaScript engine (macOS) after any change to
//   `buildElkInput` or the vendored elkjs:
//
//       NETCRUX_WRITE_LAYOUT_REFERENCES=1 flutter test \
//         test/services/layout/native_elk_parity_test.dart
//
//   A stale reference fails, it does not skip: the hash check says so. The
//   browser build's WebAssembly engine is held to the same references by
//   `elk_wasm_web_test.dart`.
//
// - **Live comparison.** On macOS, where elkjs runs on JavaScriptCore under
//   `flutter test`, the same scopes are also solved by elkjs in-process and
//   compared directly, so a change to either engine shows up before anyone
//   regenerates anything. Elsewhere elkjs would run on the QuickJS
//   interpreter, which cannot finish these scopes (chain_1k overflows its
//   stack), so the live group is not registered there; `NETCRUX_PARITY_LIVE=1`
//   forces it. The large scopes join in with `NETCRUX_PARITY_LARGE=1`.
//
// Neither group registers a test it would only skip: the CI test-count guard
// caps skipped tests, and a skip here would hide a missing reference.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/services/layout/elk_layout_service.dart';
import 'package:netcrux/services/layout/flutter_js_host_vm.dart';
import 'package:netcrux/services/layout/native_elk_solver.dart';

import '../../helpers/elk_ffi_library_gate.dart';
import '../../helpers/layout_parity.dart';

const _referenceDir = 'test/fixtures/layout';

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
  final writeReferences =
      Platform.environment['NETCRUX_WRITE_LAYOUT_REFERENCES'] == '1';
  final includeLarge = Platform.environment['NETCRUX_PARITY_LARGE'] == '1';
  final liveComparison =
      Platform.isMacOS || Platform.environment['NETCRUX_PARITY_LIVE'] == '1';
  File referenceFor(LayoutParityScope scope) =>
      File('test/${scope.referencePath}');

  group('native engine matches the stored elkjs references', () {
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
              'the stored elkjs reference for ${scope.name} was made from a '
              'different ELK input; regenerate with '
              'NETCRUX_WRITE_LAYOUT_REFERENCES=1',
        );
        final expected = parseLayout(
          utf8.decode(gzip.decode(reference.readAsBytesSync())),
        );
        final solver = NativeElkSolver.open();
        addTearDown(solver.dispose);
        final actual = parseLayout(solver.solve(input));
        final diffs = layoutDifferences(actual, expected);
        expect(diffs, isEmpty, reason: diffs.take(8).join('\n'));
        // elkjs honours the fixed port sides too: the reference is evidence
        // about the browser fallback engine, which has no other gate here.
        final sides = portSideViolations(expected, input);
        expect(sides, isEmpty, reason: sides.take(8).join('\n'));
      });
    }
  });

  group('native engine matches elkjs live', () {
    if (!liveComparison) return;
    for (final scope in layoutParityScopes) {
      if (scope.large && !includeLarge) continue;
      test(scope.name, () {
        if (!requireElkFfiLibrary()) return;
        final input = _elkInputFor(scope);
        final ElkJsHost host;
        try {
          host = createDefaultElkJsHost();
          initElkRuntime(
            host,
            File('assets/elk/elk.bundled.js').readAsStringSync(),
          );
        } on Object catch (e) {
          markTestSkipped('no JavaScript engine for the live reference: $e');
          return;
        }
        addTearDown(host.dispose);
        final String jsResult;
        try {
          jsResult = runElkLayoutOnHost(host, input);
        } on LayoutException catch (e) {
          // An interpreter that cannot finish the scope is exactly what the
          // native engine replaces; it is not evidence about parity.
          markTestSkipped('elkjs could not lay out ${scope.name} here: $e');
          return;
        }
        if (writeReferences) {
          Directory(_referenceDir).createSync(recursive: true);
          final base =
              '$_referenceDir/${scope.name.replaceAll('/', '.')}.elkjs.json';
          File('$base.gz').writeAsBytesSync(gzip.encode(utf8.encode(jsResult)));
          File(
            '$base.gz.input',
          ).writeAsStringSync('${layoutInputFingerprint(input)}\n');
        }
        final solver = NativeElkSolver.open();
        addTearDown(solver.dispose);
        final actual = parseLayout(solver.solve(input));
        final diffs = layoutDifferences(actual, parseLayout(jsResult));
        expect(diffs, isEmpty, reason: diffs.take(8).join('\n'));
      }, timeout: const Timeout(Duration(minutes: 10)));
    }
  });
}
