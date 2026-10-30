// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/services/verilog/native_netlist_reader.dart';
import 'package:path/path.dart' as p;

/// A hostile or damaged file must end in a model or a typed decline, soon,
/// and never in a hang, a crash or an exception of an unclassified kind. The
/// reader turns an unforeseen exception into a decline whose message starts
/// "an internal error", so these tests fail on that text: a bug is found
/// here instead of being quietly handed to Yosys.
void main() {
  late Directory dir;
  late File file;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('native_reader_fuzz');
    file = File(p.join(dir.path, 'f.v'));
  });
  tearDown(() => dir.deleteSync(recursive: true));

  const fixtures = <String>[
    'test/fixtures/gate_level/awkward.v',
    'test/fixtures/gate_level/hierarchy.v',
    'test/fixtures/gate_level/declarations.v',
  ];

  /// Reads [bytes] and checks the outcome is one of the two allowed.
  NativeReadOutcome? attempt(
    List<int> bytes, {
    int bufferSize = 4096,
    int maxTokenBytes = 512,
    Duration limit = const Duration(seconds: 10),
  }) {
    file.writeAsBytesSync(bytes);
    final clock = Stopwatch()..start();
    final outcome = readGateLevelNetlist(
      NativeReadRequest(
        sourceFiles: [file.path],
        bufferSize: bufferSize,
        maxTokenBytes: maxTokenBytes,
      ),
    );
    expect(clock.elapsed, lessThan(limit), reason: 'took too long');
    switch (outcome) {
      case NativeReadSuccess(:final model):
        expect(model.modules, isNotEmpty);
      case NativeReadFallbackOutcome(:final message):
        expect(message, isNot(startsWith('an internal error')));
        expect(message, isNotEmpty);
      case null:
        fail('a read nobody cancelled returned null');
    }
    return outcome;
  }

  group('truncation', () {
    for (final path in fixtures) {
      test('${p.basename(path)} cut at every byte offset', () {
        final bytes = File(path).readAsBytesSync();
        for (var cut = 0; cut < bytes.length; cut += 7) {
          attempt(bytes.sublist(0, cut));
        }
        // And every offset through the first 200 bytes, where the header is.
        for (var cut = 0; cut < min(200, bytes.length); cut++) {
          attempt(bytes.sublist(0, cut));
        }
      });
    }

    test('a cut with a tiny buffer, so tokens straddle every refill', () {
      final bytes = File(fixtures.first).readAsBytesSync();
      for (var cut = 1; cut < bytes.length; cut += 11) {
        attempt(bytes.sublist(0, cut), bufferSize: 70, maxTokenBytes: 40);
      }
    });
  });

  group('damage', () {
    const pieces = <String>[
      'module',
      'endmodule',
      '(',
      ')',
      '{',
      '}',
      '[',
      ']',
      ';',
      ',',
      '.',
      r'\',
      '/*',
      '*/',
      '(*',
      '*)',
      '`',
      "'",
      '"',
      "1'b",
      "4'hx",
      'assign',
      'wire',
      '#',
      '=',
      '~',
      '\u0000',
      '\n',
    ];

    test('random byte changes, deletions, copies and insertions', () {
      final random = Random(20261030);
      for (var i = 0; i < 600; i++) {
        final base = File(fixtures[i % fixtures.length]).readAsBytesSync();
        final bytes = List<int>.of(base);
        final edits = 1 + random.nextInt(4);
        for (var e = 0; e < edits && bytes.isNotEmpty; e++) {
          final at = random.nextInt(bytes.length);
          switch (random.nextInt(5)) {
            case 0:
              bytes[at] = random.nextInt(256);
            case 1:
              bytes.removeRange(
                at,
                min(bytes.length, at + 1 + random.nextInt(40)),
              );
            case 2:
              final end = min(bytes.length, at + 1 + random.nextInt(60));
              bytes.insertAll(
                random.nextInt(bytes.length),
                bytes.sublist(at, end),
              );
            case 3:
              bytes.insertAll(
                at,
                pieces[random.nextInt(pieces.length)].codeUnits,
              );
            default:
              bytes.insertAll(
                at,
                List<int>.generate(
                  1 + random.nextInt(8),
                  (_) => random.nextInt(256),
                ),
              );
          }
        }
        attempt(
          bytes,
          bufferSize: i.isEven ? 4096 : 90,
          maxTokenBytes: i.isEven ? 512 : 60,
        );
      }
    });
  });

  group('hostile files', () {
    List<int> text(String s) => s.codeUnits;

    test('nothing, white space, comments only', () {
      for (final content in ['', '   \n\t\n', '// nothing\n/* here */\n']) {
        final outcome = attempt(text(content));
        expect(outcome, isA<NativeReadFallbackOutcome>());
      }
    });

    test('binary noise and NUL bytes', () {
      final random = Random(7);
      attempt(
        Uint8List.fromList(List.generate(300000, (_) => random.nextInt(256))),
      );
      attempt(Uint8List(100000));
      attempt(text('module t (input a);${'\u0000' * 100}endmodule'));
    });

    test('an identifier far over the token limit is declined at once', () {
      final huge = 'a' * (3 * 1024 * 1024);
      final outcome = attempt(
        text('module $huge (input x); endmodule'),
        bufferSize: 1 << 20,
        maxTokenBytes: 64 * 1024,
      );
      expect(
        (outcome! as NativeReadFallbackOutcome).message,
        contains('longer than'),
      );
    });

    test('over-long escaped names, numbers and strings', () {
      final huge = 'b' * 2000;
      for (final snippet in [
        'module t (input a); wire \\$huge ; endmodule',
        "module t (input a); CELL u (.A(1'b${'1' * 2000})); endmodule",
        'module t (input a); CELL u (.A("$huge")); endmodule',
      ]) {
        attempt(text(snippet));
      }
    });

    test('concatenations nested a hundred thousand deep', () {
      const depth = 100000;
      attempt(
        text(
          'module t (input a); CELL u (.A(${'{' * depth}a${'}' * depth})); endmodule',
        ),
        bufferSize: 1 << 20,
      );
      attempt(
        text('module t (input a); CELL u (.A(${'(' * depth}a)); endmodule'),
      );
    });

    test('ranges, repeats and constants too wide to hold', () {
      for (final snippet in [
        'module t (input [2000000000:0] a); endmodule',
        'module t (input [99999999999999999999:0] a); endmodule',
        'module t (input a); CELL u (.A({1000000000{a}})); endmodule',
        "module t (input a); CELL u (.A(2000000000'b1)); endmodule",
        "module t (input a); CELL u (.A(4'd99999999999999999999)); endmodule",
        "module t (input a); CELL u (.A(1'b)); endmodule",
        "module t (input a); CELL u (.A(4'hZZZZZZZZZZ)); endmodule",
        'module t (input a); wire [3:0] w; CELL u (.A(w[999999999999])); endmodule',
      ]) {
        attempt(text(snippet));
      }
    });

    test('a hundred thousand tiny modules, and a chain of them', () {
      final many = StringBuffer();
      for (var i = 0; i < 100000; i++) {
        many.writeln('module m$i (input a); endmodule');
      }
      expect(attempt(text('$many'), bufferSize: 1 << 20), isNotNull);

      final chain = StringBuffer();
      for (var i = 0; i < 9000; i++) {
        chain.writeln('module c$i (input a); c${i + 1} u (.a(a)); endmodule');
      }
      chain.writeln('module c9000 (input a); endmodule');
      attempt(text('$chain'), bufferSize: 1 << 20);
    });

    test('unterminated everything at the end of the file', () {
      for (final tail in [
        '/*',
        '(*',
        '"',
        r'\',
        '`',
        '`define',
        "'",
        "4'",
        '//',
        '(',
        '{',
      ]) {
        attempt(text('module t (input a); $tail'));
        attempt(
          text('module t (input a); wire x; $tail'),
          bufferSize: 40,
          maxTokenBytes: 20,
        );
      }
    });

    test('one line of five megabytes of white space before the module', () {
      attempt(
        text('${' ' * 5000000}module t (input a); endmodule'),
        bufferSize: 1 << 20,
      );
    });

    test('carriage returns alone, and a byte order mark', () {
      attempt(text('module t (input a);\rwire w;\rendmodule\r'));
      expect(
        attempt([0xEF, 0xBB, 0xBF, ...text('module t (input a); endmodule')]),
        isA<NativeReadFallbackOutcome>(),
        reason: 'a byte order mark is not a token the reader knows',
      );
    });

    test('a file name that does not exist, and a directory', () {
      final missing = readGateLevelNetlist(
        NativeReadRequest(sourceFiles: [p.join(dir.path, 'nope.v')]),
      );
      expect(missing, isA<NativeReadFallbackOutcome>());
      final folder = readGateLevelNetlist(
        NativeReadRequest(sourceFiles: [dir.path]),
      );
      expect(folder, isA<NativeReadFallbackOutcome>());
    });

    test('a damaged gzip stream', () {
      final good = gzip.encode(File(fixtures.first).readAsBytesSync());
      for (final bytes in [
        good.sublist(0, good.length ~/ 2),
        [
          ...good.sublist(0, 20),
          ...List<int>.filled(30, 0x55),
          ...good.sublist(50),
        ],
        [0x1f, 0x8b, 8],
      ]) {
        final gz = File(p.join(dir.path, 'x.v.gz'))..writeAsBytesSync(bytes);
        final outcome = readGateLevelNetlist(
          NativeReadRequest(sourceFiles: [gz.path]),
        );
        expect(outcome, isA<NativeReadFallbackOutcome>());
        expect(
          (outcome! as NativeReadFallbackOutcome).message,
          isNot(startsWith('an internal error')),
        );
      }
    });
  });

  test('cancelling a large read stops the worker at once', () async {
    final text = StringBuffer('module t (input a, output y);\n');
    for (var i = 0; i < 400000; i++) {
      text.writeln('  CELL u$i (.A(a), .Y(n$i));');
    }
    text.writeln('endmodule');
    file.writeAsStringSync('$text');
    final clock = Stopwatch()..start();
    final result = await readGateLevelNetlistOnIsolate(
      NativeReadRequest(sourceFiles: [file.path]),
      cancelSignal: Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    expect(result, isNull);
    expect(clock.elapsed, lessThan(const Duration(seconds: 5)));
  });
}
