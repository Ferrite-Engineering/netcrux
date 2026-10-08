// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/annotation.dart';
import 'package:netcrux/domain/models/annotation_target.dart';
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

    test('default constructor produces empty annotations', () {
      const s = NetcruxSession(
        version: NetcruxSession.currentVersion,
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
      expect(s.annotations, isEmpty);
    });

    test('reads version 1 and the current version, rejects others', () {
      expect(NetcruxSession.currentVersion, 2);
      expect(NetcruxSession.readableVersions, <int>{1, 2});
      for (final v in NetcruxSession.readableVersions) {
        expect(
          NetcruxSession.fromJson(<String, Object?>{'version': v}).version,
          v,
        );
      }
      expect(
        () => NetcruxSession.fromJson(const <String, Object?>{'version': 3}),
        throwsA(isA<NetcruxSessionVersionException>()),
      );
    });

    test('round-trips titled and untitled annotations through JSON', () {
      const titled = Annotation(
        id: 'a0',
        targetKind: AnnotationTargetKind.net,
        targetId: 'e_clk',
        title: 'Clock root',
        body: '',
        createdAtMillis: 100,
        updatedAtMillis: 100,
        moduleName: 'top',
      );
      const annotation = Annotation(
        id: 'a1',
        targetKind: AnnotationTargetKind.cell,
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
        annotations: <Annotation>[titled, annotation],
      );
      final json = richSession.toJson();
      expect(json.containsKey('bookmarks'), isFalse);
      final restored = NetcruxSession.fromJson(json);
      expect(restored, equals(richSession));
      expect(restored.annotations, <Annotation>[titled, annotation]);
    });

    test('toJson omits annotations when empty and never writes bookmarks', () {
      final json = session.toJson();
      expect(json.containsKey('bookmarks'), isFalse);
      expect(json.containsKey('annotations'), isFalse);
    });

    test('fromJson silently drops malformed entries', () {
      final json = <String, Object?>{
        'version': 1,
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
          <String, Object?>{
            'id': 'b3',
            'name': 'unknown kind',
            'targetKind': 'transaction',
            'targetId': 'u',
            'createdAtMillis': 3,
          },
        ],
        'annotations': <Object?>[
          <String, Object?>{
            'id': 'a1',
            'targetKind': 'cell',
            'targetId': 'u',
            'body': 'ok',
            'createdAtMillis': 2,
            'updatedAtMillis': 2,
          },
          <String, Object?>{'id': 'no-body'},
        ],
      };
      final restored = NetcruxSession.fromJson(json);
      expect(restored.annotations.map((a) => a.id), <String>['b1', 'a1']);
    });

    group('a version-1 file with bookmarks', () {
      late NetcruxSession restored;

      setUp(() {
        final text = File(
          'test/fixtures/session/legacy_bookmarks_v1.netcrux',
        ).readAsStringSync();
        restored = NetcruxSession.fromJson(
          jsonDecode(text) as Map<String, Object?>,
        );
      });

      test('loads every bookmark as an annotation, in creation order', () {
        expect(restored.version, 1);
        expect(restored.annotations.map((a) => a.id), <String>[
          'bm-1759780000000-0',
          'bm-1759780000100-1',
          'an-1759780000500-2',
        ]);
      });

      test('name becomes the title, note the body, target kept', () {
        final first = restored.annotations[0];
        expect(first.title, 'State register');
        expect(first.body, 'Check the reset value');
        expect(first.targetKind, AnnotationTargetKind.cell);
        expect(first.targetId, r'$procdff$17');
        expect(first.moduleName, 'fsm_lock');
        expect(first.createdAtMillis, 1759780000000);
        expect(first.updatedAtMillis, 1759780000000);
        expect(first.author, isNull);

        final second = restored.annotations[1];
        expect(second.title, 'Unlock input');
        expect(second.body, isEmpty);
        expect(second.targetKind, AnnotationTargetKind.boundaryPort);
        expect(second.targetId, 'port:unlock');
        expect(second.moduleName, isNull);
      });

      test("the file's own annotations load unchanged", () {
        final note = restored.annotations[2];
        expect(note.title, isNull);
        expect(note.body, 'Resets to **IDLE**, not LOCKED.');
        expect(note.author, 'me');
      });

      test('saving writes annotations only, at the current version', () {
        final resaved = NetcruxSession(
          version: NetcruxSession.currentVersion,
          sourceFilePaths: restored.sourceFilePaths,
          topModule: restored.topModule,
          scopePath: restored.scopePath,
          zoom: restored.zoom,
          panX: restored.panX,
          panY: restored.panY,
          selectionJson: restored.selectionJson,
          overlayMode: restored.overlayMode,
          expandedScopeKeys: restored.expandedScopeKeys,
          annotations: restored.annotations,
        ).toJson();
        expect(resaved['version'], 2);
        expect(resaved.containsKey('bookmarks'), isFalse);
        final again = NetcruxSession.fromJson(
          jsonDecode(jsonEncode(resaved)) as Map<String, Object?>,
        );
        expect(again.annotations, restored.annotations);
      });
    });

    test('a bookmark that carried a colour loads, colour dropped', () {
      // The shape a build with a colour field on bookmarks wrote.
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
      expect(restored.annotations.single.title, 'State register');
      expect(restored.annotations.single.body, 'Check the reset value');
      expect(restored.annotations.single.moduleName, isNull);
      final resaved = jsonEncode(restored.toJson());
      expect(resaved, isNot(contains('colorHex')));
      expect(resaved, isNot(contains('"bookmarks"')));
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
