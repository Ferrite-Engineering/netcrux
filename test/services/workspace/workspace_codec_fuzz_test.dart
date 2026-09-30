// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_codec.dart';

// Malformed `workspace.json` fuzz sweep.
///
/// [NetcruxWorkspaceCodec.payloadFromJson] must surface a typed
/// [FormatException] for any malformed field and must never throw an uncaught
/// non-[FormatException] error — that is what lets the corrupt-workspace
/// recovery path quarantine a corrupt workspace instead of bricking launch.
void main() {
  const codec = NetcruxWorkspaceCodec();

  // A fully-populated, valid payload map (every optional field present).
  Map<String, Object?> validMap() => <String, Object?>{
    'sourceFiles': <String>['top.v', 'sub.v'],
    'topModule': 'top',
    'projectFilePath': '/p/proj.netcrux',
    'scopePath': <String>['top', 'u_sub'],
    'expandedScopes': <String>['top'],
    'selection': <String, Object?>{'kind': 'cell', 'id': 'u_sub'},
    'overlayMode': 'activity',
    'zoom': 1.5,
    'panX': 12.0,
    'panY': -4.0,
    'sessionExportPath': '/p/sess.netcrux-workspace',
  };

  test('the valid control round-trips without throwing', () {
    final payload = codec.payloadFromJson(validMap());
    expect(payload.sourceFiles, <String>['top.v', 'sub.v']);
    expect(payload.zoom, 1.5);
  });

  group('per-field type violations throw FormatException', () {
    const badValues = <String, Object?>{
      'sourceFiles': 42, // not a list
      'scopePath': 'not-a-list',
      'expandedScopes': 7,
      'selection': <Object?>['not', 'a', 'map'],
      'overlayMode': 99,
      'projectFilePath': <String>[],
      'sessionExportPath': 3.14,
      'topModule': false,
      'zoom': 'fast',
      'panX': 'left',
    };
    for (final entry in badValues.entries) {
      test('"${entry.key}" with a wrong-typed value', () {
        final map = validMap()..[entry.key] = entry.value;
        expect(
          () => codec.payloadFromJson(map),
          throwsA(isA<FormatException>()),
        );
      });
    }

    test('a non-string entry inside sourceFiles', () {
      final map = validMap()..['sourceFiles'] = <Object?>['ok', 5];
      expect(
        () => codec.payloadFromJson(map),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('decode-then-parse fuzz (seeded)', () {
    final validString = jsonEncode(validMap());

    test('every truncation either FormatExceptions or parses', () {
      for (var cut = 0; cut <= validString.length; cut++) {
        final slice = validString.substring(0, cut);
        Object? decoded;
        try {
          decoded = jsonDecode(slice);
        } on FormatException {
          continue; // truncated JSON → typed failure, as required.
        }
        if (decoded is Map<String, Object?>) {
          // A structurally-valid prefix that decoded to a map: parsing it
          // must still only ever throw FormatException, never a raw error.
          try {
            codec.payloadFromJson(decoded);
          } on FormatException {
            // ok
          }
        }
      }
    });

    test('random field mutations never leak a non-FormatException', () {
      final rng = Random(0x5743); // "WC"
      for (var iter = 0; iter < 1000; iter++) {
        final map = validMap();
        // Replace a random field's value with an arbitrary typed value.
        final keys = map.keys.toList();
        final key = keys[rng.nextInt(keys.length)];
        map[key] = <Object?>[
          rng.nextInt(99),
          'x',
          <String, Object?>{'n': rng.nextBool()},
          null,
        ][rng.nextInt(4)];
        try {
          codec.payloadFromJson(map);
        } on FormatException {
          // ok — typed.
        }
      }
    });
  });
}
