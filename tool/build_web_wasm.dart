// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Builds the web viewer's layout engine, `native/elk_wasm` (the vendored
// elkrs port compiled to WebAssembly), and copies it into `web/wasm/` beside
// the hand-written worker `elk_wasm_worker.js`, where `flutter build web`
// picks it up. The artefacts are build outputs and are not committed; CI runs
// this before the web tests and before every web build. Without them the web
// viewer still lays out, on the elkjs fallback, and says so on the console.
//
//   dart run tool/build_web_wasm.dart           # release build + size gate
//   dart run tool/build_web_wasm.dart --check   # size gate only, no build
//
// Prerequisites: `rustup target add wasm32-unknown-unknown` and wasm-pack
// (CI pins 0.13.1).
//
// Size gate: the gzipped `.wasm` must stay within [_maxGzippedBytes]. Every
// web user downloads it once before the first layout; raise the budget only
// deliberately.
//
// ignore_for_file: avoid_print

import 'dart:io';

const _crateDir = 'native/elk_wasm';
const _outDir = 'web/wasm';
const _artefacts = <String>['elk_wasm.js', 'elk_wasm_bg.wasm'];
const _maxGzippedBytes = 1310720; // 1.25 MiB

Future<int> main(List<String> args) async {
  if (!args.contains('--check')) {
    print('Building $_crateDir with wasm-pack...');
    final result = await Process.run('wasm-pack', <String>[
      'build',
      _crateDir,
      '--target',
      'web',
      '--release',
      '--no-typescript',
      '--no-pack',
    ], runInShell: Platform.isWindows);
    stdout.write(result.stdout);
    stderr.write(result.stderr);
    if (result.exitCode != 0) {
      stderr.writeln(
        'wasm-pack failed. Is the wasm32-unknown-unknown target installed '
        '(rustup target add wasm32-unknown-unknown)?',
      );
      return result.exitCode;
    }
    Directory(_outDir).createSync(recursive: true);
    for (final name in _artefacts) {
      final source = File('$_crateDir/pkg/$name');
      if (!source.existsSync()) {
        stderr.writeln('Expected artefact not found: ${source.path}');
        return 2;
      }
      source.copySync('$_outDir/$name');
      print('  copied $name to $_outDir/');
    }
  }

  final wasm = File('$_outDir/elk_wasm_bg.wasm');
  if (!wasm.existsSync()) {
    stderr.writeln('${wasm.path} is missing: run without --check first.');
    return 3;
  }
  final raw = wasm.readAsBytesSync();
  final gzipped = gzip.encode(raw).length;
  print(
    'elk_wasm_bg.wasm: ${raw.length} bytes, $gzipped gzipped '
    '(budget $_maxGzippedBytes gzipped)',
  );
  if (gzipped > _maxGzippedBytes) {
    stderr.writeln(
      'The layout engine is ${gzipped - _maxGzippedBytes} bytes over its '
      'gzipped budget.',
    );
    return 4;
  }
  return 0;
}
