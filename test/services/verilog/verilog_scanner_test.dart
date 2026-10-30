// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/services/verilog/verilog_scanner.dart';
import 'package:netcrux/services/yosys/chunked_yosys_json_reader.dart';

String _describe(VerilogScanner s) {
  switch (s.kind) {
    case VerilogToken.eof:
      return 'eof@${s.line}.${s.column}';
    case VerilogToken.symbol:
      return '${String.fromCharCode(s.symbol)}@${s.line}.${s.column}-'
          '${s.endLine}.${s.endColumn}';
    default:
      return '${s.kind}:${s.escaped ? r'\' : ''}${s.text}@${s.line}.${s.column}'
          '-${s.endLine}.${s.endColumn}';
  }
}

List<String> _tokens(
  String text, {
  int chunk = 1 << 20,
  int bufferSize = 1 << 12,
  int maxToken = 64,
  bool lenient = false,
}) {
  final scanner = VerilogScanner(
    MemoryChunkSource(
      Uint8List.fromList(utf8.encode(text)),
      maxChunk: chunk,
    ),
    path: 't.v',
    bufferSize: bufferSize,
    maxTokenBytes: maxToken,
    lenientDirectives: lenient,
  );
  final out = <String>[];
  do {
    scanner.next();
    out.add(_describe(scanner));
  } while (scanner.kind != VerilogToken.eof);
  return out;
}

void main() {
  const sample = r'''
// leading comment
`timescale 1ns / 1ps
`celldefine
module top (input a, /* block
comment */ output y);
  (* keep = 1, note = "x" *) wire \esc[3]  ;
  wire [3:0] n;
  assign y = 4'b10x1 ; // tail
  INV u0 (.A(a), .Y(n[0]));  (*)
`endcelldefine
endmodule
''';

  test('tokens, positions and trivia', () {
    final t = _tokens(sample);
    expect(t.first, '1:module@4.1-4.7');
    expect(t, contains(r'1:\esc[3]@6.35-6.42'));
    expect(t, contains("2:4'b10x1@8.14-8.21"));
    // The attribute is skipped; the (*) is two symbols.
    expect(t.where((e) => e.startsWith('wire')), isEmpty);
    expect(t.last, startsWith('eof@'));
  });

  test('chunk boundaries never change the tokens', () {
    final reference = _tokens(sample);
    for (final chunk in [1, 2, 3, 5, 7, 13]) {
      expect(
        _tokens(sample, chunk: chunk, bufferSize: 128, maxToken: 100),
        reference,
        reason: 'chunk $chunk',
      );
    }
  });

  test('a small buffer relocates tokens that straddle its end', () {
    final reference = _tokens(sample);
    for (final size in [24, 25, 31, 40, 64]) {
      expect(
        _tokens(sample, chunk: 5, bufferSize: size, maxToken: 20),
        reference,
        reason: 'buffer $size',
      );
    }
  });

  test('an over-long token is a malformed stop, not a hang', () {
    final long = 'a' * 200;
    expect(
      () => _tokens('module $long ;', bufferSize: 64, maxToken: 32),
      throwsA(
        isA<NativeReaderFallback>().having(
          (e) => e.stop,
          'stop',
          NativeReaderStop.malformed,
        ),
      ),
    );
  });

  test('unterminated comments, attributes and strings are malformed', () {
    for (final bad in ['/* never closed', '(* never closed', '"never closed']) {
      expect(
        () => _tokens(bad, chunk: 3, bufferSize: 32, maxToken: 16),
        throwsA(isA<NativeReaderFallback>()),
        reason: bad,
      );
    }
  });

  test('unknown directives are unsupported unless lenient', () {
    expect(
      () => _tokens('`define X 1\nmodule m;'),
      throwsA(
        isA<NativeReaderFallback>()
            .having((e) => e.stop, 'stop', NativeReaderStop.unsupported)
            .having((e) => e.line, 'line', 1),
      ),
    );
    final t = _tokens('`define X 1 \\\n 2\nmodule m;', lenient: true);
    expect(t.first, startsWith('1:module@3.'));
  });

  test('default_nettype wire is ignored, none is unsupported', () {
    expect(
      _tokens('`default_nettype wire\nmodule').first,
      startsWith('1:module'),
    );
    expect(
      () => _tokens('`default_nettype none\nmodule'),
      throwsA(isA<NativeReaderFallback>()),
    );
  });

  test('interner returns one id per distinct name', () {
    final interner = Interner();
    final scanner = VerilogScanner(
      MemoryChunkSource(
        Uint8List.fromList(utf8.encode(r'a b a \b c a')),
        maxChunk: 4,
      ),
      path: 't.v',
      bufferSize: 64,
      maxTokenBytes: 16,
    );
    final ids = <int>[];
    while (true) {
      scanner.next();
      if (scanner.kind == VerilogToken.eof) break;
      ids.add(scanner.intern(interner));
    }
    expect(ids, [0, 1, 0, 1, 2, 0]);
    expect(interner.stringOf(2), 'c');
    expect(interner.length, 3);
  });
}
