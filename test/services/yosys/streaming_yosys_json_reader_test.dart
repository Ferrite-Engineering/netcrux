// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/services/yosys/streaming_yosys_json_reader.dart';
import 'package:netcrux/services/yosys/yosys_json_parser.dart';
import 'package:path/path.dart' as p;

void main() {
  group('StreamingYosysJsonReader', () {
    const reader = StreamingYosysJsonReader();
    const inMemory = YosysJsonParser();

    test('parses a simple two-module document', () {
      const json = '''
{
  "creator": "Yosys 0.40 (test)",
  "modules": {
    "and2": {
      "ports": {},
      "cells": {},
      "netnames": {}
    },
    "top": {
      "attributes": { "top": "1" },
      "ports": {},
      "cells": {},
      "netnames": {}
    }
  }
}
''';
      final streamed = reader.parse(json);
      expect(streamed.creator, 'Yosys 0.40 (test)');
      expect(streamed.modules.keys, containsAll(<String>['and2', 'top']));
      expect(streamed.topModule?.name, 'top');
    });

    test('agrees with the in-memory parser on the and2 fixture', () async {
      final path = p.join(
        Directory.current.path,
        'test',
        'fixtures',
        'verilog',
        'and2.expected.json',
      );
      final raw = await File(path).readAsString();
      final viaStreaming = reader.parse(raw);
      final viaInMemory = inMemory.parse(raw);
      expect(viaStreaming.creator, viaInMemory.creator);
      expect(
        viaStreaming.modules.keys.toSet(),
        viaInMemory.modules.keys.toSet(),
      );
      for (final name in viaStreaming.modules.keys) {
        expect(viaStreaming.modules[name], viaInMemory.modules[name]);
      }
    });

    test('agrees with the in-memory parser on the adder4 fixture', () async {
      final path = p.join(
        Directory.current.path,
        'test',
        'fixtures',
        'verilog',
        'adder4.expected.json',
      );
      final raw = await File(path).readAsString();
      final viaStreaming = reader.parse(raw);
      final viaInMemory = inMemory.parse(raw);
      expect(viaStreaming, viaInMemory);
    });

    test('agrees with the in-memory parser on the fsm fixture', () async {
      final path = p.join(
        Directory.current.path,
        'test',
        'fixtures',
        'verilog',
        'fsm.expected.json',
      );
      final raw = await File(path).readAsString();
      final viaStreaming = reader.parse(raw);
      final viaInMemory = inMemory.parse(raw);
      expect(viaStreaming, viaInMemory);
    });

    test('readFile reads from disk and parses', () async {
      final path = p.join(
        Directory.current.path,
        'test',
        'fixtures',
        'verilog',
        'and2.expected.json',
      );
      final model = await reader.readFile(path);
      expect(model.modules, isNotEmpty);
    });

    test('readStream parses a chunked byte stream', () async {
      final path = p.join(
        Directory.current.path,
        'test',
        'fixtures',
        'verilog',
        'and2.expected.json',
      );
      final bytes = await File(path).readAsBytes();
      // Slice the file into 64-byte chunks to simulate a slow stream.
      final stream = Stream<List<int>>.fromIterable(<List<int>>[
        for (var i = 0; i < bytes.length; i += 64)
          bytes.sublist(i, (i + 64).clamp(0, bytes.length)),
      ]);
      final model = await reader.readStream(stream);
      expect(model.modules, isNotEmpty);
    });

    test('cancellation aborts mid-document', () async {
      // Build a document with several modules; cancel before the
      // reader even starts processing them.
      const json = '''
{
  "modules": {
    "a": { "ports": {}, "cells": {}, "netnames": {} },
    "b": { "ports": {}, "cells": {}, "netnames": {} },
    "c": { "ports": {}, "cells": {}, "netnames": {} }
  }
}
''';
      final token = CancellationToken()..cancel();
      final model = reader.parse(json, cancellation: token);
      // Cancelled before any module was processed.
      expect(model.modules, isEmpty);
    });

    test('rejects a malformed document with a parse exception', () {
      const json = '{"modules": { "a": { not valid json } }';
      expect(
        () => reader.parse(json),
        throwsA(isA<YosysJsonParseException>()),
      );
    });

    test('rejects a document missing the modules key', () {
      const json = '{"creator": "yosys"}';
      expect(
        () => reader.parse(json),
        throwsA(isA<YosysJsonParseException>()),
      );
    });

    test('handles braces inside string values', () {
      const json = '''
{
  "creator": "yosys {with braces}",
  "modules": {
    "a": { "ports": {}, "cells": {}, "netnames": {}, "tag": "}" }
  }
}
''';
      final model = reader.parse(json);
      expect(model.creator, 'yosys {with braces}');
      expect(model.modules.keys, <String>['a']);
    });
  });
}
