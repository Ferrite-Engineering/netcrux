// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/project/netcrux_project.dart';
import 'package:netcrux/domain/models/workspace/netcrux_tab_payload.dart';
import 'package:netcrux/services/filelist/filelist_reader.dart';
import 'package:netcrux/services/project/netcrux_project_file.dart';
import 'package:netcrux/services/project/netcrux_project_path_resolver.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_codec.dart';
import 'package:netcrux/services/yosys/elaboration_cache_service.dart';
import 'package:path/path.dart' as p;

/// The cell-library list, `NetcruxProject.libertyFiles`, through every place
/// a project travels: the model, the project file, path anchoring, filelist
/// import, the open-files split, the tab payload and the elaboration cache
/// key.
void main() {
  group('NetcruxProject.libertyFiles', () {
    test('defaults to empty and takes part in equality and hashing', () {
      final plain = NetcruxProject.create(sourceFiles: const <String>['a.v']);
      final withLib = NetcruxProject.create(
        sourceFiles: const <String>['a.v'],
        libertyFiles: const <String>['cells.lib'],
      );
      expect(plain.libertyFiles, isEmpty);
      expect(NetcruxProject.empty.libertyFiles, isEmpty);
      expect(withLib, isNot(plain));
      expect(withLib.copyWith(libertyFiles: const <String>[]), plain);
      expect(
        plain.copyWith(libertyFiles: const <String>['cells.lib']).hashCode,
        withLib.hashCode,
      );
      expect(() => withLib.libertyFiles.add('x'), throwsUnsupportedError);
      // copyWith without the field keeps it.
      expect(withLib.copyWith(topModule: 'top').libertyFiles, <String>[
        'cells.lib',
      ]);
    });

    test('isLibertyPath matches .lib and .liberty, any case', () {
      expect(NetcruxProject.isLibertyPath('/x/cells.lib'), isTrue);
      expect(NetcruxProject.isLibertyPath(r'C:\x\CELLS.LIB'), isTrue);
      expect(NetcruxProject.isLibertyPath('cells.liberty'), isTrue);
      expect(NetcruxProject.isLibertyPath('top.v'), isFalse);
      expect(NetcruxProject.isLibertyPath('mylib.sv'), isFalse);
    });

    test('fromOpenedFiles splits sources from cell libraries in order', () {
      final project = NetcruxProject.fromOpenedFiles(const <String>[
        '/rtl/top.v',
        '/pdk/a.lib',
        '/rtl/core.sv',
        '/pdk/b.liberty',
      ]);
      expect(project.sourceFiles, <String>['/rtl/top.v', '/rtl/core.sv']);
      expect(project.libertyFiles, <String>['/pdk/a.lib', '/pdk/b.liberty']);
    });
  });

  group('project file', () {
    const reader = NetcruxProjectFileReader();
    const writer = NetcruxProjectFileWriter();

    test('round-trips libertyFiles', () {
      final project = NetcruxProject.create(
        sourceFiles: const <String>['top.v'],
        libertyFiles: const <String>['pdk/a.lib', 'pdk/b.lib'],
      );
      expect(reader.parse(writer.serialise(project)), project);
    });

    test('omits the key when there are none, so older files keep shape', () {
      final json = writer.toJson(
        NetcruxProject.create(sourceFiles: const <String>['top.v']),
      );
      expect(json.containsKey('libertyFiles'), isFalse);
    });

    test('a file written before cell libraries loads with none', () {
      final project = reader.parse(
        '{"version": 1, "sourceFiles": ["top.v"], "topModule": "top"}',
      );
      expect(project.libertyFiles, isEmpty);
    });

    test('paths are anchored and made relative like sources', () {
      final project = NetcruxProject.create(
        sourceFiles: const <String>['rtl/top.v'],
        libertyFiles: const <String>['../pdk/cells.lib', '/abs/other.lib'],
      );
      final resolved = resolveProjectPaths(project, '/work/proj');
      expect(resolved.libertyFiles, <String>[
        p.normalize('/work/pdk/cells.lib'),
        p.normalize('/abs/other.lib'),
      ]);
      final relative = relativizeProjectPaths(resolved, '/work/proj');
      expect(relative.libertyFiles.first, p.join('..', 'pdk', 'cells.lib'));
    });
  });

  group('filelist', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('filelist_lib'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('a .lib or .liberty entry is a cell library, not a source', () async {
      File(p.join(dir.path, 'nested.f')).writeAsStringSync('more.liberty\n');
      final top = File(p.join(dir.path, 'top.f'))
        ..writeAsStringSync(
          'top.v\n'
          '../pdk/cells.lib\n'
          '-f nested.f\n'
          '+incdir+inc\n',
        );
      final project = await const FilelistReader().readAsProject(top.path);
      expect(project.sourceFiles, <String>[p.join(dir.path, 'top.v')]);
      expect(project.libertyFiles, <String>[
        p.normalize(p.join(dir.path, '..', 'pdk', 'cells.lib')),
        p.join(dir.path, 'more.liberty'),
      ]);
    });
  });

  group('tab payload', () {
    const codec = NetcruxWorkspaceCodec();

    test('round-trips a tab-level list, including an empty one', () {
      for (final list in <List<String>>[
        const <String>['/pdk/a.lib'],
        const <String>[],
      ]) {
        final payload = NetcruxTabPayload(
          sourceFiles: const <String>['/rtl/top.v'],
          libertyFiles: list,
        );
        final back = codec.payloadFromJson(codec.payloadToJson(payload));
        expect(back.libertyFiles, list);
        expect(back, payload);
      }
    });

    test('no list of its own stays null, absent from the JSON', () {
      const payload = NetcruxTabPayload(sourceFiles: <String>['/rtl/top.v']);
      final json = codec.payloadToJson(payload);
      expect(json.containsKey('libertyFiles'), isFalse);
      expect(codec.payloadFromJson(json).libertyFiles, isNull);
    });

    test('copyWith sets and clears the list', () {
      const payload = NetcruxTabPayload.empty;
      final set = payload.copyWith(libertyFiles: const <String>['a.lib']);
      expect(set.libertyFiles, <String>['a.lib']);
      expect(set, isNot(payload));
      expect(set.copyWith(clearLibertyFiles: true), payload);
    });

    test('a malformed list is a format error', () {
      expect(
        () => codec.payloadFromJson(<String, Object?>{
          'sourceFiles': <String>[],
          'libertyFiles': 'cells.lib',
        }),
        throwsFormatException,
      );
    });
  });

  group('elaboration cache key', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('cache_key_lib'));
    tearDown(() => dir.deleteSync(recursive: true));

    test(
      'a changed or missing cell library changes or voids the key',
      () async {
        final src = File(p.join(dir.path, 'top.v'))..writeAsStringSync('x');
        final lib = File(p.join(dir.path, 'cells.lib'))..writeAsStringSync('y');
        Future<String?> key(List<String> libs) async =>
            (await ElaborationCacheService.buildKey(
              sourceFilePaths: <String>[src.path],
              libertyFilePaths: libs,
              yosysVersion: 'v',
            ))?.canonicalKey;

        final none = await key(const <String>[]);
        final one = await key(<String>[lib.path]);
        expect(one, isNot(none));
        lib.setLastModifiedSync(DateTime(2001));
        expect(await key(<String>[lib.path]), isNot(one));
        expect(await key(<String>[p.join(dir.path, 'gone.lib')]), isNull);
      },
    );
  });
}
