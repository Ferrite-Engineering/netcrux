// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/enums/netcrux_source_language.dart';
import 'package:netcrux/domain/models/project/netcrux_project.dart';
import 'package:netcrux/services/project/netcrux_project_path_resolver.dart';
import 'package:path/path.dart' as p;

void main() {
  final projectDir = p.normalize(p.absolute(p.join('/tmp', 'designs', 'cpu')));

  NetcruxProject projectWith({
    List<String> sourceFiles = const <String>[],
    List<String> includePaths = const <String>[],
    Map<String, NetcruxSourceLanguage> languages =
        const <String, NetcruxSourceLanguage>{},
  }) => NetcruxProject.create(
    sourceFiles: sourceFiles,
    topModule: 'cpu',
    includePaths: includePaths,
    sourceFileLanguages: languages,
  );

  group('resolveProjectPaths', () {
    test('anchors relative source files to the project directory', () {
      final resolved = resolveProjectPaths(
        projectWith(sourceFiles: <String>['alu.v', 'rtl/regfile.v']),
        projectDir,
      );
      expect(resolved.sourceFiles, <String>[
        p.join(projectDir, 'alu.v'),
        p.join(projectDir, 'rtl', 'regfile.v'),
      ]);
    });

    test('collapses parent segments rather than passing them to Yosys', () {
      final resolved = resolveProjectPaths(
        projectWith(sourceFiles: <String>['../../test/fixtures/verilog/a.v']),
        projectDir,
      );
      expect(
        resolved.sourceFiles.single,
        p.normalize(p.absolute('/tmp/test/fixtures/verilog/a.v')),
      );
      expect(resolved.sourceFiles.single, isNot(contains('..')));
    });

    test('leaves absolute paths alone', () {
      // A project may legitimately point at a shared IP directory that
      // lives outside its own tree.
      final shared = p.normalize(p.absolute(p.join('/opt', 'ip', 'fifo.v')));
      final resolved = resolveProjectPaths(
        projectWith(sourceFiles: <String>[shared]),
        projectDir,
      );
      expect(resolved.sourceFiles.single, shared);
    });

    test('anchors include paths too', () {
      final resolved = resolveProjectPaths(
        projectWith(includePaths: <String>['inc']),
        projectDir,
      );
      expect(resolved.includePaths.single, p.join(projectDir, 'inc'));
    });

    test('rewrites language-override keys in step with the source list', () {
      // The overrides are keyed by the same strings that appear in
      // sourceFiles. Leaving the keys behind drops every override the
      // moment paths are anchored, sending VHDL through the Verilog
      // reader.
      final resolved = resolveProjectPaths(
        projectWith(
          sourceFiles: <String>['sub.vhd'],
          languages: <String, NetcruxSourceLanguage>{
            'sub.vhd': NetcruxSourceLanguage.vhdl,
          },
        ),
        projectDir,
      );
      final anchored = resolved.sourceFiles.single;
      expect(resolved.sourceFileLanguages, <String, NetcruxSourceLanguage>{
        anchored: NetcruxSourceLanguage.vhdl,
      });
      expect(resolved.resolveLanguage(anchored), NetcruxSourceLanguage.vhdl);
    });

    test('preserves the elaboration knobs it does not touch', () {
      final project = NetcruxProject.create(
        sourceFiles: const <String>['alu.v'],
        topModule: 'alu',
        defines: const <String, String>{'WIDTH': '32', 'DEBUG': ''},
        extraYosysCommands: const <String>['proc', 'opt'],
        lowerToStructural: true,
      );
      final resolved = resolveProjectPaths(project, projectDir);
      expect(resolved.topModule, 'alu');
      expect(resolved.defines, project.defines);
      expect(resolved.extraYosysCommands, project.extraYosysCommands);
      expect(resolved.lowerToStructural, isTrue);
      expect(resolved.version, project.version);
    });

    test('is idempotent — anchoring an anchored project is a no-op', () {
      final once = resolveProjectPaths(
        projectWith(sourceFiles: <String>['alu.v']),
        projectDir,
      );
      expect(resolveProjectPaths(once, projectDir), once);
    });

    // `p.canonicalize` lowercases on Windows. These strings are the source
    // list the user sees and the workspace saves, so a Windows project must
    // come back spelled as the user spelled it. The Windows path style is
    // passed in, so this holds on every host.
    //
    // MUTATION: resolving through `canonicalize` makes this red.
    test('keeps the case of a Windows path, anchored or absolute', () {
      const dir = r'C:\Users\Dev\Designs\CPU';
      final resolved = resolveProjectPaths(
        projectWith(
          sourceFiles: <String>[r'RTL\Top.v', r'D:\Shared\IP\Fifo.v'],
          includePaths: <String>[r'..\Inc'],
          languages: <String, NetcruxSourceLanguage>{
            r'RTL\Top.v': NetcruxSourceLanguage.verilog,
          },
        ),
        dir,
        pathContext: p.windows,
      );
      expect(resolved.sourceFiles, <String>[
        r'C:\Users\Dev\Designs\CPU\RTL\Top.v',
        r'D:\Shared\IP\Fifo.v',
      ]);
      expect(resolved.includePaths, <String>[r'C:\Users\Dev\Designs\Inc']);
      expect(resolved.sourceFileLanguages.keys, <String>[
        r'C:\Users\Dev\Designs\CPU\RTL\Top.v',
      ]);
    });

    test('handles a project with no paths at all', () {
      final resolved = resolveProjectPaths(projectWith(), projectDir);
      expect(resolved.sourceFiles, isEmpty);
      expect(resolved.includePaths, isEmpty);
    });
  });
}
