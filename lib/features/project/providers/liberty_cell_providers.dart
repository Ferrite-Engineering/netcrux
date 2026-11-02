// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/models/schematic/liberty_cell_symbols.dart';
import 'package:netcrux/features/project/providers/current_project_provider.dart';
import 'package:netcrux/features/project/providers/loaded_netlist_provider.dart';
import 'package:netcrux/services/liberty/liberty_cell_index.dart';
import 'package:netcrux/services/liberty/liberty_stub_service_provider.dart';
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
    final model = await ref.watch(loadedNetlistProvider.future);
    if (model == null) return LibertyCellIndex.empty;
    final loaded = await service.librariesFor(files);
    return LibertyCellIndex(loaded.libraries);
  } on Object {
    return LibertyCellIndex.empty;
  }
}

/// How the tab's design draws its cell-library cells (gate symbols, clock
/// wedges, supply pins on the top and bottom faces). Value-equal, so the
/// layout re-runs only when a drawing changes. [LibertyCellSymbols.none]
/// until the design and its libraries are read, or when either fails.
@Riverpod(keepAlive: true)
Future<LibertyCellSymbols> libertyCellSymbols(Ref ref) async {
  try {
    final model = await ref.watch(loadedNetlistProvider.future);
    if (model == null) return LibertyCellSymbols.none;
    final index = await ref.watch(libertyCellIndexProvider.future);
    return index.symbolsFor(model);
  } on Object {
    return LibertyCellSymbols.none;
  }
}
