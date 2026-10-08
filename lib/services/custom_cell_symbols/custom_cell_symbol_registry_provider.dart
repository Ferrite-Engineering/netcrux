// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/interfaces/custom_cell_symbol_registry.dart';
import 'package:netcrux/domain/models/custom_cell_symbol/custom_cell_symbol.dart';

/// Riverpod provider exposing the active [CustomCellSymbolRegistry].
///
/// Open-core resolves this to [NoopCustomCellSymbolRegistry] — every
/// lookup returns `null`, the manager UI sees an empty list, and the
/// schematic renderer falls through to the built-in cell painters.
/// The closed-source Pro overlay registers a concrete
/// `ProCustomCellSymbolRegistry` via `proOverrides`.
///
/// Declared as a manual `Provider` (not `@Riverpod`-codegen) so the
/// Pro overlay can override it with `.overrideWith` without taking
/// the build_runner generator dep. Matches the
/// [netlistDiffServiceProvider] / [sourcePaneServiceProvider] /
/// [coneOfInfluenceServiceProvider] / [xTraceServiceProvider] /
/// [annotationStoreProvider] pattern.
final customCellSymbolRegistryProvider = Provider<CustomCellSymbolRegistry>(
  (ref) => const NoopCustomCellSymbolRegistry(),
  name: 'customCellSymbolRegistryProvider',
);

/// Synchronous snapshot of the active registry's currently-known
/// symbols, keyed by [CustomCellSymbol.moduleType]. Wraps the
/// registry's [CustomCellSymbolRegistry.snapshot] getter inside a
/// reactive provider so widgets and the renderer can `ref.watch` it
/// and rebuild whenever the underlying registry emits on its
/// [CustomCellSymbolRegistry.changed] stream.
///
/// Open-core returns the empty map. The Pro overlay's registry
/// refreshes this snapshot via its `changed` stream so the schematic
/// repaints whenever a symbol is added, edited, or removed.
final customCellSymbolSnapshotProvider =
    StreamProvider<Map<String, CustomCellSymbol>>(
      (ref) {
        final registry = ref.watch(customCellSymbolRegistryProvider);
        return _watchRegistry(registry);
      },
      name: 'customCellSymbolSnapshotProvider',
    );

/// Yields the current registry [CustomCellSymbolRegistry.snapshot]
/// once eagerly, then one fresh snapshot per
/// [CustomCellSymbolRegistry.changed] event. Implemented as an
/// `async*` that prefixes the initial value before subscribing to
/// the broadcast change stream so the StreamProvider always has at
/// least one value to expose via its `.future` getter even when the
/// underlying registry never emits (the open-core no-op case).
Stream<Map<String, CustomCellSymbol>> _watchRegistry(
  CustomCellSymbolRegistry registry,
) {
  final controller = StreamController<Map<String, CustomCellSymbol>>();
  // Seed the stream with the current snapshot so listeners see a
  // value on first subscription. Scheduled via a microtask so we
  // emit *after* the listener attaches; emitting from inside the
  // constructor would lose the event.
  scheduleMicrotask(() {
    if (!controller.isClosed) controller.add(registry.snapshot);
  });
  final subscription = registry.changed.listen((_) {
    if (!controller.isClosed) controller.add(registry.snapshot);
  });
  controller.onCancel = () async {
    await subscription.cancel();
    await controller.close();
  };
  return controller.stream;
}
