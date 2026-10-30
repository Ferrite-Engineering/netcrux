// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/enums/netcrux_source_language.dart';
import 'package:netcrux/domain/enums/netlist_reader_choice.dart';
import 'package:netcrux/domain/models/project/netcrux_project.dart';
import 'package:netcrux/services/project/netcrux_project_file.dart';
import 'package:netcrux/services/project/netcrux_project_path_resolver.dart';
import 'package:netcrux/services/yosys/elaboration_cache_service.dart';
import 'package:path/path.dart' as p;

/// The native gate-level reader's two project fields, `cellModelFiles` and
/// `netlistReader`, through the model, the project file and path anchoring.
void main() {
  group('NetcruxProject', () {
    test('both fields default to nothing and take part in equality', () {
      final plain = NetcruxProject.create(sourceFiles: const <String>['a.v']);
      expect(plain.cellModelFiles, isEmpty);
      expect(plain.netlistReader, NetlistReaderChoice.auto);
      expect(NetcruxProject.empty.cellModelFiles, isEmpty);
      final models = plain.copyWith(cellModelFiles: const <String>['m.v']);
      final yosys = plain.copyWith(netlistReader: NetlistReaderChoice.yosys);
      expect(models, isNot(plain));
      expect(yosys, isNot(plain));
      expect(models.hashCode, isNot(plain.hashCode));
      expect(yosys.hashCode, isNot(plain.hashCode));
      // copyWith without the fields keeps them.
      expect(models.copyWith(topModule: 't').cellModelFiles, ['m.v']);
      expect(
        yosys.copyWith(topModule: 't').netlistReader,
        NetlistReaderChoice.yosys,
      );
    });

    test('a .v.gz source is Verilog', () {
      expect(
        NetcruxProject.inferLanguageFromExtension('/d/top.v.gz'),
        NetcruxSourceLanguage.verilog,
      );
      expect(
        NetcruxProject.inferLanguageFromExtension('/d/TOP.V.GZ'),
        NetcruxSourceLanguage.verilog,
      );
      expect(
        NetcruxProject.inferLanguageFromExtension('/d/top.sv.gz'),
        NetcruxSourceLanguage.systemVerilog,
      );
    });
  });

  group('project file', () {
    const reader = NetcruxProjectFileReader();
    const writer = NetcruxProjectFileWriter();

    test('round-trips both keys', () {
      final project = NetcruxProject.create(
        sourceFiles: const <String>['top.v'],
        cellModelFiles: const <String>['models/cells.v', 'models/io.v.gz'],
        netlistReader: NetlistReaderChoice.native,
      );
      final json = writer.toJson(project);
      expect(json['cellModelFiles'], ['models/cells.v', 'models/io.v.gz']);
      expect(json['netlistReader'], 'native');
      expect(reader.fromJson(json), project);
    });

    test('writes neither key at their defaults', () {
      final json = writer.toJson(
        NetcruxProject.create(sourceFiles: const <String>['top.v']),
      );
      expect(json.containsKey('cellModelFiles'), isFalse);
      expect(json.containsKey('netlistReader'), isFalse);
    });

    test(
      'a file without the keys, or with an unknown reader, reads as auto',
      () {
        final base = <String, Object?>{
          'version': 1,
          'sourceFiles': <String>['a.v'],
        };
        final plain = reader.fromJson(base);
        expect(plain.cellModelFiles, isEmpty);
        expect(plain.netlistReader, NetlistReaderChoice.auto);
        final odd = reader.fromJson(<String, Object?>{
          ...base,
          'netlistReader': 'verilator',
        });
        expect(odd.netlistReader, NetlistReaderChoice.auto);
      },
    );
  });

  group('path anchoring', () {
    final dir = p.normalize(p.absolute(p.join('/tmp', 'designs', 'cpu')));

    test(
      'cell model files resolve against the project and relativize back',
      () {
        final project = NetcruxProject.create(
          sourceFiles: const <String>['top.v'],
          cellModelFiles: const <String>['models/cells.v', '../shared/io.v'],
        );
        final resolved = resolveProjectPaths(project, dir);
        expect(resolved.cellModelFiles, [
          p.join(dir, 'models', 'cells.v'),
          p.normalize(p.join(dir, '..', 'shared', 'io.v')),
        ]);
        final back = relativizeProjectPaths(resolved, dir);
        expect(back.cellModelFiles, ['models/cells.v', '../shared/io.v']);
      },
    );
  });

  group('elaboration cache key', () {
    test('the reader and the cell model files are part of it', () async {
      final a = await ElaborationCacheService.buildKey(
        sourceFilePaths: const <String>[],
        yosysVersion: '',
        reader: 'native',
      );
      final b = await ElaborationCacheService.buildKey(
        sourceFilePaths: const <String>[],
        yosysVersion: '',
      );
      expect(a, isNot(b));
      expect(a!.canonicalKey, contains(';reader=native'));
      expect(b!.canonicalKey, isNot(contains('reader')));
    });
  });
}
