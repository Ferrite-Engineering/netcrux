import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/models/bookmark.dart';
import 'package:netcrux/domain/models/netlist/bit_ref.dart';
import 'package:netcrux/domain/models/netlist/module.dart';
import 'package:netcrux/domain/models/schematic/schematic_graph.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/features/viewer/services/analysis_selection_probe.dart';

/// Selects the element a bookmark or annotation names on the schematic of
/// [tab], the per-tab container, navigating to its scope and revealing it.
/// Returns false, changing nothing, when the shown design has no such
/// element.
///
/// [targetId] is the canvas's own id for the element: a bare cell instance
/// name (`$procdff$17`, `u_alu`), a `<cell>:<port>` pin id, a
/// `port:<name>` boundary-port id, a wire's `e_<netId>_<k>` edge id, or a
/// dotted instance path for a scope. Those ids are local to a module, so
/// the element is looked up by exact name in [moduleName]'s scopes through
/// the exact-name [AnalysisSelectionProbe] methods. Splitting the id on
/// dots, as `selectCell` does, would turn a Yosys cell name carrying a
/// source location (`$and$alu.v:42$7`) into a path and find nothing.
///
/// Without a [moduleName] (an entry saved before it was recorded), the
/// module of the scope on screen is tried first, then every other module
/// of the design in name order.
bool revealBookmarkTarget(
  ProviderContainer tab, {
  required BookmarkTargetKind kind,
  required String targetId,
  String? moduleName,
}) {
  final tree = tab.read(hierarchyTreeProvider);
  final model = tree.model;
  if (model == null) return false;
  if (kind == BookmarkTargetKind.scope) return _revealScope(tab, targetId);

  final current = tree.selected?.moduleName;
  final modules = moduleName != null
      ? <String>[moduleName]
      : <String>[
          ?current,
          ...(model.modules.keys.where((m) => m != current).toList()..sort()),
        ];
  final probe = AnalysisSelectionProbe(tab);
  for (final module in modules) {
    if (_revealIn(tab, probe, model.modules[module], module, kind, targetId)) {
      return true;
    }
  }
  return false;
}

bool _revealIn(
  ProviderContainer tab,
  AnalysisSelectionProbe probe,
  Module? module,
  String moduleName,
  BookmarkTargetKind kind,
  String targetId,
) {
  if (module == null) return false;
  switch (kind) {
    case BookmarkTargetKind.cell:
      return probe.revealCellIn(moduleName, targetId);
    case BookmarkTargetKind.port:
      final cellId = cellIdOfPinId(targetId);
      if (cellId == null) return false;
      final portName = targetId.substring(cellId.length + 1);
      final cell = module.cells[cellId];
      if (cell == null || !cell.connections.containsKey(portName)) {
        return false;
      }
      if (!probe.revealCellIn(moduleName, cellId)) return false;
      tab
          .read(selectedElementProvider.notifier)
          .select(
            SelectedElement.port(
              cellId: cellId,
              portId: targetId,
              portName: portName,
            ),
          );
      return true;
    case BookmarkTargetKind.boundaryPort:
      final name = targetId.startsWith('port:')
          ? targetId.substring('port:'.length)
          : targetId;
      return probe.selectPortIn(moduleName, name);
    case BookmarkTargetKind.net:
      final netId = netIdOfEdgeId(targetId);
      if (netId == null) return false;
      final netName = _netNameOf(module, netId);
      return netName != null && probe.revealNetIn(moduleName, netName);
    case BookmarkTargetKind.scope:
      return false;
  }
}

/// The name of the first net of [module] that carries bit [netId].
String? _netNameOf(Module module, int netId) {
  for (final entry in module.nets.entries) {
    for (final bit in entry.value.bits) {
      if (bit is NetBit && bit.netId == netId) return entry.key;
    }
  }
  return null;
}

/// Opens the scope a dotted instance path names. The path may or may not
/// start with the top module's name, so both readings are tried.
bool _revealScope(ProviderContainer tab, String path) {
  final segments = path.split('.').where((s) => s.isNotEmpty).toList();
  final notifier = tab.read(hierarchyTreeProvider.notifier);
  for (final candidate in <List<String>>[
    segments,
    if (segments.isNotEmpty) segments.sublist(1),
  ]) {
    notifier.selectByPath(candidate);
    final landed = tab.read(hierarchyTreeProvider).selected?.path;
    if (landed != null && _samePath(landed, candidate)) {
      tab.read(selectedElementProvider.notifier).clear();
      return true;
    }
  }
  return false;
}

bool _samePath(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
