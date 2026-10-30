// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The web layout engine is four files in three languages that name each
// other by string: the Rust export, the worker that imports the wasm-bindgen
// glue and calls the export, the Dart solver that starts the worker by path,
// and the build tool and workflows that put the artefacts where the worker
// looks. None of those links is checked by a compiler, and a broken one does
// not fail loudly: the viewer quietly lays out on the elkjs fallback. This
// pins every link.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) {
  final file = File(path);
  expect(file.existsSync(), isTrue, reason: '$path is missing');
  return file.readAsStringSync();
}

void main() {
  test('the Rust crate exports the function the worker calls', () {
    expect(
      _read('native/elk_wasm/src/lib.rs'),
      contains('#[wasm_bindgen(js_name = layoutJson)]'),
    );
    final worker = _read('web/wasm/elk_wasm_worker.js');
    expect(worker, contains("import('./elk_wasm.js')"));
    expect(worker, contains("'./elk_wasm_bg.wasm'"));
    expect(worker, contains('glue.layoutJson'));
  });

  test('the worker can be composed into one module with the glue', () {
    // An editor webview cannot start a worker from its resource origin, so
    // the extension's page shim fetches the glue, the worker and the wasm, and
    // starts the worker from a blob that holds the glue's text, a definition of
    // `self.cruxLayoutHosted`, and the worker's script. That module must not
    // declare, at top level, a name the glue exports.
    final worker = _read('web/wasm/elk_wasm_worker.js');
    expect(worker, contains('self.cruxLayoutHosted'));
    expect(
      RegExp(
        r'^(?:let|const|var|function)\s+layoutJsonWithProgress\b',
        multiLine: true,
      ).hasMatch(worker),
      isFalse,
      reason: 'the glue exports layoutJsonWithProgress',
    );
    final solver = _read('lib/services/layout/elk_web_solver_web.dart');
    expect(solver, contains('kEditorHostLayoutWorkerGlobal'));
  });

  test('the solver starts the committed worker by its web path', () {
    final solver = _read('lib/services/layout/elk_web_solver_web.dart');
    final path = RegExp(
      "kElkWasmWorkerPath = '([^']+)'",
    ).firstMatch(solver)?.group(1);
    expect(path, 'wasm/elk_wasm_worker.js');
    expect(File('web/$path').existsSync(), isTrue);
    expect(solver, contains("_WorkerOptions(type: 'module')"));
  });

  test('the build tool writes the files the worker imports, untracked', () {
    final tool = _read('tool/build_web_wasm.dart');
    expect(tool, contains("'native/elk_wasm'"));
    expect(tool, contains("'web/wasm'"));
    expect(tool, contains("'elk_wasm.js'"));
    expect(tool, contains("'elk_wasm_bg.wasm'"));
    final ignored = _read('.gitignore').split('\n').map((l) => l.trim());
    expect(
      ignored,
      containsAll(<String>[
        'web/wasm/elk_wasm.js',
        'web/wasm/elk_wasm_bg.wasm',
        'native/elk_wasm/pkg/',
        'test/.web_wasm/',
      ]),
    );
  });

  test('CI builds the engine before the browser tests and the web build', () {
    final ci = _read('.github/workflows/ci.yml');
    final build = ci.indexOf('run: dart run tool/build_web_wasm.dart');
    expect(build, isNonNegative, reason: 'ci.yml never builds the engine');
    expect(ci.indexOf('run: tool/run_web_tests.sh'), greaterThan(build));
    expect(ci.indexOf('run: flutter build web --release'), greaterThan(build));
    expect(ci, contains('test -f build/web/wasm/elk_wasm_bg.wasm'));

    final deploy = _read('.github/workflows/web-deploy.yml');
    final deployBuild = deploy.indexOf(
      'run: dart run tool/build_web_wasm.dart',
    );
    expect(deployBuild, isNonNegative);
    expect(deploy.indexOf('flutter build web'), greaterThan(deployBuild));
    expect(deploy, contains('test -f build/web/wasm/elk_wasm_bg.wasm'));

    final script = _read('scripts/deploy_web.sh');
    expect(
      script.indexOf('dart run tool/build_web_wasm.dart'),
      lessThan(script.indexOf('flutter build web --release')),
    );
  });

  test('the browser tests load the engine where the runner stages it', () {
    final runner = _read('tool/run_web_tests.sh');
    expect(runner, contains('test/.web_wasm/'));
    expect(runner, contains('test/.web_wasm/no_module/'));
    final webTest = _read('test/services/layout/elk_wasm_web_test.dart');
    expect(webTest, contains("'/.web_wasm/elk_wasm_worker.js'"));
    expect(webTest, contains("'/.web_wasm/no_module/elk_wasm_worker.js'"));
  });
}
