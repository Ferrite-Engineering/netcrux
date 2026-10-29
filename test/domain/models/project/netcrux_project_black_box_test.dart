// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/project/netcrux_project.dart';
import 'package:netcrux/domain/models/workspace/netcrux_tab_payload.dart';
import 'package:netcrux/services/project/netcrux_project_file.dart';
import 'package:netcrux/services/project/netcrux_project_path_resolver.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_codec.dart';
import 'package:netcrux/services/yosys/elaboration_cache_service.dart';
import 'package:path/path.dart' as p;

/// The "show missing modules as black boxes" option,
/// `NetcruxProject.blackBoxMissingModules`, through every place a project
/// travels: the model, the project file, path anchoring, the tab payload
/// and the elaboration cache key.
void main() {
  group('NetcruxProject.blackBoxMissingModules', () {
    test('defaults to off and takes part in equality and hashing', () {
      final plain = NetcruxProject.create(sourceFiles: const <String>['a.v']);
      final on = NetcruxProject.create(
        sourceFiles: const <String>['a.v'],
        blackBoxMissingModules: true,
      );
      expect(plain.blackBoxMissingModules, isFalse);
      expect(NetcruxProject.empty.blackBoxMissingModules, isFalse);
      expect(on, isNot(plain));
      expect(on.copyWith(blackBoxMissingModules: false), plain);
      expect(
        plain.copyWith(blackBoxMissingModules: true).hashCode,
        on.hashCode,
      );
      // copyWith without the field keeps it.
      expect(on.copyWith(topModule: 'top').blackBoxMissingModules, isTrue);
    });

    test('survives path anchoring both ways', () {
      final on = NetcruxProject.create(
        sourceFiles: const <String>['rtl/top.v'],
        blackBoxMissingModules: true,
      );
      final resolved = resolveProjectPaths(on, '/work/proj');
      expect(resolved.blackBoxMissingModules, isTrue);
      expect(
        relativizeProjectPaths(resolved, '/work/proj').blackBoxMissingModules,
        isTrue,
      );
    });
  });

  group('project file', () {
    const reader = NetcruxProjectFileReader();
    const writer = NetcruxProjectFileWriter();

    test('round-trips the option', () {
      final project = NetcruxProject.create(
        sourceFiles: const <String>['top.v'],
        blackBoxMissingModules: true,
      );
      final json = writer.toJson(project);
      expect(json['blackBoxMissingModules'], isTrue);
      expect(json['version'], kNetcruxProjectVersion);
      expect(reader.parse(writer.serialise(project)), project);
    });

    test('omits the key when off, so the file keeps its v1 shape', () {
      final json = writer.toJson(
        NetcruxProject.create(sourceFiles: const <String>['top.v']),
      );
      expect(json.containsKey('blackBoxMissingModules'), isFalse);
    });

    test('a file without the key, or with a non-bool, loads with it off', () {
      expect(
        reader
            .parse('{"version": 1, "sourceFiles": ["top.v"]}')
            .blackBoxMissingModules,
        isFalse,
      );
      expect(
        reader
            .parse(
              '{"version": 1, "sourceFiles": ["top.v"], '
              '"blackBoxMissingModules": "yes"}',
            )
            .blackBoxMissingModules,
        isFalse,
      );
    });
  });

  group('tab payload', () {
    const codec = NetcruxWorkspaceCodec();

    test('round-trips the tab-level setting, on and off', () {
      for (final value in <bool>[true, false]) {
        final payload = NetcruxTabPayload(
          sourceFiles: const <String>['/rtl/top.v'],
          blackBoxMissingModules: value,
        );
        final back = codec.payloadFromJson(codec.payloadToJson(payload));
        expect(back.blackBoxMissingModules, value);
        expect(back, payload);
      }
    });

    test('no setting of its own stays null, absent from the JSON', () {
      const payload = NetcruxTabPayload(sourceFiles: <String>['/rtl/top.v']);
      final json = codec.payloadToJson(payload);
      expect(json.containsKey('blackBoxMissingModules'), isFalse);
      expect(codec.payloadFromJson(json).blackBoxMissingModules, isNull);
    });

    test('copyWith sets and clears the setting', () {
      const payload = NetcruxTabPayload.empty;
      final set = payload.copyWith(blackBoxMissingModules: true);
      expect(set.blackBoxMissingModules, isTrue);
      expect(set, isNot(payload));
      expect(set.copyWith(topModule: 'x').blackBoxMissingModules, isTrue);
      expect(set.copyWith(clearBlackBoxMissingModules: true), payload);
    });

    test('a non-bool value is a format error', () {
      expect(
        () => codec.payloadFromJson(<String, Object?>{
          'sourceFiles': <String>[],
          'blackBoxMissingModules': 'true',
        }),
        throwsFormatException,
      );
    });
  });

  group('elaboration cache key', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('cache_key_bb'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('the option changes the key', () async {
      final src = File(p.join(dir.path, 'top.v'))..writeAsStringSync('x');
      Future<String?> key({required bool blackBoxes}) async =>
          (await ElaborationCacheService.buildKey(
            sourceFilePaths: <String>[src.path],
            yosysVersion: 'v',
            blackBoxMissingModules: blackBoxes,
          ))?.canonicalKey;

      final off = await key(blackBoxes: false);
      final on = await key(blackBoxes: true);
      expect(on, isNotNull);
      expect(on, isNot(off));
      // Off reads exactly as a key built before the option existed.
      expect(
        off,
        (await ElaborationCacheService.buildKey(
          sourceFilePaths: <String>[src.path],
          yosysVersion: 'v',
        ))?.canonicalKey,
      );
    });
  });
}
