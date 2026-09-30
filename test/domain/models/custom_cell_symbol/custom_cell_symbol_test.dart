// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/custom_cell_symbol/custom_cell_symbol.dart';
import 'package:netcrux/domain/models/custom_cell_symbol/port_anchor.dart';

CustomCellSymbol _fixtureSymbol({String id = 'symbol-1'}) {
  return CustomCellSymbol(
    id: id,
    moduleType: 'my_alu',
    kind: CustomCellSymbolKind.svg,
    content: '<svg xmlns="http://www.w3.org/2000/svg"/>',
    width: 120,
    height: 80,
    portAnchors: const <String, PortAnchor>{
      'A': PortAnchor(x: 0, y: 0.25, side: PortAnchorSide.left),
      'B': PortAnchor(x: 0, y: 0.75, side: PortAnchorSide.left),
      'Y': PortAnchor(x: 1, y: 0.5, side: PortAnchorSide.right),
    },
    createdAt: '2026-05-25T10:00:00Z',
    updatedAt: '2026-05-25T10:00:00Z',
    author: 'mfink',
    notes: 'IEEE ALU shape',
  );
}

void main() {
  group('CustomCellSymbol', () {
    test('equality is field-by-field including port anchors', () {
      final a = _fixtureSymbol();
      final b = _fixtureSymbol();
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('changing any port anchor breaks equality', () {
      final a = _fixtureSymbol();
      final b = a.copyWith(
        portAnchors: <String, PortAnchor>{
          ...a.portAnchors,
          'A': const PortAnchor(x: 0.1, y: 0.1, side: PortAnchorSide.top),
        },
      );
      expect(a, isNot(equals(b)));
    });

    test('copyWith preserves unchanged fields', () {
      final a = _fixtureSymbol();
      final b = a.copyWith();
      expect(b, equals(a));
    });

    test('copyWith.clearAuthor / clearNotes nulls the optional fields', () {
      final a = _fixtureSymbol();
      final b = a.copyWith(clearAuthor: true, clearNotes: true);
      expect(b.author, isNull);
      expect(b.notes, isNull);
    });

    test('toJson round-trip preserves every field', () {
      final a = _fixtureSymbol();
      final json = a.toJson();
      final b = CustomCellSymbol.fromJson(json);
      expect(b, equals(a));
    });

    test('toJson omits author + notes when null', () {
      final a = _fixtureSymbol().copyWith(clearAuthor: true, clearNotes: true);
      final json = a.toJson();
      expect(json.containsKey('author'), isFalse);
      expect(json.containsKey('notes'), isFalse);
    });

    test('fromJson uses sensible defaults for missing fields', () {
      final symbol = CustomCellSymbol.fromJson(const <String, Object?>{});
      expect(symbol.id, isEmpty);
      expect(symbol.moduleType, isEmpty);
      expect(symbol.kind, CustomCellSymbolKind.svg);
      expect(symbol.content, isEmpty);
      expect(symbol.width, 100);
      expect(symbol.height, 60);
      expect(symbol.portAnchors, isEmpty);
      expect(symbol.author, isNull);
      expect(symbol.notes, isNull);
    });

    test('fromJson tolerates unknown kind values', () {
      final symbol = CustomCellSymbol.fromJson(const <String, Object?>{
        'id': 'x',
        'moduleType': 't',
        'kind': 'this-does-not-exist',
        'content': '',
        'width': 100,
        'height': 60,
        'createdAt': '',
        'updatedAt': '',
      });
      expect(symbol.kind, CustomCellSymbolKind.svg);
    });

    test('fromJson silently drops malformed port-anchor entries', () {
      final symbol = CustomCellSymbol.fromJson(const <String, Object?>{
        'id': 'x',
        'moduleType': 't',
        'kind': 'svg',
        'content': '',
        'width': 100,
        'height': 60,
        'createdAt': '',
        'updatedAt': '',
        'portAnchors': <String, Object?>{
          'A': <String, Object?>{
            'x': 0.1,
            'y': 0.2,
            'side': 'left',
          },
          'B': 'not-a-map',
        },
      });
      expect(symbol.portAnchors.keys, <String>{'A'});
    });

    test('toString carries the moduleType for diagnostic logs', () {
      final symbol = _fixtureSymbol();
      expect(symbol.toString(), contains('my_alu'));
    });
  });

  group('CustomCellSymbolKind', () {
    test('enum values cover the v1 surface', () {
      expect(
        CustomCellSymbolKind.values,
        containsAll(<CustomCellSymbolKind>[
          CustomCellSymbolKind.svg,
          CustomCellSymbolKind.path,
          CustomCellSymbolKind.builtinGlyph,
        ]),
      );
    });
  });
}
