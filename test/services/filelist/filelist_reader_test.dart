// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/services/filelist/filelist_reader.dart';
import 'package:path/path.dart' as p;

void main() {
  group('FilelistReader', () {
    const reader = FilelistReader();

    String fixturePath(String name) => p.join(
      Directory.current.path,
      'test',
      'fixtures',
      'filelist',
      name,
    );

    test('reads a simple flat filelist', () async {
      final contents = await reader.read(fixturePath('simple.f'));
      expect(contents.sourceFiles.length, 2);
      expect(p.basename(contents.sourceFiles[0]), 'cpu.v');
      expect(p.basename(contents.sourceFiles[1]), 'alu.v');
      expect(contents.defines, <String, String>{
        'WIDTH': '32',
        'DEBUG': '',
      });
      expect(contents.includePaths.length, 1);
      expect(p.basename(contents.includePaths.single), 'inc');
    });

    test('recursively expands nested -f', () async {
      final contents = await reader.read(fixturePath('parent.f'));
      final names = contents.sourceFiles.map(p.basename).toList();
      expect(names, <String>[
        'parent_top.v',
        'nested_a.v',
        'nested_b.v',
      ]);
      expect(contents.defines, <String, String>{
        'NESTED': 'on',
        'TOP': '1',
      });
      expect(contents.includePaths.length, 1);
      expect(p.basename(contents.includePaths.single), 'nested_inc');
    });

    test('detects cycles between mutually-referencing filelists', () async {
      await expectLater(
        () => reader.read(fixturePath('cycle_a.f')),
        throwsA(isA<FilelistCycleException>()),
      );
    });

    test('expands environment variables from override', () async {
      const reader = FilelistReader(
        environmentOverride: <String, String>{
          'REPO_ROOT': '/repo',
          'REV': '42',
        },
      );
      final contents = await reader.read(fixturePath('with_env.f'));
      expect(
        contents.sourceFiles.single.endsWith(p.join('repo', 'cpu.v')),
        isTrue,
        reason: r'sources should expand $REPO_ROOT relative to the FS',
      );
      expect(contents.defines, <String, String>{'REV': '42'});
      expect(
        contents.includePaths.single.endsWith(p.join('repo', 'inc')),
        isTrue,
      );
    });

    test('unset env vars expand to empty string', () async {
      const reader = FilelistReader(
        environmentOverride: <String, String>{},
      );
      final contents = await reader.read(fixturePath('with_env.f'));
      // REV is unset → empty value.
      expect(contents.defines, <String, String>{'REV': ''});
    });

    test('strips // and # comments', () async {
      final dir = await Directory.systemTemp.createTemp('netcrux_filelist_');
      try {
        final path = p.join(dir.path, 'commented.f');
        await File(path).writeAsString(
          '// leading comment\n'
          'cpu.v // trailing\n'
          '# also a comment\n'
          'alu.v\n',
        );
        final contents = await reader.read(path);
        expect(contents.sourceFiles.map(p.basename), <String>[
          'cpu.v',
          'alu.v',
        ]);
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test(
      'toProject materialises a NetcruxProject with the right shape',
      () async {
        final contents = await reader.read(fixturePath('simple.f'));
        final project = reader.toProject(contents);
        expect(project.sourceFiles, contents.sourceFiles);
        expect(project.defines, contents.defines);
        expect(project.includePaths, contents.includePaths);
      },
    );

    test('chained +define+ segments on one token', () async {
      final dir = await Directory.systemTemp.createTemp('netcrux_filelist_');
      try {
        final path = p.join(dir.path, 'chained.f');
        await File(path).writeAsString(
          'cpu.v\n'
          '+define+A=1+define+B+define+C=hello\n',
        );
        final contents = await reader.read(path);
        expect(contents.defines, <String, String>{
          'A': '1',
          'B': '',
          'C': 'hello',
        });
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('unknown bare flags are silently dropped (forward compat)', () async {
      // The reader can't know whether an unknown `-foo` takes an
      // argument (Vivado's `-sv` doesn't; `-f` does). We document the
      // safe behaviour: drop the flag itself but treat the next token
      // as a source. Users who need richer argument semantics should
      // file an issue with the flag name so we can table it.
      final dir = await Directory.systemTemp.createTemp('netcrux_filelist_');
      try {
        final path = p.join(dir.path, 'unknown.f');
        await File(path).writeAsString(
          '-sv\n'
          'cpu.v\n'
          'alu.v\n',
        );
        final contents = await reader.read(path);
        expect(contents.sourceFiles.map(p.basename), <String>[
          'cpu.v',
          'alu.v',
        ]);
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('missing nested -f surfaces FilelistNotFoundException', () async {
      final dir = await Directory.systemTemp.createTemp('netcrux_filelist_');
      try {
        final path = p.join(dir.path, 'with_missing.f');
        await File(path).writeAsString('-f nonexistent.f\n');
        await expectLater(
          () => reader.read(path),
          throwsA(isA<FilelistNotFoundException>()),
        );
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });
}
