// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/elaboration_cache_key.dart';

void main() {
  group('ElaborationCacheFile', () {
    test('equality and hashCode are value-based', () {
      const a = ElaborationCacheFile(
        path: '/p/foo.v',
        sizeBytes: 100,
        modifiedMicroseconds: 12345,
      );
      const b = ElaborationCacheFile(
        path: '/p/foo.v',
        sizeBytes: 100,
        modifiedMicroseconds: 12345,
      );
      const c = ElaborationCacheFile(
        path: '/p/foo.v',
        sizeBytes: 101,
        modifiedMicroseconds: 12345,
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
    });
  });

  group('ElaborationCacheKey', () {
    ElaborationCacheKey buildKey({
      List<ElaborationCacheFile> files = const <ElaborationCacheFile>[
        ElaborationCacheFile(
          path: '/p/foo.v',
          sizeBytes: 10,
          modifiedMicroseconds: 1,
        ),
      ],
      String version = 'Yosys 0.50',
      String? topModule,
      List<String> defines = const <String>[],
    }) {
      return ElaborationCacheKey(
        files: files,
        yosysVersion: version,
        topModule: topModule,
        defines: defines,
      );
    }

    test('canonicalKey includes yosys version, top, files', () {
      final key = buildKey(topModule: 'top');
      expect(key.canonicalKey, contains('yosys=Yosys 0.50'));
      expect(key.canonicalKey, contains('top=top'));
      expect(key.canonicalKey, contains('/p/foo.v@1:10'));
    });

    test('equal inputs produce equal canonical keys', () {
      final a = buildKey();
      final b = buildKey();
      expect(a, equals(b));
      expect(a.canonicalKey, b.canonicalKey);
      expect(a.hashCode, b.hashCode);
    });

    test('different yosys versions produce different keys', () {
      final a = buildKey();
      final b = buildKey(version: 'Yosys 0.51');
      expect(a, isNot(equals(b)));
    });

    test('different file fingerprints produce different keys', () {
      final a = buildKey();
      final b = buildKey(
        files: const <ElaborationCacheFile>[
          ElaborationCacheFile(
            path: '/p/foo.v',
            sizeBytes: 10,
            modifiedMicroseconds: 999,
          ),
        ],
      );
      expect(a, isNot(equals(b)));
    });

    test('different top modules produce different keys', () {
      final a = buildKey(topModule: 'a');
      final b = buildKey(topModule: 'b');
      expect(a, isNot(equals(b)));
    });

    test('different defines produce different keys', () {
      final a = buildKey(defines: const <String>['FOO']);
      final b = buildKey(defines: const <String>['FOO=1']);
      expect(a, isNot(equals(b)));
    });

    test('constructor freezes the file list against external mutation', () {
      final mutableFiles = <ElaborationCacheFile>[
        const ElaborationCacheFile(
          path: '/p/a.v',
          sizeBytes: 1,
          modifiedMicroseconds: 1,
        ),
      ];
      final key = ElaborationCacheKey(
        files: mutableFiles,
        yosysVersion: 'v',
      );
      mutableFiles.clear();
      expect(key.files, hasLength(1));
    });
  });
}
