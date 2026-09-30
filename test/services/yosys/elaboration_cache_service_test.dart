// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/elaboration_cache_key.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/services/yosys/elaboration_cache_service.dart';

import '../../helpers/wait_for.dart';

ElaborationCacheKey _key({
  String version = 'Yosys 0.50',
  List<ElaborationCacheFile> files = const <ElaborationCacheFile>[
    ElaborationCacheFile(
      path: '/p/foo.v',
      sizeBytes: 10,
      modifiedMicroseconds: 1,
    ),
  ],
}) => ElaborationCacheKey(files: files, yosysVersion: version);

ElaborationCacheKey _keyFor(String path) => _key(
  files: <ElaborationCacheFile>[
    ElaborationCacheFile(path: path, sizeBytes: 1, modifiedMicroseconds: 1),
  ],
);

ElaborationCacheEntry _entry({String creator = 'test', int bytes = 10}) =>
    ElaborationCacheEntry(
      model: NetlistModel(creator: creator, modules: const {}),
      stderr: 'warn: $creator',
      approxBytes: bytes,
    );

void main() {
  group('ElaborationCacheService', () {
    test('lookup returns null on a cold cache', () {
      final cache = ElaborationCacheService();
      expect(cache.lookup(_key()), isNull);
    });

    test('store + lookup round-trips the parsed model and stderr', () {
      final entry = _entry(creator: 'round-trip');
      final cache = ElaborationCacheService()..store(_key(), entry);
      final hit = cache.lookup(_key());
      expect(hit, isNotNull);
      expect(hit!.model, same(entry.model));
      expect(hit.stderr, 'warn: round-trip');
    });

    test('different versions miss each other', () {
      final cache = ElaborationCacheService()
        ..store(_key(version: 'A'), _entry(creator: 'A'));
      expect(cache.lookup(_key(version: 'B')), isNull);
    });

    test('LRU eviction drops the oldest entry past maxEntries', () {
      final cache = ElaborationCacheService(maxEntries: 2);
      final k1 = _keyFor('/a.v');
      final k2 = _keyFor('/b.v');
      final k3 = _keyFor('/c.v');
      cache
        ..store(k1, _entry(creator: '1'))
        ..store(k2, _entry(creator: '2'))
        ..store(k3, _entry(creator: '3'));
      expect(cache.lookup(k1), isNull);
      expect(cache.lookup(k2)!.model.creator, '2');
      expect(cache.lookup(k3)!.model.creator, '3');
      expect(cache.length, 2);
    });

    test('lookup promotes an entry to most-recent so it survives eviction', () {
      final cache = ElaborationCacheService(maxEntries: 2);
      final k1 = _keyFor('/a.v');
      final k2 = _keyFor('/b.v');
      final k3 = _keyFor('/c.v');
      cache
        ..store(k1, _entry(creator: '1'))
        ..store(k2, _entry(creator: '2'))
        // Touch k1 so it becomes most-recent.
        ..lookup(k1)
        ..store(k3, _entry(creator: '3'));
      expect(cache.lookup(k1)!.model.creator, '1');
      expect(cache.lookup(k2), isNull);
      expect(cache.lookup(k3)!.model.creator, '3');
    });

    test('byte budget evicts LRU entries but never the newest', () {
      final cache = ElaborationCacheService(maxTotalBytes: 100);
      final k1 = _keyFor('/a.v');
      final k2 = _keyFor('/b.v');
      final k3 = _keyFor('/c.v');
      cache
        ..store(k1, _entry(creator: '1', bytes: 60))
        ..store(k2, _entry(creator: '2', bytes: 60));
      // 120 > 100 → k1 evicted.
      expect(cache.lookup(k1), isNull);
      expect(cache.totalBytes, 60);
      // A single oversized entry still caches (newest is exempt).
      cache.store(k3, _entry(creator: '3', bytes: 500));
      expect(cache.lookup(k3)!.model.creator, '3');
      expect(cache.length, 1);
      expect(cache.totalBytes, 500);
    });

    test('re-storing the same key replaces its bytes, not adds', () {
      final key = _key();
      final cache = ElaborationCacheService()
        ..store(key, _entry(bytes: 40))
        ..store(key, _entry(bytes: 70));
      expect(cache.length, 1);
      expect(cache.totalBytes, 70);
    });

    test('invalidate removes a single entry and its bytes', () {
      final key = _key();
      final cache = ElaborationCacheService()
        ..store(key, _entry())
        ..invalidate(key);
      expect(cache.lookup(key), isNull);
      expect(cache.totalBytes, 0);
    });

    test('clear empties the cache', () {
      final cache = ElaborationCacheService()
        ..store(_key(), _entry())
        ..clear();
      expect(cache.length, 0);
      expect(cache.totalBytes, 0);
    });
  });

  group('ElaborationCacheService.buildKey', () {
    late Directory tempDir;
    setUp(() {
      tempDir = Directory.systemTemp.createTempSync(
        'netcrux_elab_cache_buildkey_',
      );
    });
    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('returns a key with file fingerprints from disk', () async {
      final file = File('${tempDir.path}/foo.v')
        ..writeAsStringSync('module x; endmodule');
      final key = await ElaborationCacheService.buildKey(
        sourceFilePaths: <String>[file.path],
        yosysVersion: 'Yosys test',
      );
      expect(key, isNotNull);
      expect(key!.files, hasLength(1));
      expect(key.files.single.path, file.path);
      expect(key.files.single.sizeBytes, greaterThan(0));
    });

    test('returns null when any source file is missing', () async {
      final key = await ElaborationCacheService.buildKey(
        sourceFilePaths: const <String>['/does/not/exist.v'],
        yosysVersion: 'Yosys test',
      );
      expect(key, isNull);
    });

    test('a re-elaboration after touch produces a different key', () async {
      final file = File('${tempDir.path}/foo.v')..writeAsStringSync('first');
      final k1 = await ElaborationCacheService.buildKey(
        sourceFilePaths: <String>[file.path],
        yosysVersion: 'Yosys test',
      );
      // Touch with SAME-SIZE content so only the mtime distinguishes the
      // key, and poll until the filesystem clock actually ticks past k1's
      // stamp (APFS is fine-grained; coarser filesystems need a beat) —
      // no fixed sleep guessing at the mtime resolution.
      ElaborationCacheKey? k2;
      await waitFor(() async {
        file.writeAsStringSync('firsX');
        k2 = await ElaborationCacheService.buildKey(
          sourceFilePaths: <String>[file.path],
          yosysVersion: 'Yosys test',
        );
        return k2 != k1;
      }, reason: 'mtime never advanced past the first write');
      expect(k1, isNot(equals(k2)));
    });
  });
}
