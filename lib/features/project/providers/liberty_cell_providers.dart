// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/models/custom_cell_symbol/custom_cell_symbol.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/schematic/liberty_cell_symbols.dart';
import 'package:netcrux/features/project/providers/current_project_provider.dart';
import 'package:netcrux/features/project/providers/loaded_netlist_provider.dart';
import 'package:netcrux/services/custom_cell_symbols/custom_cell_symbol_registry_provider.dart';
import 'package:netcrux/services/custom_cell_symbols/symbol_supply_pins.dart';
import 'package:netcrux/services/liberty/liberty_cell_index.dart';
import 'package:netcrux/services/liberty/liberty_stub_service_provider.dart';
import 'package:netcrux/services/liberty/module_area_rollup.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'liberty_cell_providers.g.dart';

/// The cells of the tab's Liberty libraries, by name: what the schematic
/// draws them as, and what the Inspector shows about them.
///
/// Read after the design has loaded, through the same on-disk cache the
/// elaboration filled, so a library is parsed once; and read again whenever
/// the design reloads, so an edited library is picked up with it. A tab with
/// no libraries, or a design that failed to load, has
/// [LibertyCellIndex.empty]. A library that cannot be read is left out, as
/// it is for elaboration, which already said so in Diagnostics.
@Riverpod(keepAlive: true)
Future<LibertyCellIndex> libertyCellIndex(Ref ref) async {
  final files = ref.watch(
    currentProjectProvider.select((project) => project.libertyFiles),
  );
  if (files.isEmpty) return LibertyCellIndex.empty;
  final service = ref.read(libertyStubServiceProvider);
  try {
    final model = await _loadedDesign(ref);
    if (model == null) return LibertyCellIndex.empty;
    final loaded = await service.librariesFor(files);
    return LibertyCellIndex(loaded.libraries);
  } on Object {
    return LibertyCellIndex.empty;
  }
}

/// The tab's design once it has loaded, or `null` for a design that failed
/// or has no sources. The caller is built again when the design reloads.
///
/// Waits on a future made here rather than on `loadedNetlistProvider.future`.
/// A future that fails reaches only the listeners in the error zone it was
/// made in, so a provider built in another zone (a frame callback registered
/// elsewhere, a test body) never saw the failure its `try` was waiting for:
/// it stayed loading, and the failure was reported as an uncaught error. This
/// future completes with a value, never an error, so it settles in any zone.
Future<NetlistModel?> _loadedDesign(Ref ref) {
  // Watched, not awaited: it builds the caller again when the design starts
  // loading again, as awaiting it did.
  ref.watch(loadedNetlistProvider.future).ignore();
  final settled = Completer<NetlistModel?>();
  ref.listen(loadedNetlistProvider, (_, design) {
    if (design.isLoading || settled.isCompleted) return;
    settled.complete(design.hasError ? null : design.value);
  }, fireImmediately: true);
  return settled.future;
}

/// How the tab's design draws its cell-library cells (gate symbols, clock
/// wedges, supply pins on the top and bottom faces). Value-equal, so the
/// layout re-runs only when a drawing changes. [LibertyCellSymbols.none]
/// until the design and its libraries are read, or when either fails.
///
/// The supply pins a custom cell symbol names are added for the types whose
/// libraries declare none ([withSymbolSupplyPins]), so the supply rule holds
/// for them too. Open core has no custom symbols, so nothing is added there.
@Riverpod(keepAlive: true)
Future<LibertyCellSymbols> libertyCellSymbols(Ref ref) async {
  final symbols =
      ref.watch(customCellSymbolSnapshotProvider).value ??
      const <String, CustomCellSymbol>{};
  try {
    final model = await _loadedDesign(ref);
    if (model == null) return LibertyCellSymbols.none;
    final index = await ref.watch(libertyCellIndexProvider.future);
    return withSymbolSupplyPins(index.symbolsFor(model), symbols);
  } on Object {
    return LibertyCellSymbols.none;
  }
}

/// The cell area of each module of the tab's design, rolled up from the
/// Liberty `area` of its leaf cells and computed per module when first
/// asked ([ModuleAreaRollup]). `null` while the design or its libraries are
/// loading, and when the tab has no libraries.
@Riverpod(keepAlive: true)
ModuleAreaRollup? moduleAreaRollup(Ref ref) {
  final model = ref.watch(loadedNetlistProvider).value;
  final index = ref.watch(libertyCellIndexProvider).value;
  if (model == null || index == null || index.isEmpty) return null;
  return ModuleAreaRollup(model, index);
}
