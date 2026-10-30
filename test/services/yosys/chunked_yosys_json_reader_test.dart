// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/services/yosys/chunked_yosys_json_reader.dart';
import 'package:netcrux/services/yosys/isolate_netlist_parser.dart';
import 'package:netcrux/services/yosys/prebuilt_netlist_loader.dart';
import 'package:netcrux/services/yosys/streaming_yosys_json_reader.dart';
import 'package:netcrux/services/yosys/yosys_json_parser.dart';

/// The file reader against the string reader, document by document and chunk
/// size by chunk size. The string reader is the long-tested one; the file
/// reader must build the same model from the same text however the bytes are
/// cut, and reject what it rejects.
NetlistModel _chunked(String text, int chunkSize, {CancellationToken? cancel}) {
  return ChunkedYosysJsonReader(
    MemoryChunkSource(
      Uint8List.fromList(utf8.encode(text)),
      maxChunk: chunkSize,
    ),
    chunkSize: chunkSize,
    cancellation: cancel,
  ).parse();
}

const StreamingYosysJsonReader _strings = StreamingYosysJsonReader();

void main() {
  final fixtures = <String, String>{
    for (final entity in Directory('test/fixtures').listSync(recursive: true))
      if (entity is File &&
          entity.path.endsWith('.json') &&
          !entity.path.contains('malformed') &&
          !entity.path.contains('mesh_1m') &&
          !entity.path.contains('grid_100k') &&
          !entity.path.endsWith('.expected_error.json') &&
          // Goldens of the parsed model, not Yosys documents.
          !entity.path.contains('expected_netlist') &&
          entity.lengthSync() < 3 * 1024 * 1024)
        entity.path: entity.readAsStringSync(),
  };

  group('ChunkedYosysJsonReader equals the string reader', () {
    test('there are fixtures to compare', () {
      expect(fixtures.length, greaterThan(5));
    });

    for (final entry in fixtures.entries) {
      test('${entry.key}, cut at several chunk sizes', () {
        final expected = _strings.parse(entry.value);
        // A one-byte chunk splits every token; do it only where it is cheap.
        final sizes = entry.value.length < 30000
            ? const [1, 2, 3, 7, 61, 4096]
            : const [13, 4096, 1 << 20];
        for (final size in sizes) {
          expect(_chunked(entry.value, size), expected, reason: 'chunk $size');
        }
      });
    }

    test('names with escapes, braces, quotes and multi-byte text', () {
      // Every kind of byte a name can hold, in a cell name, a net name, a
      // module name and an attribute, with the tokens cut at every offset.
      final doc = jsonEncode(<String, Object?>{
        'creator': 'Yosys 0.99 (café)',
        'modules': <String, Object?>{
          r'we"ird\mod{ule}': <String, Object?>{
            'attributes': <String, Object?>{
              'src': 'aé中😀\n"{[',
              'top': '00000000000000000000000000000001',
            },
            'ports': <String, Object?>{
              'a': <String, Object?>{
                'direction': 'input',
                'bits': <Object?>[2],
              },
            },
            'cells': <String, Object?>{
              r'\u_{x}/"q"\': <String, Object?>{
                'hide_name': 0,
                'type': r'$and',
                'parameters': <String, Object?>{'W': '0001'},
                'attributes': <String, Object?>{'src': 'x.v:1.1-2.2'},
                'port_directions': <String, Object?>{'A': 'input'},
                'connections': <String, Object?>{
                  'A': <Object?>[2, '0', 'x'],
                },
              },
            },
            'netnames': <String, Object?>{
              'nét': <String, Object?>{
                'hide_name': 1,
                'bits': <Object?>[2],
                'attributes': <String, Object?>{},
              },
            },
          },
        },
      });
      final expected = _strings.parse(doc);
      expect(
        expected.modules.keys.single,
        r'we"ird\mod{ule}',
        reason: 'the string reader reads the document',
      );
      for (var size = 1; size < 40; size++) {
        expect(_chunked(doc, size), expected, reason: 'chunk $size');
      }
    });

    test('pretty-printed, with the creator last and unknown members', () {
      const doc = r'''
{
  "extra": {"nested": [1, 2, {"x": "}"}]},
  "modules": {
    "m": {
      "parameter_default_values": {"P": "1"},
      "attributes": {"top": "1"},
      "ports": null,
      "cells": {
        "c": {
          "type": "$not",
          "connections": {"A": [2], "Y": [3]},
          "port_directions": {"A": "input", "Y": "output"}
        }
      },
      "netnames": {}
    }
  },
  "creator": "Yosys"
}
''';
      final expected = _strings.parse(doc);
      for (final size in const [1, 5, 64, 4096]) {
        expect(_chunked(doc, size), expected, reason: 'chunk $size');
      }
      expect(_chunked(doc, 3).creator, 'Yosys');
    });

    test('a module far larger than the chunk is read member by member', () {
      // 20k cells in one module through a 1 KiB buffer: nothing here holds
      // the module, or the document, in one piece.
      final cells = <String, Object?>{
        for (var i = 0; i < 20000; i++)
          'u$i': <String, Object?>{
            'hide_name': 0,
            'type': r'$not',
            'port_directions': <String, Object?>{'A': 'input', 'Y': 'output'},
            'connections': <String, Object?>{
              'A': <Object?>[i + 2],
              'Y': <Object?>[i + 3],
            },
          },
      };
      final doc = jsonEncode(<String, Object?>{
        'creator': 'Yosys',
        'modules': <String, Object?>{
          'flat': <String, Object?>{'cells': cells},
        },
      });
      expect(doc.length, greaterThan(1 << 20));
      final model = _chunked(doc, 1024);
      expect(model.modules['flat']!.cells, hasLength(20000));
      expect(model, _strings.parse(doc));
    });

    test('the buffer is the only window on the file', () {
      // The reader never asks its source for more than the chunk size, and
      // the bytes it was handed are enough: a source that serves a 100 MB
      // document 64 KiB at a time is read through to the end.
      final source = _CountingSource(100 * 1024 * 1024);
      final model = ChunkedYosysJsonReader(
        source,
        chunkSize: 64 * 1024,
      ).parse();
      expect(model.modules['pad']!.attributes['top'], '1');
      expect(source.largestRequest, 64 * 1024);
      expect(source.bytesServed, greaterThan(100 * 1024 * 1024));
    });
  });

  group('ChunkedYosysJsonReader rejects what the string reader rejects', () {
    final valid = File(
      'test/fixtures/verilog/and2.expected.json',
    ).readAsStringSync();

    /// [stricter] allows the file reader to refuse a document the string
    /// reader lets through: the string reader accepts a document cut off
    /// inside its `modules` object, the file reader walks the structure and
    /// does not.
    void expectSameVerdict(
      String doc, {
      int chunk = 7,
      bool stricter = false,
    }) {
      Object? expected;
      try {
        expected = _strings.parse(doc);
      } on YosysJsonParseException catch (e) {
        expected = e;
      }
      Object? actual;
      try {
        actual = _chunked(doc, chunk);
      } on YosysJsonParseException catch (e) {
        actual = e;
      }
      if (expected is NetlistModel && !(stricter && actual is Exception)) {
        expect(actual, expected, reason: doc);
      } else if (expected is! NetlistModel) {
        expect(
          actual,
          isA<YosysJsonParseException>(),
          reason: 'the string reader rejects it, so must the file reader: $doc',
        );
      }
    }

    test('the malformed corpus', () {
      final dir = Directory('test/fixtures/netlist/malformed/generated');
      final files = dir.listSync().whereType<File>().where(
        (f) =>
            f.path.endsWith('.json') &&
            !f.path.endsWith('.expected_error.json'),
      );
      expect(files, isNotEmpty);
      for (final file in files) {
        expectSameVerdict(file.readAsStringSync());
      }
    });

    test('non-object documents and an empty file', () {
      ['', '   ', '[]', '42', '"s"', 'null', '{'].forEach(expectSameVerdict);
    });

    test('every truncation point of a valid netlist', () {
      for (var cut = 0; cut <= valid.length; cut++) {
        expectSameVerdict(
          valid.substring(0, cut),
          chunk: 1 + cut % 9,
          stricter: cut < valid.length,
        );
      }
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('random byte mutations never leak a raw error', () {
      final rng = Random(0x4e43);
      final units = valid.codeUnits.toList();
      for (var iter = 0; iter < 1500; iter++) {
        final mutated = List<int>.of(units);
        final flips = 1 + rng.nextInt(4);
        for (var f = 0; f < flips; f++) {
          mutated[rng.nextInt(mutated.length)] = 0x20 + rng.nextInt(0x5e);
        }
        final doc = String.fromCharCodes(mutated);
        try {
          _chunked(doc, 1 + iter % 17);
        } on YosysJsonParseException {
          // typed, as it must be
        }
      }
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('a wrong-typed field names the module, the cell and the field', () {
      const doc =
          '{"modules":{"m":{"cells":{"c":{"type":"x","connections":{"A":3}}}}}}';
      Object? fromStrings;
      try {
        _strings.parse(doc);
      } on YosysJsonParseException catch (e) {
        fromStrings = e.message;
      }
      Object? fromChunks;
      try {
        _chunked(doc, 5);
      } on YosysJsonParseException catch (e) {
        fromChunks = e.message;
      }
      expect(fromChunks, isNotNull);
      expect(fromChunks, fromStrings);
    });

    test('a member that is not an object says what it was', () {
      const doc = '{"modules":{"m":{"cells":{"c":7}}}}';
      expect(
        () => _chunked(doc, 4),
        throwsA(
          isA<YosysJsonParseException>().having(
            (e) => e.message,
            'message',
            allOf(contains('"m"'), contains('cell "c"'), contains('7')),
          ),
        ),
      );
    });

    test('cancellation returns an empty netlist', () {
      final token = CancellationToken()..cancel();
      final model = _chunked(valid, 16, cancel: token);
      expect(model.modules, isEmpty);
    });
  });

  group('a netlist file of more than 2 GiB', () {
    // The case that was a RangeError: the JSON is bigger than any Dart string.
    // The document is real and valid, padded with white space between two
    // members so the file is large without a design to match, and it is
    // opened through the three routes a user has.
    late Directory dir;
    late File big;
    late int size;

    setUpAll(() {
      dir = Directory.systemTemp.createTempSync('netcrux_big_json_');
      big = File('${dir.path}/big.json');
      final sink = big.openSync(mode: FileMode.write);
      try {
        sink.writeStringSync(
          '{"creator":"Yosys","modules":{"top":{"attributes":{"top":"1"},'
          r'"cells":{"u0":{"type":"$not","connections":{"A":[2],"Y":[3]},'
          '"port_directions":{"A":"input","Y":"output"}}',
        );
        final pad = Uint8List(8 * 1024 * 1024)..fillRange(0, 8 << 20, 0x20);
        // Just over 2 GiB of white space inside the cells object.
        const target = (1 << 31) + (16 << 20);
        for (var written = 0; written < target; written += pad.length) {
          sink.writeFromSync(pad);
        }
        sink.writeStringSync(
          r',"u1":{"type":"$not","connections":{"A":[3],"Y":[4]},'
          '"port_directions":{"A":"input","Y":"output"}}},'
          '"netnames":{}}}}',
        );
      } finally {
        sink.closeSync();
      }
      size = big.lengthSync();
    });

    tearDownAll(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    void expectDesign(NetlistModel? model) {
      expect(model, isNotNull);
      final top = model!.modules['top']!;
      expect(top.cells.keys, ['u0', 'u1']);
      expect(top.isTop, isTrue);
    }

    test('is larger than a Dart string can be', () {
      expect(size, greaterThan(0x7fffffff));
    });

    test('is read in chunks by the reader', () {
      expectDesign(ChunkedYosysJsonReader.parseFile(big.path));
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('is read in chunks on a worker isolate', () async {
      expectDesign(await parseNetlistFileOnIsolate(big.path));
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('opens through File > Open Netlist JSON (the loader)', () async {
      expectDesign(await const PrebuiltNetlistLoader().load(big.path));
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}

/// A document served from nowhere: an opening, `megabytes` of white space in
/// the middle of a cells object, a closing. Records the largest read asked of
/// it.
class _CountingSource implements ByteChunkSource {
  _CountingSource(this.padding)
    : _head = utf8.encode(
        '{"modules":{"pad":{"attributes":{"top":"1"},"cells":{',
      ),
      _tail = utf8.encode('}}}}');

  final int padding;
  final List<int> _head;
  final List<int> _tail;
  int largestRequest = 0;
  int bytesServed = 0;
  int _at = 0;

  int get _total => _head.length + padding + _tail.length;

  @override
  int read(Uint8List into) {
    largestRequest = max(largestRequest, into.length);
    var n = 0;
    while (n < into.length && _at < _total) {
      if (_at < _head.length) {
        into[n++] = _head[_at++];
      } else if (_at < _head.length + padding) {
        final run = min(into.length - n, _head.length + padding - _at);
        into.fillRange(n, n + run, 0x20);
        n += run;
        _at += run;
      } else {
        into[n++] = _tail[_at++ - _head.length - padding];
      }
    }
    bytesServed += n;
    return n;
  }

  @override
  void close() {}
}
