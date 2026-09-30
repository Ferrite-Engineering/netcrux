// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/enums/netcrux_source_language.dart';
import 'package:netcrux/domain/models/project/netcrux_project.dart';
import 'package:netcrux/services/project/netcrux_project_file.dart';
import 'package:path/path.dart' as p;

void main() {
  group('NetcruxProjectFileReader', () {
    const reader = NetcruxProjectFileReader();

    test('round-trips through serialise', () {
      const writer = NetcruxProjectFileWriter();
      final project = NetcruxProject.create(
        sourceFiles: const <String>['cpu.v', 'alu.v'],
        topModule: 'top',
        defines: const <String, String>{'WIDTH': '32', 'FAST': ''},
        includePaths: const <String>['inc', 'src/include'],
        extraYosysCommands: const <String>['proc', 'opt'],
        lowerToStructural: true,
      );
      final json = writer.serialise(project);
      final back = reader.parse(json);
      expect(back, project);
    });

    test('reads the committed golden fixture', () async {
      final path = p.join(
        Directory.current.path,
        'test',
        'fixtures',
        'project',
        'golden_v1.netcrux-project',
      );
      final project = await reader.read(path);
      expect(project.version, kNetcruxProjectVersion);
      expect(project.sourceFiles, <String>['cpu.v', 'alu.v']);
      expect(project.topModule, 'cpu');
      expect(project.defines, <String, String>{'WIDTH': '32', 'DEBUG': ''});
      expect(project.includePaths, <String>['inc']);
      expect(project.extraYosysCommands, <String>['proc', 'opt']);
      expect(project.lowerToStructural, isTrue);
    });

    test('ignores unknown fields (forward compatibility)', () {
      const json = '''
{
  "version": 1,
  "sourceFiles": ["a.v"],
  "topModule": "top",
  "defines": {},
  "includePaths": [],
  "extraYosysCommands": [],
  "lowerToStructural": false,
  "fromTheFuture": "ignore me",
  "alsoFromTheFuture": 42
}
''';
      final project = reader.parse(json);
      expect(project.sourceFiles, <String>['a.v']);
      expect(project.topModule, 'top');
    });

    test('missing optional fields fall back to defaults', () {
      const json = '''
{
  "version": 1,
  "sourceFiles": ["a.v"]
}
''';
      final project = reader.parse(json);
      expect(project.sourceFiles, <String>['a.v']);
      expect(project.topModule, '');
      expect(project.defines, isEmpty);
      expect(project.includePaths, isEmpty);
      expect(project.extraYosysCommands, isEmpty);
      expect(project.lowerToStructural, isFalse);
    });

    test('rejects an unknown version', () {
      const json = '''
{
  "version": 999,
  "sourceFiles": []
}
''';
      expect(
        () => reader.parse(json),
        throwsA(
          isA<NetcruxProjectVersionException>().having(
            (e) => e.version,
            'version',
            999,
          ),
        ),
      );
    });

    test('rejects malformed JSON', () {
      expect(
        () => reader.parse('{ not json'),
        throwsA(isA<NetcruxProjectFormatException>()),
      );
    });

    test('rejects a non-object root', () {
      expect(
        () => reader.parse('[]'),
        throwsA(isA<NetcruxProjectFormatException>()),
      );
    });

    test('rejects a missing version field', () {
      expect(
        () => reader.parse('{"sourceFiles": []}'),
        throwsA(isA<NetcruxProjectFormatException>()),
      );
    });

    test('non-string elements in arrays are filtered out', () {
      const json = '''
{
  "version": 1,
  "sourceFiles": ["a.v", 42, null, "b.v"],
  "includePaths": [true, "ok"]
}
''';
      final project = reader.parse(json);
      expect(project.sourceFiles, <String>['a.v', 'b.v']);
      expect(project.includePaths, <String>['ok']);
    });
  });

  group('NetcruxProjectFileReader extraYosysCommands allow-list', () {
    const reader = NetcruxProjectFileReader();

    String projectWithCommands(List<String> commands) {
      final encoded = commands.map((c) => '"${c.replaceAll('"', r'\"')}"');
      return '''
{
  "version": 1,
  "sourceFiles": ["a.v"],
  "topModule": "top",
  "extraYosysCommands": [${encoded.join(', ')}]
}
''';
    }

    test('allows the documented safe passes', () {
      final project = reader.parse(
        projectWithCommands(<String>['proc', 'opt', 'opt_clean', 'flatten']),
      );
      expect(
        project.extraYosysCommands,
        <String>['proc', 'opt', 'opt_clean', 'flatten'],
      );
    });

    test('allows a safe pass carrying options', () {
      // Options ride along — every allow-listed command is safe under any
      // of its flags, and the name is what is matched.
      final project = reader.parse(
        projectWithCommands(<String>['opt -full', 'hierarchy -check']),
      );
      expect(
        project.extraYosysCommands,
        <String>['opt -full', 'hierarchy -check'],
      );
    });

    test('refuses exec, naming the offending command', () {
      expect(
        () => reader.parse(
          projectWithCommands(<String>['proc', 'exec -- touch /tmp/pwned']),
        ),
        throwsA(
          isA<NetcruxProjectUnsafeCommandException>()
              .having((e) => e.command, 'command', 'exec')
              .having((e) => e.message, 'message', contains('exec')),
        ),
      );
    });

    test('refuses the other code-execution and I/O commands', () {
      for (final unsafe in <String>[
        'shell',
        'tcl /tmp/x.tcl',
        'script /tmp/x.ys',
        'plugin -i /tmp/evil.so',
        'tee -o /tmp/x cat',
        'write_json /tmp/out.json',
        'read_verilog /etc/passwd',
        'setenv LD_PRELOAD /tmp/evil.so',
      ]) {
        final expectedName = unsafe.split(' ').first;
        expect(
          () => reader.parse(projectWithCommands(<String>[unsafe])),
          throwsA(
            isA<NetcruxProjectUnsafeCommandException>().having(
              (e) => e.command,
              'command for "$unsafe"',
              expectedName,
            ),
          ),
          reason: '"$unsafe" must be refused',
        );
      }
    });

    test('refuses a statement smuggled after a safe first token', () {
      // The runner joins entries with "; ", so a ";" inside one entry
      // would run a second, unvetted command. The whole entry is refused.
      expect(
        () => reader.parse(
          projectWithCommands(<String>['opt; exec -- touch /tmp/pwned']),
        ),
        throwsA(
          isA<NetcruxProjectUnsafeCommandException>().having(
            (e) => e.command,
            'command',
            'opt; exec -- touch /tmp/pwned',
          ),
        ),
      );
    });

    test('refuses a newline-smuggled statement', () {
      // Raw string: the `\n` is two JSON characters, which jsonDecode turns
      // into a real newline inside the command entry.
      const json = r'''
{
  "version": 1,
  "sourceFiles": ["a.v"],
  "extraYosysCommands": ["opt\nexec -- id"]
}
''';
      expect(
        () => reader.parse(json),
        throwsA(isA<NetcruxProjectUnsafeCommandException>()),
      );
    });

    test('refuses a blank command entry', () {
      expect(
        () => reader.parse(projectWithCommands(<String>['  '])),
        throwsA(isA<NetcruxProjectUnsafeCommandException>()),
      );
    });

    test('read() refuses an unsafe project file on disk', () async {
      final dir = await Directory.systemTemp.createTemp('netcrux_unsafe_');
      try {
        final path = p.join(dir.path, 'evil.netcrux-project');
        await File(path).writeAsString(
          projectWithCommands(<String>['exec -- touch /tmp/pwned']),
        );
        await expectLater(
          reader.read(path),
          throwsA(
            isA<NetcruxProjectUnsafeCommandException>().having(
              (e) => e.command,
              'command',
              'exec',
            ),
          ),
        );
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('allowUnsafeCommands bypasses the allow-list (trust seam)', () {
      // The seam a future workspace-trust decision flips: a trusted
      // project may carry its own passes. Default-off everywhere else.
      const trusting = NetcruxProjectFileReader(allowUnsafeCommands: true);
      final project = trusting.parse(
        projectWithCommands(<String>['exec -- echo hi']),
      );
      expect(project.extraYosysCommands, <String>['exec -- echo hi']);
    });
  });

  group('NetcruxProjectFileWriter', () {
    const writer = NetcruxProjectFileWriter();
    const reader = NetcruxProjectFileReader();

    test('writes atomically via temp file rename', () async {
      final dir = await Directory.systemTemp.createTemp('netcrux_proj_');
      try {
        final path = p.join(dir.path, 'project.netcrux-project');
        final project = NetcruxProject.create(
          sourceFiles: const <String>['cpu.v'],
          topModule: 'cpu',
        );
        await writer.write(path, project);
        final back = await reader.read(path);
        expect(back, project);
        expect(File('$path.tmp').existsSync(), isFalse);
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('emits a stable key ordering', () {
      final project = NetcruxProject.create(sourceFiles: const <String>['a.v']);
      final json = writer.serialise(project);
      // Spot-check the field order matches the writer's documented
      // contract; downstream tooling that diffs project files relies
      // on this stability.
      final versionIdx = json.indexOf('"version"');
      final sourcesIdx = json.indexOf('"sourceFiles"');
      final topIdx = json.indexOf('"topModule"');
      final lowerIdx = json.indexOf('"lowerToStructural"');
      expect(versionIdx, greaterThanOrEqualTo(0));
      expect(sourcesIdx, greaterThan(versionIdx));
      expect(topIdx, greaterThan(sourcesIdx));
      expect(lowerIdx, greaterThan(topIdx));
    });

    test('round-trips a project with per-file language overrides', () {
      const writer = NetcruxProjectFileWriter();
      final project = NetcruxProject.create(
        sourceFiles: const <String>['top.v', 'sub.vhd', 'legacy.v'],
        sourceFileLanguages: const <String, NetcruxSourceLanguage>{
          'sub.vhd': NetcruxSourceLanguage.vhdl,
          // Auto entries are dropped from the on-disk shape but
          // round-trip semantically equivalent to absent.
          'legacy.v': NetcruxSourceLanguage.systemVerilog,
        },
      );
      final json = writer.serialise(project);
      expect(json, contains('"sourceFileLanguages"'));
      expect(json, contains('"sub.vhd": "vhdl"'));
      expect(json, contains('"legacy.v": "systemverilog"'));
      final back = reader.parse(json);
      expect(
        back.sourceFileLanguages['sub.vhd'],
        NetcruxSourceLanguage.vhdl,
      );
      expect(
        back.sourceFileLanguages['legacy.v'],
        NetcruxSourceLanguage.systemVerilog,
      );
    });

    test('omits sourceFileLanguages when the map is empty', () {
      const writer = NetcruxProjectFileWriter();
      final project = NetcruxProject.create(sourceFiles: const <String>['a.v']);
      final json = writer.serialise(project);
      // Forward-compat: older readers shouldn't see a stray key.
      expect(json, isNot(contains('sourceFileLanguages')));
    });

    test('silently drops unknown language strings', () {
      // Forward-compat: a future "vhdl-2019" entry must not crash the
      // current reader. Paths with unknown values fall back to auto.
      const raw = '''
{
  "version": 1,
  "sourceFiles": ["a.vhd"],
  "topModule": "t",
  "sourceFileLanguages": {"a.vhd": "vhdl-2019-future"}
}
''';
      final project = reader.parse(raw);
      expect(project.sourceFileLanguages, isEmpty);
      // Auto-detection from the extension still classifies it as VHDL.
      expect(
        project.resolveLanguage('a.vhd'),
        NetcruxSourceLanguage.vhdl,
      );
    });
  });
}
