// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/services/liberty/liberty_stub_service.dart';
import 'package:path/path.dart' as p;

const String _libA = '''
library (a) {
  cell (INV) {
    pg_pin (VDD) { pg_type : primary_power ; }
    pg_pin (VSS) { pg_type : primary_ground ; }
    pin (A) { direction : input ; }
    pin (Y) { direction : output ; }
  }
}
''';

const String _libB = '''
library (b) {
  cell (INV) { pin (Z) { direction : input ; } }
  cell (BUF) {
    pin (A) { direction : input ; }
    pin (Y) { direction : output ; }
  }
}
''';

void main() {
  late Directory root;
  late Directory cacheBase;
  late LibertyStubService service;

  setUp(() {
    root = Directory.systemTemp.createTempSync('liberty_service_test');
    cacheBase = Directory(p.join(root.path, 'support'))..createSync();
    service = LibertyStubService(cacheBaseDirectory: () async => cacheBase);
  });
  tearDown(() => root.deleteSync(recursive: true));

  String write(String name, String text) {
    final path = p.join(root.path, name);
    File(path).writeAsStringSync(text);
    return path;
  }

  File cacheFile(String prefix) =>
      Directory(p.join(cacheBase.path, 'liberty-cache'))
          .listSync()
          .whereType<File>()
          .singleWhere((f) => p.basename(f.path).startsWith(prefix));

  test('writes a stub file under liberty-cache with every cell', () async {
    final a = write('a.lib', _libA);
    final b = write('b.lib', _libB);
    final stubs = await service.stubsFor(<String>[a, b]);
    expect(p.dirname(stubs.stubPath), p.join(cacheBase.path, 'liberty-cache'));
    final verilog = File(stubs.stubPath).readAsStringSync();
    expect(verilog, contains('module INV (VDD, VSS, A, Y);'));
    expect(verilog, contains('module BUF (A, Y);'));
    expect(stubs.cellCount, 2);
    // INV is in both; a.lib came first.
    expect(stubs.warnings.single, contains('"INV"'));
  });

  test('a second call reads the cache instead of the Liberty file', () async {
    final a = write('a.lib', _libA);
    final first = await service.stubsFor(<String>[a]);
    // Corrupt the library without changing its size or time: a re-parse
    // would now fail, a cache hit does not.
    final file = File(a);
    final modified = file.lastModifiedSync();
    file
      ..writeAsStringSync(_libA.replaceAll('{', '('))
      ..setLastModifiedSync(modified);
    final second = await service.stubsFor(<String>[a]);
    expect(second.stubPath, first.stubPath);
    expect(second.cellCount, 1);
  });

  test(
    'a gzip-compressed library gives the same stubs as a plain one',
    () async {
      final plain = write('a.lib', _libA);
      final compressed = p.join(root.path, 'b.lib.gz');
      File(compressed).writeAsBytesSync(gzip.encode(utf8.encode(_libA)));
      final fromPlain = await service.stubsFor(<String>[plain]);
      final fromCompressed = await service.stubsFor(<String>[compressed]);
      expect(fromCompressed.warnings, isEmpty);
      expect(fromCompressed.cellCount, 1);
      // The stubs name the file they came from, and nothing else differs.
      expect(
        File(fromCompressed.stubPath).readAsStringSync(),
        File(
          fromPlain.stubPath,
        ).readAsStringSync().replaceFirst('// a.lib', '// b.lib.gz'),
      );
    },
  );

  test('a compressed library is cached by the .gz file, not re-read', () async {
    final path = p.join(root.path, 'a.liberty.gz');
    File(path).writeAsBytesSync(gzip.encode(utf8.encode(_libA)));
    final first = await service.stubsFor(<String>[path]);
    // Replace the contents with something that cannot be inflated, keeping
    // the size and time the cache key is made of: a re-read would now fail,
    // a cache hit does not.
    final file = File(path);
    final size = file.lengthSync();
    final modified = file.lastModifiedSync();
    file
      ..writeAsBytesSync(List<int>.filled(size, 0x1f))
      ..setLastModifiedSync(modified);
    final second = await service.stubsFor(<String>[path]);
    expect(second.stubPath, first.stubPath);
    expect(second.warnings, isEmpty);
    // A change to the .gz file is read again.
    file.setLastModifiedSync(DateTime.now().add(const Duration(hours: 1)));
    final third = await service.stubsFor(<String>[path]);
    expect(third.warnings.single, contains(path));
  });

  test('a damaged .lib.gz is skipped with a warning naming it', () async {
    final path = p.join(root.path, 'bad.lib.gz');
    final bytes = gzip.encode(utf8.encode(_libA)).toList();
    for (var i = 12; i < bytes.length - 8; i++) {
      bytes[i] ^= 0x5a;
    }
    File(path).writeAsBytesSync(bytes);
    final stubs = await service.stubsFor(<String>[path]);
    expect(stubs.cellCount, 0);
    expect(stubs.warnings.single, contains('bad.lib.gz'));
  });

  test('a changed Liberty file is parsed again', () async {
    final a = write('a.lib', _libA);
    final first = await service.stubsFor(<String>[a]);
    write('a.lib', _libB);
    File(a).setLastModifiedSync(DateTime.now().add(const Duration(hours: 1)));
    final second = await service.stubsFor(<String>[a]);
    expect(second.stubPath, isNot(first.stubPath));
    expect(File(second.stubPath).readAsStringSync(), contains('module BUF'));
  });

  test('a corrupt cache entry is a miss, not a failure', () async {
    final a = write('a.lib', _libA);
    await service.stubsFor(<String>[a]);
    cacheFile('lib-').writeAsStringSync('{not json');
    final again = await service.stubsFor(<String>[a]);
    expect(again.cellCount, 1);
  });

  test('a malformed library is skipped with a warning naming it', () async {
    final good = write('good.lib', _libA);
    final bad = write('bad.lib', 'library (x) {\n  cell (A) {\n');
    final stubs = await service.stubsFor(<String>[bad, good]);
    expect(stubs.cellCount, 1);
    expect(File(stubs.stubPath).readAsStringSync(), contains('module INV'));
    expect(stubs.warnings, hasLength(1));
    expect(stubs.warnings.single, contains(bad));
    expect(stubs.warnings.single, contains('line'));
    expect(stubs.warnings.single, contains('never closed'));
    expect(stubs.warnings.single, contains('missing modules'));
  });

  test('a missing library is skipped with a warning naming it', () async {
    final good = write('good.lib', _libA);
    final missing = p.join(root.path, 'nope.lib');
    final stubs = await service.stubsFor(<String>[good, missing]);
    expect(stubs.cellCount, 1);
    expect(stubs.warnings.single, contains(missing));
    expect(stubs.warnings.single, contains('file not found'));
  });

  test('a directory in place of a library is skipped', () async {
    final dirPath = p.join(root.path, 'adir.lib');
    Directory(dirPath).createSync();
    final stubs = await service.stubsFor(<String>[dirPath]);
    expect(stubs.cellCount, 0);
    expect(stubs.warnings.single, contains('not a file'));
  });

  test('when every library is skipped the stub file is empty', () async {
    final bad = write('bad.lib', 'library (x) {\n  cell (A) {\n');
    final stubs = await service.stubsFor(<String>[bad]);
    expect(stubs.cellCount, 0);
    expect(File(stubs.stubPath).readAsStringSync(), isNot(contains('module')));
    expect(stubs.warnings, hasLength(1));
  });

  test('a skipped library is reported again on the next run', () async {
    final bad = write('bad.lib', 'library (x) {\n  cell (A) {\n');
    final good = write('good.lib', _libA);
    await service.stubsFor(<String>[bad, good]);
    final again = await service.stubsFor(<String>[bad, good]);
    expect(again.cellCount, 1);
    expect(again.warnings.single, contains(bad));
  });

  test('fixing a skipped library brings its cells back', () async {
    final lib = write('fix.lib', 'library (x) {\n  cell (A) {\n');
    final broken = await service.stubsFor(<String>[lib]);
    expect(broken.cellCount, 0);
    File(lib).writeAsStringSync(_libA);
    File(lib).setLastModifiedSync(DateTime(2001));
    final fixed = await service.stubsFor(<String>[lib]);
    expect(fixed.cellCount, 1);
    expect(fixed.warnings, isEmpty);
    expect(fixed.stubPath, isNot(broken.stubPath));
  });

  test('prunes old cache files but never the ones in use', () async {
    final small = LibertyStubService(
      cacheBaseDirectory: () async => cacheBase,
      maxCacheFiles: 2,
    );
    final paths = <String>[
      for (var i = 0; i < 4; i++)
        write('l$i.lib', _libA.replaceAll('INV', 'INV$i')),
    ];
    LibertyStubs? last;
    for (final path in paths) {
      last = await small.stubsFor(<String>[path]);
    }
    final left = Directory(
      p.join(cacheBase.path, 'liberty-cache'),
    ).listSync().whereType<File>().toList();
    expect(left.length, lessThanOrEqualTo(2));
    expect(File(last!.stubPath).existsSync(), isTrue);
  });
}
