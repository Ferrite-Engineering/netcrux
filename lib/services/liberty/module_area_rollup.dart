// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/services/liberty/liberty_cell_index.dart';

/// The cell area of one module: the Liberty `area` of every leaf cell under
/// it, summed through its submodules.
@immutable
class ModuleArea {
  /// Creates an area.
  const ModuleArea({required this.area, required this.partial});

  /// The sum of the areas that are known, in the library's units.
  final double area;

  /// Whether some leaf cell has no known area: a cell no library defines
  /// (a Yosys primitive, a black box), a library cell without an `area`, or
  /// an instance of a module that instantiates itself. [area] then counts
  /// only the rest.
  final bool partial;

  /// Whether any leaf had an area at all. A module with none says nothing
  /// about area, rather than "0, partial".
  bool get isKnown => area > 0;

  @override
  bool operator ==(Object other) =>
      other is ModuleArea && other.area == area && other.partial == partial;

  @override
  int get hashCode => Object.hash(area, partial);

  @override
  String toString() => 'ModuleArea($area${partial ? ', partial' : ''})';
}

/// Rolls the Liberty `area` of leaf cells up the hierarchy of [model], one
/// module at a time and only when asked: [areaOf] computes a module's area
/// on first request, from its own cells and the memoised areas of the
/// modules it instantiates, and keeps it. Every instance of a module has
/// the same area, so each module is summed once however often it is
/// instantiated.
///
/// The cost is one pass over the cells of each module asked about and of the
/// modules below it, counted by type first so a module of a million cells
/// of thirty types looks up thirty types, not a million.
class ModuleAreaRollup {
  /// Creates a roll-up over [model] with the cell areas of [index].
  ModuleAreaRollup(this.model, this.index);

  /// The design.
  final NetlistModel model;

  /// The cell libraries.
  final LibertyCellIndex index;

  /// Cells Yosys writes that record something about the design rather than
  /// stand for hardware: they have no area, known or unknown.
  static const Set<String> _bookkeepingTypes = <String>{
    r'$scopeinfo',
    r'$meminit',
    r'$meminit_v2',
  };

  final Map<String, ModuleArea> _byModule = <String, ModuleArea>{};
  final Set<String> _inProgress = <String>{};

  /// The area of the module named [moduleName], or `null` when the design
  /// has no such module.
  ModuleArea? areaOf(String moduleName) {
    final done = _byModule[moduleName];
    if (done != null) return done;
    final module = model.modules[moduleName];
    if (module == null) return null;
    // A module that instantiates itself has no finite area; its instance
    // inside itself counts as unknown.
    if (!_inProgress.add(moduleName)) return null;
    try {
      final counts = <String, int>{};
      for (final cell in module.cells.values) {
        counts[cell.type] = (counts[cell.type] ?? 0) + 1;
      }
      var area = 0.0;
      var partial = false;
      for (final entry in counts.entries) {
        final type = entry.key;
        if (_bookkeepingTypes.contains(type)) continue;
        final child = model.modules[type];
        if (child != null && !child.isBlackBox) {
          final sub = areaOf(type);
          if (sub == null) {
            partial = true;
          } else {
            area += sub.area * entry.value;
            partial = partial || sub.partial;
          }
          continue;
        }
        final cellArea = index[type]?.cell.area;
        if (cellArea == null) {
          partial = true;
        } else {
          area += cellArea * entry.value;
        }
      }
      return _byModule[moduleName] = ModuleArea(area: area, partial: partial);
    } finally {
      _inProgress.remove(moduleName);
    }
  }
}
