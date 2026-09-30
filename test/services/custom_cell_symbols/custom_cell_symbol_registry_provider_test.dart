// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/interfaces/custom_cell_symbol_registry.dart';
import 'package:netcrux/domain/models/custom_cell_symbol/custom_cell_symbol.dart';
import 'package:netcrux/domain/models/custom_cell_symbol/custom_cell_symbol_match.dart';
import 'package:netcrux/services/custom_cell_symbols/custom_cell_symbol_registry_provider.dart';

class _RecordingRegistry implements CustomCellSymbolRegistry {
  _RecordingRegistry({Map<String, CustomCellSymbol>? seed})
    : _snapshot = Map<String, CustomCellSymbol>.from(
        seed ?? const <String, CustomCellSymbol>{},
      );

  Map<String, CustomCellSymbol> _snapshot;
  final StreamController<void> _changed = StreamController<void>.broadcast();
  bool addCalled = false;
  bool removeCalled = false;

  @override
  Map<String, CustomCellSymbol> get snapshot =>
      Map<String, CustomCellSymbol>.unmodifiable(_snapshot);

  @override
  Future<CustomCellSymbolMatch?> lookup(String moduleType) async {
    final symbol = _snapshot[moduleType];
    if (symbol == null) return null;
    return CustomCellSymbolMatch(
      symbol: symbol,
      kind: CustomCellSymbolMatchKind.exactMatch,
    );
  }

  @override
  Future<List<CustomCellSymbol>> listAll() async => _snapshot.values.toList();

  @override
  Future<void> addOrUpdate(CustomCellSymbol symbol) async {
    addCalled = true;
    _snapshot = <String, CustomCellSymbol>{
      ..._snapshot,
      symbol.moduleType: symbol,
    };
    _changed.add(null);
  }

  @override
  Future<void> remove(String symbolId) async {
    removeCalled = true;
    _snapshot = <String, CustomCellSymbol>{
      for (final entry in _snapshot.entries)
        if (entry.value.id != symbolId) entry.key: entry.value,
    };
    _changed.add(null);
  }

  @override
  Stream<void> get changed => _changed.stream;

  Future<void> dispose() => _changed.close();
}

void main() {
  test('customCellSymbolRegistryProvider defaults to the no-op registry', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(
      c.read(customCellSymbolRegistryProvider),
      isA<NoopCustomCellSymbolRegistry>(),
    );
  });

  test('customCellSymbolRegistryProvider accepts overrides', () async {
    final test = _RecordingRegistry();
    addTearDown(test.dispose);
    final c = ProviderContainer(
      overrides: <Override>[
        customCellSymbolRegistryProvider.overrideWithValue(test),
      ],
    );
    addTearDown(c.dispose);
    expect(c.read(customCellSymbolRegistryProvider), same(test));

    await c
        .read(customCellSymbolRegistryProvider)
        .addOrUpdate(
          const CustomCellSymbol(
            id: 'sx',
            moduleType: 'mx',
            kind: CustomCellSymbolKind.svg,
            content: '<svg/>',
            width: 100,
            height: 60,
            portAnchors: {},
            createdAt: '',
            updatedAt: '',
          ),
        );
    expect(test.addCalled, isTrue);
  });

  test(
    'customCellSymbolSnapshotProvider emits empty by default for the noop '
    'registry',
    () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      // Subscribe via listen so the StreamProvider eagerly opens its
      // subscription (read(.future) on a never-listened StreamProvider
      // can park forever on some Riverpod versions). Once listening,
      // the .future resolves with the first emission.
      final sub = c.listen(
        customCellSymbolSnapshotProvider,
        (_, _) {},
      );
      addTearDown(sub.close);
      final snapshot = await c
          .read(customCellSymbolSnapshotProvider.future)
          .timeout(const Duration(seconds: 2));
      expect(snapshot, isEmpty);
    },
  );

  test(
    'customCellSymbolSnapshotProvider re-emits whenever the active registry '
    'changes',
    () async {
      final test = _RecordingRegistry(
        seed: const <String, CustomCellSymbol>{
          'm1': CustomCellSymbol(
            id: 's1',
            moduleType: 'm1',
            kind: CustomCellSymbolKind.svg,
            content: '<svg/>',
            width: 100,
            height: 60,
            portAnchors: {},
            createdAt: '',
            updatedAt: '',
          ),
        },
      );
      addTearDown(test.dispose);
      final c = ProviderContainer(
        overrides: <Override>[
          customCellSymbolRegistryProvider.overrideWithValue(test),
        ],
      );
      addTearDown(c.dispose);

      // Subscribe with a listener and collect new values. The
      // fireImmediately argument seeds an initial "loading" tick the
      // collector ignores; only `whenData` emissions land in the
      // received list.
      final received = <Map<String, CustomCellSymbol>>[];
      final sub = c.listen<AsyncValue<Map<String, CustomCellSymbol>>>(
        customCellSymbolSnapshotProvider,
        (_, next) {
          next.whenData(received.add);
        },
        fireImmediately: true,
      );
      addTearDown(sub.close);

      // Let the seeded snapshot emission flush.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(received.isNotEmpty, isTrue);
      expect(received.first.keys, <String>{'m1'});

      // Mutate; the StreamProvider should emit a fresh value.
      await c
          .read(customCellSymbolRegistryProvider)
          .addOrUpdate(
            const CustomCellSymbol(
              id: 's2',
              moduleType: 'm2',
              kind: CustomCellSymbolKind.svg,
              content: '<svg/>',
              width: 100,
              height: 60,
              portAnchors: {},
              createdAt: '',
              updatedAt: '',
            ),
          );
      // Let the StreamController tick.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(received, isNotEmpty);
      expect(received.last.keys, containsAll(<String>['m1', 'm2']));
    },
  );
}
