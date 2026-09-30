// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

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
        colorHex: '#FFCC00',
        note: 'CDC suspect',
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
