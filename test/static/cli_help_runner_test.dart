// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// `netcrux --help` must print and exit before the renderer and the engine
// start: on a machine with no display or no working OpenGL it is the one
// invocation that has to work, and a line from the renderer on stderr before
// the usage is a defect.
//
// A desktop runner creates its window and engine before Dart's `main` runs, so
// the answer has to come from the runner. Each runner's entry point checks for
// help first and prints a C++ copy of cliHelpText() from
// native/cli_help/netcrux_cli_help.h. This test keeps that copy identical to
// the Dart text, and keeps the check ahead of everything that starts a window,
// the engine, COM or GTK, on every platform (the runners themselves build on
// Linux and Windows only).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/services/cli/cli_args.dart';

String _read(String path) => File(path).readAsStringSync();

String _code(String source) => source
    .split('\n')
    .map((line) {
      final comment = line.indexOf('//');
      return comment < 0 ? line : line.substring(0, comment);
    })
    .join('\n');

const _open = 'R"NETCRUXHELP(';
const _close = ')NETCRUXHELP"';

void main() {
  final header = _read('native/cli_help/netcrux_cli_help.h');

  test('the runners print exactly what cliHelpText returns', () {
    final start = header.indexOf(_open);
    final end = header.indexOf(_close);
    expect(start, isNonNegative, reason: 'the help literal is missing');
    expect(end, greaterThan(start));
    final copy = header.substring(start + _open.length, end);
    expect(copy, cliHelpText());
  });

  test('the help text is ASCII, so any console code page prints it', () {
    for (final unit in cliHelpText().codeUnits) {
      expect(unit, lessThan(128), reason: 'non-ASCII code unit $unit');
    }
  });

  test('the Linux runner answers help before GTK or the engine exist', () {
    final main = _code(_read('linux/runner/main.cc'));
    final help = main.indexOf('NetCruxHelpRequested(');
    expect(help, isNonNegative, reason: 'main never checks for help');
    for (final started in const [
      'my_application_new(',
      'g_application_run(',
    ]) {
      final at = main.indexOf(started);
      expect(at, isNonNegative, reason: 'main no longer calls $started');
      expect(help, lessThan(at), reason: 'help is checked after $started');
    }
  });

  test(
    'the Windows runner answers help before COM, the window or the engine',
    () {
      final main = _code(_read('windows/runner/main.cpp'));
      final help = main.indexOf('NetCruxHelpRequested(');
      expect(help, isNonNegative, reason: 'main never checks for help');
      for (final started in const [
        'CoInitializeEx(',
        'flutter::DartProject',
        'FlutterWindow window',
        'window.Create(',
      ]) {
        final at = main.indexOf(started);
        expect(at, isNonNegative, reason: 'main no longer has $started');
        expect(help, lessThan(at), reason: 'help is checked after $started');
      }
    },
  );

  test('both runners can find the shared header', () {
    expect(
      _read('linux/runner/CMakeLists.txt'),
      contains('native/cli_help'),
    );
    expect(
      _read('windows/runner/CMakeLists.txt'),
      contains('native/cli_help'),
    );
  });

  test('bootstrap prints help before the single-instance claim or binding', () {
    // The Dart side is the fallback for an embedder without these runners; it
    // must still end before it touches the platform.
    final app = _code(_read('lib/app.dart'));
    final help = app.indexOf("argv.contains('--help')");
    expect(help, isNonNegative);
    for (final started in const [
      'claimSingleInstance(',
      'WidgetsFlutterBinding.ensureInitialized();',
    ]) {
      final at = app.indexOf(started);
      expect(at, isNonNegative, reason: 'bootstrap no longer calls $started');
      expect(help, lessThan(at), reason: 'help is checked after $started');
    }
  });
}
