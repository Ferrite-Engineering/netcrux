// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/interfaces/custom_cell_symbol_registry.dart';
import 'package:netcrux/domain/models/custom_cell_symbol/custom_cell_symbol.dart';

void main() {
  group('NoopCustomCellSymbolRegistry', () {
    test('snapshot is the empty map', () {
      const registry = NoopCustomCellSymbolRegistry();
      expect(registry.snapshot, isEmpty);
    });

    test('lookup always returns null', () async {
      const registry = NoopCustomCellSymbolRegistry();
      expect(await registry.lookup('any_module'), isNull);
      expect(await registry.lookup(''), isNull);
    });

    test('listAll returns the empty list', () async {
      const registry = NoopCustomCellSymbolRegistry();
      expect(await registry.listAll(), isEmpty);
    });

    test('addOrUpdate is a silent no-op', () async {
      const registry = NoopCustomCellSymbolRegistry();
      const symbol = CustomCellSymbol(
        id: 'noop-symbol',
        moduleType: 'noop_module',
        kind: CustomCellSymbolKind.svg,
        content: '',
        width: 100,
        height: 60,
        portAnchors: {},
        createdAt: '',
        updatedAt: '',
      );
      // Should complete without throwing.
      await registry.addOrUpdate(symbol);
      // Snapshot still empty afterward.
      expect(registry.snapshot, isEmpty);
    });

    test('remove is a silent no-op', () async {
      const registry = NoopCustomCellSymbolRegistry();
      // Unknown id, should complete without throwing.
      await registry.remove('does-not-exist');
    });

    test('changed never emits', () async {
      const registry = NoopCustomCellSymbolRegistry();
      final events = await registry.changed.take(1).toList();
      expect(events, isEmpty);
    });
  });
}
