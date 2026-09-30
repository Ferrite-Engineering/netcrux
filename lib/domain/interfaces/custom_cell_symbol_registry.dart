// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:netcrux/domain/models/custom_cell_symbol/custom_cell_symbol.dart';
import 'package:netcrux/domain/models/custom_cell_symbol/custom_cell_symbol_match.dart';

/// Extension-point registry powering the Custom cell symbols
/// feature.
///
/// Lets users author or import per-module-type symbol overrides
/// (SVG, glyphs, path data) that replace the default rectangular
/// cell rendering on the schematic canvas. The renderer consults the
/// registry through [lookup] (and the cached [snapshot] for the
/// synchronous paint path); the manager UI consults [listAll] and
/// the mutating helpers.
///
/// **Open-core ships [NoopCustomCellSymbolRegistry]** as the
/// registered default. [lookup] always returns `null`, [listAll]
/// returns an empty list, the mutating methods are no-ops, and
/// [changed] never emits. The closed-source Pro overlay
/// registers a `ProCustomCellSymbolRegistry` via `proOverrides` that
/// loads symbols from per-project (`<project>/.netcrux-symbols/`)
/// and per-user (`<appSupportDir>/netcrux/symbols/`) directories,
/// with project-local entries shadowing per-user entries on
/// [CustomCellSymbol.moduleType] collisions.
abstract interface class CustomCellSymbolRegistry {
  /// Synchronous snapshot of every currently-registered symbol,
  /// keyed by [CustomCellSymbol.moduleType]. The schematic painter
  /// reads this on the paint path (paint must stay sync), and the
  /// Pro registry refreshes the snapshot whenever the on-disk
  /// contents change so the rendered output stays current.
  ///
  /// Returns an unmodifiable view; callers must not mutate.
  Map<String, CustomCellSymbol> get snapshot;

  /// Asynchronous lookup. Returns the matched symbol plus the
  /// [CustomCellSymbolMatchKind] used to resolve it, or `null` when
  /// no symbol is bound to [moduleType]. Async to leave room for
  /// future remote / enterprise-registry implementations.
  Future<CustomCellSymbolMatch?> lookup(String moduleType);

  /// Lists every currently-registered symbol. Used by the manager
  /// UI; not on the render path.
  Future<List<CustomCellSymbol>> listAll();

  /// Inserts or replaces [symbol]. The Pro implementation writes
  /// the symbol to its persistent store (per-project by default)
  /// and emits [changed].
  Future<void> addOrUpdate(CustomCellSymbol symbol);

  /// Removes the symbol with id [symbolId]. The Pro implementation
  /// deletes the on-disk file and emits [changed]. Unknown ids are
  /// silently ignored.
  Future<void> remove(String symbolId);

  /// Emits whenever the registry contents change (add, update,
  /// remove, or an on-disk modification picked up by the Pro
  /// watcher). Subscribers (renderer hook, manager UI) listen and
  /// re-read [snapshot] / [listAll] on each event.
  ///
  /// Open-core's no-op default never emits.
  Stream<void> get changed;
}

/// Open-core default: empty registry, mutations are no-ops, change
/// stream is empty.
///
/// The open-core build always has this implementation registered —
/// the schematic renderer's custom-symbol hook returns `null` for
/// every cell, so the built-in `painterFor(CellKind)` path runs
/// unchanged. The Pro overlay replaces this via `proOverrides`.
class NoopCustomCellSymbolRegistry implements CustomCellSymbolRegistry {
  /// Creates the no-op registry.
  const NoopCustomCellSymbolRegistry();

  @override
  Map<String, CustomCellSymbol> get snapshot =>
      const <String, CustomCellSymbol>{};

  @override
  Future<CustomCellSymbolMatch?> lookup(String moduleType) async => null;

  @override
  Future<List<CustomCellSymbol>> listAll() async => const <CustomCellSymbol>[];

  @override
  Future<void> addOrUpdate(CustomCellSymbol symbol) async {}

  @override
  Future<void> remove(String symbolId) async {}

  @override
  Stream<void> get changed => const Stream<void>.empty();
}
