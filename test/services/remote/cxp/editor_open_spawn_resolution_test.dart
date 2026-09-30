// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Windows `CreateProcess` searches the *calling* process's current
// directory before PATH. NetCrux never moves its own CWD, so a developer
// who launched it from a terminal inside a repository hands a `code.exe`
// committed to that repository priority over every copy on PATH. The editor
// spawn resolves through crux_io's `SpawnHost` before it starts anything:
// a bare name becomes the absolute PATH hit, and a name PATH does not answer
// to is refused rather than handed on bare.
//
// These run on the macOS and Linux boxes: a Windows `SpawnHost` with an
// injected `exists` probe makes the Windows branch host-independent, so the
// guard is not gated behind the weekly Windows job. Nothing is spawned — the
// launch is a recorder.
//
// MUTATION: resolving with `resolveExecutable` (which hands an unmatched
// name on bare) instead of `requireExecutable` makes the "not on PATH" test
// red; dropping the resolution makes the first two red.

import 'dart:io';

import 'package:crux_io/crux_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/services/remote/cxp/editor_open_service.dart';

void main() {
  const path = r'C:\rtl-repo;C:\Program Files\Microsoft VS Code\bin;C:\Windows';

  SpawnHost windows(Set<String> present) => SpawnHost(
    windows: true,
    environment: const <String, String>{'PATH': path},
    exists: present.contains,
  );

  /// The editor service over a resolving runner whose launch only records.
  ({List<String> launched, EditorOpenService service}) editor(SpawnHost host) {
    final launched = <String>[];
    return (
      launched: launched,
      service: EditorOpenService(
        processRunner: resolvingProcessRunner((exe, args) async {
          launched.add(exe);
          return ProcessResult(0, 0, '', '');
        }, host: host),
      ),
    );
  }

  Future<EditorOpenResult> open(EditorOpenService service, String template) =>
      service.openSourceLocation(
        commandTemplate: template,
        filePath: r'C:\rtl\cpu.v',
        line: 42,
      );

  test('a bare editor name launches the absolute PATH hit', () async {
    final e = editor(
      windows(<String>{r'C:\Program Files\Microsoft VS Code\bin\code.CMD'}),
    );
    expect((await open(e.service, 'code -g {file}:{line}')).honored, isTrue);
    expect(e.launched, <String>[
      r'C:\Program Files\Microsoft VS Code\bin\code.CMD',
    ]);
  });

  // The bug itself: the planted copy sits in the project directory, which is
  // the launching shell's CWD and need not be on PATH at all. Handed an
  // absolute path, CreateProcess never searches the CWD.
  test('a planted binary in the CWD cannot displace the PATH copy', () async {
    final e = editor(windows(<String>{r'C:\Windows\vim.EXE'}));
    await open(e.service, 'vim +{line} {file}');
    expect(e.launched, <String>[r'C:\Windows\vim.EXE']);
  });

  test('a name not on PATH starts nothing and says why', () async {
    final e = editor(windows(const <String>{}));
    final result = await open(e.service, 'helix {file}:{line}');
    expect(result.honored, isFalse);
    expect(result.reason, 'Failed to launch "helix": not found on PATH');
    expect(e.launched, isEmpty);
  });

  test('an explicit path is launched as written', () async {
    const custom = r'D:\tools\emacsclient.exe';
    final e = editor(windows(const <String>{custom}));
    await open(e.service, '$custom +{line} {file}');
    expect(e.launched, <String>[custom]);
  });

  test('POSIX is left alone — execvp never consults the CWD', () async {
    final e = editor(
      SpawnHost(
        windows: false,
        environment: const <String, String>{'PATH': '/opt/homebrew/bin'},
        exists: (_) => true,
      ),
    );
    await open(e.service, 'code -g {file}:{line}');
    expect(e.launched, <String>['code']);
  });
}
