// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/annotation.dart';
import 'package:netcrux/domain/models/bookmark.dart';
import 'package:netcrux/domain/models/session/netcrux_session.dart';

void main() {
  group('NetcruxSession', () {
    const session = NetcruxSession(
      version: NetcruxSession.currentVersion,
      sourceFilePaths: <String>['/a.v', '/b.sv'],
      topModule: 'top',
      scopePath: <String>['u_cpu', 'alu'],
      zoom: 1.25,
      panX: 12.5,
      panY: -8,
      selectionJson: <String, Object?>{'kind': 'cell', 'cellId': 'u_alu'},
      overlayMode: 'fanin',
      expandedScopeKeys: <String>['', 'u_cpu'],
    );

    test('JSON round-trip preserves every field', () {
      final json = session.toJson();
      final restored = NetcruxSession.fromJson(json);
      expect(restored, equals(session));
    });

    test('fromJson rejects missing version', () {
      expect(
        () => NetcruxSession.fromJson(const <String, Object?>{}),
        throwsA(isA<NetcruxSessionFormatException>()),
      );
    });

    test('fromJson rejects unknown version', () {
      expect(
        () => NetcruxSession.fromJson(const <String, Object?>{'version': 99}),
        throwsA(
          isA<NetcruxSessionVersionException>().having(
            (e) => e.version,
            'version',
            99,
          ),
        ),
      );
    });

    test('fromJson tolerates unknown fields silently', () {
      final json = session.toJson()..['futureField'] = <String, dynamic>{};
      final restored = NetcruxSession.fromJson(json);
      expect(restored, equals(session));
    });

    test('omitting optional fields produces defaults', () {
      final restored = NetcruxSession.fromJson(const <String, Object?>{
        'version': NetcruxSession.currentVersion,
      });
      expect(restored.sourceFilePaths, isEmpty);
      expect(restored.scopePath, isEmpty);
      expect(restored.expandedScopeKeys, isEmpty);
      expect(restored.zoom, 1);
      expect(restored.selectionJson, isNull);
      expect(restored.overlayMode, isNull);
    });

    test('default constructor produces empty bookmarks + annotations', () {
      const s = NetcruxSession(
        version: 1,
        sourceFilePaths: <String>[],
        topModule: '',
        scopePath: <String>[],
        zoom: 1,
        panX: 0,
        panY: 0,
        selectionJson: null,
        overlayMode: null,
        expandedScopeKeys: <String>[],
      );
      expect(s.bookmarks, isEmpty);
      expect(s.annotations, isEmpty);
    });

    test('round-trips bookmarks + annotations through JSON', () {
      const bookmark = Bookmark(
        id: 'b1',
        name: 'Clock root',
        targetKind: BookmarkTargetKind.net,
        targetId: 'e_clk',
        createdAtMillis: 100,
        note: 'CDC suspect',
        moduleName: 'top',
      );
      const annotation = Annotation(
        id: 'a1',
        targetKind: BookmarkTargetKind.cell,
        targetId: 'u_alu',
        body: '# Note\nALU output is glitchy at reset.',
        createdAtMillis: 200,
        updatedAtMillis: 200,
        author: 'martin',
      );
      const richSession = NetcruxSession(
        version: NetcruxSession.currentVersion,
        sourceFilePaths: <String>['/tmp/a.v'],
        topModule: 'top',
        scopePath: <String>['u_cpu', 'alu'],
        zoom: 1.5,
        panX: 10,
        panY: 20,
        selectionJson: null,
        overlayMode: 'fanin',
        expandedScopeKeys: <String>['u_cpu'],
        bookmarks: <Bookmark>[bookmark],
        annotations: <Annotation>[annotation],
      );
      final restored = NetcruxSession.fromJson(richSession.toJson());
      expect(restored, equals(richSession));
      expect(restored.bookmarks.single, bookmark);
      expect(restored.annotations.single, annotation);
    });

    test(
      'toJson omits bookmarks + annotations when empty (forward compat)',
      () {
        final json = session.toJson();
        expect(json.containsKey('bookmarks'), isFalse);
        expect(json.containsKey('annotations'), isFalse);
      },
    );

    test(
      'fromJson silently drops malformed bookmark / annotation entries',
      () {
        final json = <String, Object?>{
          'version': NetcruxSession.currentVersion,
          'sourceFiles': <String>[],
          'topModule': '',
          'scopePath': <String>[],
          'zoom': 1,
          'panX': 0,
          'panY': 0,
          'expandedScopes': <String>[],
          'bookmarks': <Object?>[
            <String, Object?>{
              'id': 'b1',
              'name': 'ok',
              'targetKind': 'cell',
              'targetId': 'u',
              'createdAtMillis': 1,
            },
            'not-a-map',
            <String, Object?>{'id': 'no-name-no-kind'},
          ],
          'annotations': <Object?>[
            <String, Object?>{
              'id': 'a1',
              'targetKind': 'cell',
              'targetId': 'u',
              'body': 'ok',
              'createdAtMillis': 1,
              'updatedAtMillis': 1,
            },
            <String, Object?>{'id': 'no-body'},
          ],
        };
        final restored = NetcruxSession.fromJson(json);
        expect(restored.bookmarks, hasLength(1));
        expect(restored.bookmarks.single.id, 'b1');
        expect(restored.annotations, hasLength(1));
        expect(restored.annotations.single.id, 'a1');
      },
    );

    test('a session whose bookmarks carry a colour loads, colour dropped', () {
      // The shape a build with the bookmark Color field wrote.
      final json =
          jsonDecode(r'''
{
  "version": 1,
  "sourceFiles": ["/tmp/fsm_lock.v"],
  "topModule": "fsm_lock",
  "scopePath": [],
  "zoom": 1.0,
  "panX": 0.0,
  "panY": 0.0,
  "expandedScopes": [],
  "bookmarks": [
    {
      "id": "b1",
      "name": "State register",
      "targetKind": "cell",
      "targetId": "$procdff$17",
      "createdAtMillis": 100,
      "colorHex": "#FF8800",
      "note": "Check the reset value"
    }
  ]
}
''')
              as Map<String, Object?>;
      final restored = NetcruxSession.fromJson(json);
      expect(restored.bookmarks.single.name, 'State register');
      expect(restored.bookmarks.single.note, 'Check the reset value');
      expect(restored.bookmarks.single.moduleName, isNull);
      final resaved = jsonEncode(restored.toJson());
      expect(resaved, isNot(contains('colorHex')));
      expect(resaved, contains(r'$procdff$17'));
    });

    test('equality / hashCode', () {
      const a = NetcruxSession(
        version: 1,
        sourceFilePaths: <String>[],
        topModule: 'top',
        scopePath: <String>[],
        zoom: 1,
        panX: 0,
        panY: 0,
        selectionJson: null,
        overlayMode: null,
        expandedScopeKeys: <String>[],
      );
      const b = NetcruxSession(
        version: 1,
        sourceFilePaths: <String>[],
        topModule: 'top',
        scopePath: <String>[],
        zoom: 1,
        panX: 0,
        panY: 0,
        selectionJson: null,
        overlayMode: null,
        expandedScopeKeys: <String>[],
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });
  });
}
