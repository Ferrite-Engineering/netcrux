// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/services/web/web_json_loader.dart';
import 'package:path/path.dart' as p;

void main() {
  group('fetchWebJson (VM stub)', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('netcrux_web_loader_');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('reads a JSON file at a bare path', () async {
      final file = File(p.join(tempDir.path, 'top.json'));
      await file.writeAsString('{"creator": "test", "modules": {}}');
      final body = await fetchWebJson(file.path);
      expect(body, contains('"creator"'));
      expect(body, contains('"modules"'));
    });

    test('reads a JSON file via file:// URL', () async {
      final file = File(p.join(tempDir.path, 'top.json'));
      await file.writeAsString('{"modules": {}}');
      final uri = file.uri.toString();
      final body = await fetchWebJson(uri);
      expect(body, contains('modules'));
    });

    test('throws WebJsonLoadException when the file is missing', () async {
      final missing = p.join(tempDir.path, 'absent.json');
      expect(
        () => fetchWebJson(missing),
        throwsA(isA<WebJsonLoadException>()),
      );
    });

    test('WebJsonLoadException carries message and cause', () {
      const exception = WebJsonLoadException('boom', cause: 'network');
      expect(exception.toString(), contains('boom'));
      expect(exception.toString(), contains('network'));
    });

    test('WebJsonLoadException without cause has only the message', () {
      const exception = WebJsonLoadException('alone');
      expect(exception.toString(), contains('alone'));
      expect(exception.toString(), isNot(contains('null')));
    });
  });
}
