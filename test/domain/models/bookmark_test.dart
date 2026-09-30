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
      final renamed = original.copyWith(name: 'Renamed', colorHex: '#FF0000');
      expect(renamed.id, 'b1');
      expect(renamed.name, 'Renamed');
      expect(renamed.targetKind, BookmarkTargetKind.cell);
      expect(renamed.colorHex, '#FF0000');
      // Original is unchanged.
      expect(original.name, 'Original');
      expect(original.colorHex, isNull);
    });

    test('toJson + fromJson round-trip', () {
      const bookmark = Bookmark(
        id: 'b1',
        name: 'Reset path',
        targetKind: BookmarkTargetKind.boundaryPort,
        targetId: 'port:reset_n',
        createdAtMillis: 12345,
        colorHex: '#00FF00',
        note: 'Top-level reset',
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
