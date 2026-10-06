// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/bookmark.dart';

void main() {
  group('Bookmark', () {
    test('equality + hashCode', () {
      const a = Bookmark(
        id: 'b1',
        name: 'Clock root',
        targetKind: BookmarkTargetKind.net,
        targetId: 'e_clk',
        createdAtMillis: 1000,
      );
      const b = Bookmark(
        id: 'b1',
        name: 'Clock root',
        targetKind: BookmarkTargetKind.net,
        targetId: 'e_clk',
        createdAtMillis: 1000,
      );
      const c = Bookmark(
        id: 'b1',
        name: 'Clock root',
        targetKind: BookmarkTargetKind.net,
        targetId: 'e_clk',
        createdAtMillis: 2000,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('copyWith replaces selected fields', () {
      const original = Bookmark(
        id: 'b1',
        name: 'Original',
        targetKind: BookmarkTargetKind.cell,
        targetId: 'u_alu',
        createdAtMillis: 100,
      );
      final renamed = original.copyWith(name: 'Renamed', moduleName: 'alu');
      expect(renamed.id, 'b1');
      expect(renamed.name, 'Renamed');
      expect(renamed.targetKind, BookmarkTargetKind.cell);
      expect(renamed.moduleName, 'alu');
      // Original is unchanged.
      expect(original.name, 'Original');
      expect(original.moduleName, isNull);
    });

    test('toJson + fromJson round-trip', () {
      const bookmark = Bookmark(
        id: 'b1',
        name: 'Reset path',
        targetKind: BookmarkTargetKind.boundaryPort,
        targetId: 'port:reset_n',
        createdAtMillis: 12345,
        note: 'Top-level reset',
        moduleName: 'top',
      );
      final json = bookmark.toJson();
      final restored = Bookmark.fromJson(json);
      expect(restored, equals(bookmark));
    });

    test('toJson omits null optional fields', () {
      const bookmark = Bookmark(
        id: 'b1',
        name: 'x',
        targetKind: BookmarkTargetKind.scope,
        targetId: 'top.cpu',
        createdAtMillis: 1,
      );
      final json = bookmark.toJson();
      expect(json.containsKey('colorHex'), isFalse);
      expect(json.containsKey('note'), isFalse);
      expect(json.containsKey('moduleName'), isFalse);
    });

    test('carries no colour: toJson never writes colorHex', () {
      const bookmark = Bookmark(
        id: 'b1',
        name: 'x',
        targetKind: BookmarkTargetKind.cell,
        targetId: 'u_alu',
        createdAtMillis: 1,
        note: 'n',
        moduleName: 'top',
      );
      expect(bookmark.toJson().keys, isNot(contains('colorHex')));
    });

    test('fromJson ignores a colorHex written by an older build', () {
      final restored = Bookmark.fromJson(const <String, Object?>{
        'id': 'b1',
        'name': 'Clock root',
        'targetKind': 'net',
        'targetId': 'e_4_0',
        'createdAtMillis': 100,
        'colorHex': '#FFCC00',
        'note': 'CDC suspect',
      });
      expect(
        restored,
        const Bookmark(
          id: 'b1',
          name: 'Clock root',
          targetKind: BookmarkTargetKind.net,
          targetId: 'e_4_0',
          createdAtMillis: 100,
          note: 'CDC suspect',
        ),
      );
      expect(restored!.toJson().keys, isNot(contains('colorHex')));
    });

    test('fromJson ignores a malformed colorHex instead of failing', () {
      final restored = Bookmark.fromJson(const <String, Object?>{
        'id': 'b1',
        'name': 'x',
        'targetKind': 'cell',
        'targetId': 'u_alu',
        'createdAtMillis': 1,
        'colorHex': 42,
      });
      expect(restored, isNotNull);
      expect(restored!.name, 'x');
    });

    test('fromJson treats an empty or non-string moduleName as absent', () {
      for (final value in <Object?>['', 7, null]) {
        final restored = Bookmark.fromJson(<String, Object?>{
          'id': 'b1',
          'name': 'x',
          'targetKind': 'cell',
          'targetId': 'u_alu',
          'createdAtMillis': 1,
          'moduleName': value,
        });
        expect(restored!.moduleName, isNull, reason: '$value');
      }
    });

    test('moduleName takes part in equality', () {
      const a = Bookmark(
        id: 'b1',
        name: 'x',
        targetKind: BookmarkTargetKind.cell,
        targetId: 'u_fifo',
        createdAtMillis: 1,
        moduleName: 'rx',
      );
      expect(a, isNot(a.copyWith(moduleName: 'tx')));
    });

    test('fromJson returns null on missing required fields', () {
      expect(
        Bookmark.fromJson(const <String, Object?>{'id': 'b1'}),
        isNull,
      );
      expect(
        Bookmark.fromJson(const <String, Object?>{
          'id': '',
          'name': 'x',
          'targetKind': 'cell',
          'targetId': 'u',
          'createdAtMillis': 1,
        }),
        isNull,
      );
    });

    test('fromJson returns null on unknown targetKind', () {
      expect(
        Bookmark.fromJson(const <String, Object?>{
          'id': 'b1',
          'name': 'x',
          'targetKind': 'transaction',
          'targetId': 'u',
          'createdAtMillis': 1,
        }),
        isNull,
      );
    });

    test('every BookmarkTargetKind value round-trips through JSON', () {
      for (final kind in BookmarkTargetKind.values) {
        final bookmark = Bookmark(
          id: 'b-${kind.name}',
          name: kind.name,
          targetKind: kind,
          targetId: 'tid',
          createdAtMillis: 1,
        );
        final restored = Bookmark.fromJson(bookmark.toJson());
        expect(restored, equals(bookmark), reason: 'kind=$kind');
      }
    });
  });
}
