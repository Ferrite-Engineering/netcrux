// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/services/liberty/liberty_library.dart';
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

  test('a malformed library fails naming the file', () async {
    final bad = write('bad.lib', 'library (x) {\n  cell (A) {\n');
    await expectLater(
      service.stubsFor(<String>[bad]),
      throwsA(
        isA<LibertyParseException>()
            .having((e) => e.path, 'path', bad)
            .having((e) => e.message, 'message', contains('never closed')),
      ),
    );
  });

  test('a missing library fails naming the file', () async {
    final missing = p.join(root.path, 'nope.lib');
    await expectLater(
      service.stubsFor(<String>[missing]),
      throwsA(
        isA<LibertyParseException>().having((e) => e.path, 'path', missing),
      ),
    );
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
