// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/services/yosys/streaming_yosys_json_reader.dart';
import 'package:netcrux/services/yosys/yosys_json_parser.dart';

/// Malformed Yosys-JSON fuzz sweep.
///
/// Both the in-memory [YosysJsonParser] and the production streaming
/// [StreamingYosysJsonReader] must, for any input, either return a netlist
/// or throw a typed [YosysJsonParseException] — never a raw `FormatException`
/// / `TypeError`, never a hang, never a half-built netlist. Every case is
/// `Timeout`-wrapped so a hang is a red test, not a stuck CI job.
void main() {
  const inMemory = YosysJsonParser();
  const streaming = StreamingYosysJsonReader();

  // A known-good netlist used as the base for truncation / mutation fuzzing.
  final validJson = File(
    'test/fixtures/verilog/and2.expected.json',
  ).readAsStringSync();

  /// Asserts both parsers reject [raw] with a typed exception (not a raw
  /// error) and do not hang.
  void expectTypedRejection(String raw, {String? reason}) {
    expect(
      () => inMemory.parse(raw),
      throwsA(isA<YosysJsonParseException>()),
      reason: 'in-memory parser must type-reject: ${reason ?? raw}',
    );
    expect(
      () => streaming.parse(raw),
      throwsA(isA<YosysJsonParseException>()),
      reason: 'streaming reader must type-reject: ${reason ?? raw}',
    );
  }

  group('hand-authored malformed corpus', () {
    final dir = Directory('test/fixtures/netlist/malformed/generated');
    final cases = dir
        .listSync()
        .whereType<File>()
        .where(
          (f) =>
              f.path.endsWith('.json') &&
              !f.path.endsWith('.expected_error.json'),
        )
        .toList();

    test('the corpus is present', () {
      expect(cases, isNotEmpty, reason: 'malformed corpus must exist');
    });

    for (final file in cases) {
      final name = file.uri.pathSegments.last;
      test(
        '$name yields the exception its companion documents',
        () {
          expectTypedRejection(file.readAsStringSync(), reason: name);
          // The `.expected_error.json` companion documents the expected
          // failure; assert it agrees (and exists — also enforced by the
          // fixture companion guard).
          final companion = File(
            file.path.replaceFirst('.json', '.expected_error.json'),
          );
          expect(companion.existsSync(), isTrue, reason: 'companion for $name');
          final expected =
              jsonDecode(companion.readAsStringSync()) as Map<String, Object?>;
          expect(expected['expectException'], 'YosysJsonParseException');
        },
        timeout: const Timeout(Duration(seconds: 5)),
      );
    }
  });

  group('programmatic fuzz (seeded)', () {
    test(
      'every truncation point of a valid netlist parses or type-rejects',
      () {
        // Truncating a valid document at any byte boundary must never leak
        // a raw error. The full string is the valid control (parses).
        for (var cut = 0; cut <= validJson.length; cut++) {
          final slice = validJson.substring(0, cut);
          try {
            inMemory.parse(slice);
            streaming.parse(slice);
          } on YosysJsonParseException {
            // Expected for almost every cut — fine.
          }
        }
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'random byte/type mutations never leak a raw error',
      () {
        final rng = Random(0x4e43); // fixed seed "NC" — reproducible.
        final units = validJson.codeUnits.toList();
        for (var iter = 0; iter < 2000; iter++) {
          final mutated = List<int>.of(units);
          // Flip 1–4 random code units to arbitrary printable bytes.
          final flips = 1 + rng.nextInt(4);
          for (var f = 0; f < flips; f++) {
            mutated[rng.nextInt(mutated.length)] = 0x20 + rng.nextInt(0x5e);
          }
          final raw = String.fromCharCodes(mutated);
          // Either parser may succeed (a benign mutation) or throw the
          // typed exception — but never a raw FormatException / TypeError.
          try {
            inMemory.parse(raw);
          } on YosysJsonParseException {
            // ok
          }
          try {
            streaming.parse(raw);
          } on YosysJsonParseException {
            // ok
          }
        }
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'a deeply-nested array is bounded, not a stack overflow (#6)',
      () {
        // 100k-deep nested array inside a connections value. The parser must
        // fail cleanly (typed exception) within the time budget rather than
        // blowing the stack or hanging.
        final deep =
            '{"modules":{"top":{"cells":{"c":{"connections":'
            '${'[' * 100000}${']' * 100000}}}}}}';
        // jsonDecode handles depth iteratively; the assertion is simply that
        // we get a netlist or a typed rejection, never a raw crash / hang.
        try {
          streaming.parse(deep);
          inMemory.parse(deep);
        } on YosysJsonParseException {
          // ok — typed rejection.
        }
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );
  });

  group('mutation-test anchor (invariant #1)', () {
    test('a non-object root throws, proving the root guard bites', () {
      // If the root-type guard in yosys_json_parser.dart is removed, this
      // becomes a raw TypeError escaping instead of YosysJsonParseException.
      expectTypedRejection('[]', reason: 'array root');
      expectTypedRejection('42', reason: 'scalar root');
      expectTypedRejection('"a string"', reason: 'string root');
    });
  });
}
