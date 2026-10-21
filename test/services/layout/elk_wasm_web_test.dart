// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The web viewer's layout engine in a real browser (`tool/run_web_tests.sh`,
// which stages the built engine into `test/.web_wasm/`, the only place the
// browser test server can serve it from):
//
// - the elkrs port as WebAssembly, in its Web Worker, matches the stored
//   elkjs references the desktop gate (`native_elk_parity_test.dart`) holds
//   the native engine to;
// - the solve runs off the page, so the page keeps running and cancel
//   returns at once, terminating the worker;
// - a module that cannot load falls back to elkjs, and says so.
//
// A missing staged engine or fixture fails here; nothing skips.
@TestOn('browser')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/services/layout/elk_layout_service.dart';
import 'package:netcrux/services/layout/elk_web_solver_web.dart';

import '../../helpers/layout_parity.dart';

const _worker = '/.web_wasm/elk_wasm_worker.js';

// ── fetch + gunzip through the browser ──────────────────────────────────────

@JS('fetch')
external JSPromise<_Response> _fetch(JSString url);

@JS('Response')
extension type _Response._(JSObject _) implements JSObject {
  external factory _Response(_Stream body);
  external bool get ok;
  external int get status;
  external _Stream get body;
  external JSPromise<JSString> text();
}

extension type _Stream._(JSObject _) implements JSObject {
  external _Stream pipeThrough(JSObject transform);
}

@JS('DecompressionStream')
extension type _Gunzip._(JSObject _) implements JSObject {
  external factory _Gunzip(String format);
}

/// The text of the file at [path] under `test/`, gunzipped when it ends in
/// `.gz`. A missing file fails the test.
Future<String> _read(String path) async {
  final response = await _fetch('/$path'.toJS).toDart;
  expect(response.ok, isTrue, reason: '$path: HTTP ${response.status}');
  if (!path.endsWith('.gz')) return (await response.text().toDart).toDart;
  final inflated = _Response(response.body.pipeThrough(_Gunzip('gzip')));
  return (await inflated.text().toDart).toDart;
}

Future<String> _inputFor(LayoutParityScope scope) async => elkInputForModule(
  await _read('fixtures/netlist/${scope.fixture}'),
  scope.module,
);

Future<String> _noElkjs() async =>
    throw StateError('the wasm engine loaded; elkjs must not be read');

/// A stand-in for the elkjs bundle: defines `ELK` with a `layout` that
/// resolves to a marker document, so a test can tell the fallback ran.
const String _fakeElkjs = '''
globalThis.ELK = function () {
  this.layout = function (graph) {
    return Promise.resolve({id: 'elkjs-fallback', children: []});
  };
};
''';

const String _tiny =
    '{"id":"root","layoutOptions":{"elk.algorithm":"layered"},'
    '"children":[{"id":"a","width":10,"height":10},'
    '{"id":"b","width":10,"height":10}],'
    '"edges":[{"id":"e","sources":["a"],"targets":["b"]}]}';

void main() {
  final logs = <String>[];

  void useWorker(String url) {
    logs.clear();
    debugConfigureElkWebSolver(workerUrl: url, log: logs.add);
  }

  tearDown(debugResetElkWebSolver);

  group('wasm engine matches the stored elkjs references', () {
    setUpAll(() => useWorker(_worker));

    for (final scope in layoutParityScopes.where((s) => !s.large)) {
      test(scope.name, () async {
        final input = await _inputFor(scope);
        expect(
          (await _read('${scope.referencePath}.input')).trim(),
          layoutInputFingerprint(input),
          reason: 'the stored elkjs reference for ${scope.name} is stale',
        );
        final expected = parseLayout(await _read(scope.referencePath));
        final actual = parseLayout(await solveElkOnWeb(input, _noElkjs));
        expect(await debugElkWebEngine, ElkWebEngine.wasm);
        // Exact: the port reproduces elkjs's doubles, and wasm computes the
        // same IEEE-754 results as the desktop build.
        final diffs = layoutDifferences(actual, expected, tolerance: 0);
        expect(diffs, isEmpty, reason: diffs.take(8).join('\n'));
        expect(logs, isEmpty);
      }, timeout: const Timeout(Duration(minutes: 2)));
    }
  });

  // No stored reference for these (the desktop gate compares them live with
  // NETCRUX_PARITY_LARGE=1); here they prove the worker's stack holds the
  // deepest walks a real netlist makes, and the fixed port sides hold.
  group('large scopes lay out in the worker', () {
    setUpAll(() => useWorker(_worker));

    for (final scope in layoutParityScopes.where((s) => s.large)) {
      test(scope.name, () async {
        final input = await _inputFor(scope);
        final layout = parseLayout(await solveElkOnWeb(input, _noElkjs));
        final cells = (jsonDecode(input) as Map<String, Object?>)['children']!;
        expect(layout.nodes, hasLength((cells as List<Object?>).length));
        final sides = portSideViolations(layout, input);
        expect(sides, isEmpty, reason: sides.take(8).join('\n'));
        expect(logs, isEmpty);
      }, timeout: const Timeout(Duration(minutes: 2)));
    }
  });

  group('the wasm engine in its worker', () {
    setUp(() => useWorker(_worker));

    test('runs off the page, and cancel returns at once', () async {
      final netlist = NetlistModel.fromJson(
        jsonDecode(
              await _read(
                'fixtures/netlist/vexriscv/captured/vexriscv.netlist.json.gz',
              ),
            )
            as Map<String, Object?>,
      );
      final service = ElkLayoutService();
      final solve = service.layout(netlist.modules['VexRiscv']!);
      final failure = expectLater(
        solve,
        throwsA(
          isA<LayoutException>().having(
            (e) => e.message,
            'message',
            contains('cancelled'),
          ),
        ),
      );
      // The page keeps ticking while the worker solves: a solve on the page
      // would hold every timer until it finished.
      var ticks = 0;
      final ticker = Timer.periodic(
        const Duration(milliseconds: 10),
        (_) => ticks++,
      );
      // The first solve starts the worker and loads the module first.
      final started = DateTime.now();
      while (!service.hasLayoutInFlight) {
        expect(
          DateTime.now().difference(started),
          lessThan(const Duration(seconds: 30)),
          reason: 'the solve never reached the worker',
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
      ticker.cancel();
      expect(
        service.hasLayoutInFlight,
        isTrue,
        reason: 'VexRiscv takes seconds',
      );
      expect(ticks, greaterThan(10));

      final cancelledAt = DateTime.now();
      service.cancelInFlightLayout();
      await failure;
      expect(
        DateTime.now().difference(cancelledAt),
        lessThan(const Duration(milliseconds: 500)),
      );
      expect(service.hasLayoutInFlight, isFalse);

      // A fresh worker serves the next solve.
      final again = await solveElkOnWeb(_tiny, _noElkjs);
      expect(parseLayout(again).nodes, hasLength(2));
      expect(logs, isEmpty);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('a solve past its timeout terminates the worker', () async {
      final input = await _inputFor(layoutParityScopes.last);
      await expectLater(
        solveElkOnWeb(
          input,
          _noElkjs,
          timeout: const Duration(milliseconds: 200),
        ),
        throwsA(
          isA<LayoutException>().having(
            (e) => e.message,
            'message',
            contains('timed out'),
          ),
        ),
      );
      expect(elkWebLayoutInFlight, isFalse);
      expect(
        parseLayout(await solveElkOnWeb(_tiny, _noElkjs)).nodes,
        hasLength(2),
      );
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('a rejected input is a LayoutException, not a fallback', () async {
      await expectLater(
        solveElkOnWeb('{ not json', _noElkjs),
        throwsA(
          isA<LayoutException>().having(
            (e) => e.message,
            'message',
            contains('rejected'),
          ),
        ),
      );
      expect(
        parseLayout(await solveElkOnWeb(_tiny, _noElkjs)).nodes,
        hasLength(2),
      );
      expect(await debugElkWebEngine, ElkWebEngine.wasm);
      expect(logs, isEmpty);
    });
  });

  group('falls back to elkjs only when the module cannot load', () {
    for (final (what, url) in const <(String, String)>[
      ('the worker script is missing', '/.web_wasm/missing/elk_wasm_worker.js'),
      ('the wasm module is missing', '/.web_wasm/no_module/elk_wasm_worker.js'),
    ]) {
      test(what, () async {
        useWorker(url);
        final result = await solveElkOnWeb(_tiny, () async => _fakeElkjs);
        expect(result, contains('elkjs-fallback'));
        expect(await debugElkWebEngine, ElkWebEngine.elkjs);
        expect(logs, hasLength(1));
        expect(logs.single, contains('falling back to elkjs'));
        // Decided once: the next solve goes straight to elkjs, unlogged.
        await solveElkOnWeb(_tiny, () async => _fakeElkjs);
        expect(logs, hasLength(1));
      });
    }
  });
}
