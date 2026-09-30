// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/features/project/providers/loaded_netlist_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'netlist_footprint_provider.g.dart';

/// What one tab's elaborated design is holding
/// (App Diagnostics → Memory).
///
/// **Counts, not bytes.** There is no way to ask the Dart VM what a
/// [NetlistModel] object graph costs, and a byte figure computed from a
/// per-element guess would be a fabrication wearing the uniform of a
/// measurement — precisely the kind of number a user would then quote in a
/// bug report. Cells and nets are what actually scale with a design, they
/// are what the user recognises, and comparing them across tabs answers the
/// question the section exists to answer: which tab is the heavy one.
///
/// Process-wide RSS is reported separately and *is* a real measurement.
@immutable
class NetlistFootprint {
  /// Creates a footprint.
  const NetlistFootprint({
    required this.modules,
    required this.cells,
    required this.nets,
  });

  /// The no-design footprint.
  static const NetlistFootprint empty = NetlistFootprint(
    modules: 0,
    cells: 0,
    nets: 0,
  );

  /// Modules in the elaboration.
  final int modules;

  /// Cells summed across every module.
  final int cells;

  /// Nets summed across every module.
  final int nets;

  /// Whether this tab holds an elaborated design at all.
  bool get hasDesign => modules > 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NetlistFootprint &&
          other.modules == modules &&
          other.cells == cells &&
          other.nets == nets);

  @override
  int get hashCode => Object.hash(modules, cells, nets);

  @override
  String toString() =>
      'NetlistFootprint(modules: $modules, cells: $cells, nets: $nets)';
}

/// This tab's netlist footprint. Per-tab — registered in
/// `netcruxTabOverridesFactory` alongside its source, `loadedNetlistProvider`.
///
/// A failed or in-flight elaboration reports [NetlistFootprint.empty] rather
/// than the previous design's numbers: the table says what the tab is
/// holding now, and a stale row would make a tab look heavier than it is.
@Riverpod(keepAlive: true)
NetlistFootprint netlistFootprint(Ref ref) {
  final model = ref.watch(loadedNetlistProvider).value;
  if (model == null) return NetlistFootprint.empty;
  var cells = 0;
  var nets = 0;
  for (final module in model.modules.values) {
    cells += module.cells.length;
    nets += module.nets.length;
  }
  return NetlistFootprint(
    modules: model.modules.length,
    cells: cells,
    nets: nets,
  );
}
