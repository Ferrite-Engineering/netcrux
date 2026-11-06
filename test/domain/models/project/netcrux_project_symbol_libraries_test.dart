// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/project/netcrux_project.dart';
import 'package:netcrux/features/project/providers/loaded_netlist_provider.dart';
import 'package:netcrux/services/project/netcrux_project_file.dart';
import 'package:netcrux/services/project/netcrux_project_path_resolver.dart';
import 'package:path/path.dart' as p;

/// The `symbolLibraries` key: NetCrux Pro draws cells from the libraries it
/// names; the open core reads it, anchors it and writes it back unchanged,
/// and nothing it builds for the design depends on it.
void main() {
  group('NetcruxProject.symbolLibraries', () {
    test('defaults to nothing and takes part in equality', () {
      final plain = NetcruxProject.create(sourceFiles: const <String>['a.v']);
      expect(plain.symbolLibraries, isEmpty);
      expect(NetcruxProject.empty.symbolLibraries, isEmpty);
      final withLibraries = plain.copyWith(
        symbolLibraries: const <String>['symbols/cells.sym'],
      );
      expect(withLibraries, isNot(plain));
      expect(withLibraries.hashCode, isNot(plain.hashCode));
      expect(withLibraries.copyWith(topModule: 't').symbolLibraries, <String>[
        'symbols/cells.sym',
      ]);
    });

    test('does not change the elaboration request', () {
      // The open core draws nothing from the key, so the design it elaborates
      // and the cache key it elaborates under stay the same.
      final plain = NetcruxProject.create(sourceFiles: const <String>['a.v']);
      final withLibraries = plain.copyWith(
        symbolLibraries: const <String>['symbols'],
      );
      expect(
        LoadedNetlist.buildRequest(withLibraries),
        LoadedNetlist.buildRequest(plain),
      );
    });
  });

  group('project file', () {
    const reader = NetcruxProjectFileReader();
    const writer = NetcruxProjectFileWriter();

    test('round-trips the key in order', () {
      final project = NetcruxProject.create(
        sourceFiles: const <String>['top.v'],
        symbolLibraries: const <String>['symbols', 'extra/late.symlib'],
      );
      final json = writer.toJson(project);
      expect(json['symbolLibraries'], <String>['symbols', 'extra/late.symlib']);
      expect(reader.fromJson(json), project);
    });

    test('is left out of a project without libraries', () {
      final json = writer.toJson(
        NetcruxProject.create(sourceFiles: const <String>['top.v']),
      );
      expect(json.containsKey('symbolLibraries'), isFalse);
    });

    test('a file written before the key reads with none, and a non-string '
        'entry is dropped', () {
      final plain = reader.fromJson(<String, Object?>{
        'version': 1,
        'sourceFiles': <String>['a.v'],
      });
      expect(plain.symbolLibraries, isEmpty);
      final odd = reader.fromJson(<String, Object?>{
        'version': 1,
        'sourceFiles': <String>['a.v'],
        'symbolLibraries': <Object?>['ok.sym', 3, null],
      });
      expect(odd.symbolLibraries, <String>['ok.sym']);
    });
  });

  group('path anchoring', () {
    final styles = <String, ({p.Context context, String dir})>{
      'posix': (context: p.posix, dir: '/tmp/designs/cpu'),
      'windows': (context: p.windows, dir: r'C:\tmp\designs\cpu'),
    };
    for (final MapEntry(key: name, value: style) in styles.entries) {
      test('entries resolve against the project folder and relativize back '
          '($name)', () {
        final c = style.context;
        final dir = style.dir;
        final project = NetcruxProject.create(
          sourceFiles: const <String>['top.v'],
          symbolLibraries: const <String>['symbols', '../shared/cells.sym'],
        );
        final resolved = resolveProjectPaths(project, dir, pathContext: c);
        expect(resolved.symbolLibraries, <String>[
          c.join(dir, 'symbols'),
          c.normalize(c.join(dir, '..', 'shared', 'cells.sym')),
        ]);
        final back = relativizeProjectPaths(resolved, dir, pathContext: c);
        expect(back.symbolLibraries, <String>[
          'symbols',
          '../shared/cells.sym',
        ]);
      });
    }
  });
}
