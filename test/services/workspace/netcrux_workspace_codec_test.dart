// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/workspace/netcrux_tab_payload.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_codec.dart';

void main() {
  group('NetcruxWorkspaceCodec', () {
    const codec = NetcruxWorkspaceCodec();

    test('round-trips a fully-populated payload', () {
      const payload = NetcruxTabPayload(
        sourceFiles: ['/d/cpu.v', '/d/mem.v'],
        topModule: 'cpu',
        projectFilePath: '/d/proj.netcrux-project',
        scopePath: ['u_cpu', 'alu'],
        expandedScopeKeys: ['', 'u_cpu', 'u_cpu/alu'],
        selectionJson: {'kind': 'cell', 'id': 'u1'},
        overlayMode: 'fanin',
        zoom: 1.5,
        panX: 12.5,
        panY: -4,
        sessionExportPath: '/d/last.netcrux',
      );
      final json = codec.payloadToJson(payload);
      final decoded = codec.payloadFromJson(json);
      expect(decoded, payload);
    });

    test('round-trips an empty payload', () {
      const payload = NetcruxTabPayload.empty;
      final json = codec.payloadToJson(payload);
      final decoded = codec.payloadFromJson(json);
      expect(decoded, payload);
    });

    test('omits defaulted optional fields from the JSON map', () {
      final json = codec.payloadToJson(NetcruxTabPayload.empty);
      expect(json.keys, contains('sourceFiles'));
      expect(json.containsKey('topModule'), isFalse);
      expect(json.containsKey('scopePath'), isFalse);
      expect(json.containsKey('expandedScopes'), isFalse);
      expect(json.containsKey('selection'), isFalse);
      expect(json.containsKey('overlayMode'), isFalse);
      expect(json.containsKey('zoom'), isFalse);
      expect(json.containsKey('panX'), isFalse);
      expect(json.containsKey('panY'), isFalse);
      expect(json.containsKey('projectFilePath'), isFalse);
      expect(json.containsKey('sessionExportPath'), isFalse);
    });

    test('silently ignores unknown JSON keys for forward compatibility', () {
      final json = <String, Object?>{
        'sourceFiles': ['/d/a.v'],
        'futureField': 42,
      };
      final decoded = codec.payloadFromJson(json);
      expect(decoded.sourceFiles, ['/d/a.v']);
    });

    test('throws FormatException when "sourceFiles" is missing', () {
      expect(
        () => codec.payloadFromJson(const <String, Object?>{}),
        throwsA(isA<FormatException>()),
      );
    });

    test(
      'throws FormatException when "sourceFiles" entries are non-string',
      () {
        expect(
          () => codec.payloadFromJson(<String, Object?>{
            'sourceFiles': <Object?>['/d/a.v', 42],
          }),
          throwsA(isA<FormatException>()),
        );
      },
    );

    test('throws FormatException for bad-typed optional fields', () {
      expect(
        () => codec.payloadFromJson(<String, Object?>{
          'sourceFiles': const <String>['/d/a.v'],
          'overlayMode': 7,
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => codec.payloadFromJson(<String, Object?>{
          'sourceFiles': const <String>['/d/a.v'],
          'zoom': 'not-numeric',
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => codec.payloadFromJson(<String, Object?>{
          'sourceFiles': const <String>['/d/a.v'],
          'selection': 'not-an-object',
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('schemaVersion is 1', () {
      expect(codec.schemaVersion, 1);
    });

    test('displayNameFor mirrors payload.derivedDisplayName', () {
      const payload = NetcruxTabPayload(
        sourceFiles: ['/d/cpu.v'],
        topModule: 'cpu',
      );
      expect(codec.displayNameFor(payload), payload.derivedDisplayName);
    });
  });
}
