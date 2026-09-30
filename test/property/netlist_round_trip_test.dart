// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/services/yosys/streaming_yosys_json_reader.dart';
import 'package:path/path.dart' as p;

/// Property tests verifying that the elaboration pipeline round-trips
/// cleanly: parse → re-emit → re-parse → assert structural equality.
///
/// These tests cover the parser ↔ emitter path that the JSON export
/// controller relies on.
///
/// Coverage:
///
/// - All three hand-crafted pipeline fixtures (and2, adder4, fsm).
/// - One larger synthesized fixture (`large_chain.expected.json`)
///   committed alongside that set — 32 cells in a chain, far
///   beyond the and2 / adder4 baseline.
///
/// The fixtures are `*.expected.json` files: hand-crafted minimal
/// Yosys-shaped documents that the streaming reader and the
/// `Module.toJson` emitter share without involving the real yosys
/// binary. That keeps the property tests runnable in any
/// environment.
void main() {
  group('NetlistModel round-trip — parse → emit → re-parse', () {
    const reader = StreamingYosysJsonReader();

    Future<void> roundTripFixture(String fixtureName) async {
      final path = p.join(
        Directory.current.path,
        'test',
        'fixtures',
        'verilog',
        fixtureName,
      );
      final original = await File(path).readAsString();
      final first = reader.parse(original);
      // Emit using the same `module.toJson()` API the export
      // controller uses.
      final reEmitted = <String, Object?>{
        'creator': first.creator,
        'modules': <String, Object?>{
          for (final entry in first.modules.entries)
            entry.key: entry.value.toJson(),
        },
      };
      const encoder = JsonEncoder.withIndent('  ');
      final reEmittedString = encoder.convert(reEmitted);
      final second = reader.parse(reEmittedString);
      _expectEqual(first, second, fixtureName);
    }

    test('and2 fixture', () => roundTripFixture('and2.expected.json'));
    test('adder4 fixture', () => roundTripFixture('adder4.expected.json'));
    test('fsm fixture', () => roundTripFixture('fsm.expected.json'));
    test(
      'large_chain fixture (32 cells)',
      () => roundTripFixture('large_chain.expected.json'),
    );
  });
}

/// Structural-equality check that explains a mismatch precisely so a
/// future regression in the emitter (or the parser) lands a useful
/// diagnostic instead of a generic `Expected: <model>` dump.
void _expectEqual(NetlistModel a, NetlistModel b, String fixtureName) {
  expect(
    a.creator,
    b.creator,
    reason: 'creator differs for $fixtureName',
  );
  expect(
    a.modules.keys.toSet(),
    b.modules.keys.toSet(),
    reason: 'module-name set differs for $fixtureName',
  );
  for (final name in a.modules.keys) {
    final m1 = a.modules[name]!;
    final m2 = b.modules[name]!;
    expect(
      m1,
      m2,
      reason: 'module $name differs in $fixtureName',
    );
  }
}
