// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/models/netlist/bit_ref.dart';
import 'package:netcrux/domain/models/netlist/hierarchy_node.dart';
import 'package:netcrux/domain/models/netlist/module.dart';
import 'package:netcrux/domain/models/netlist/net.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/netlist/port_direction.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/viewer/providers/canvas_fit_target_provider.dart';
import 'package:netcrux/features/viewer/providers/reveal_request_notifier.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/features/viewer/providers/trace_overlay_notifier.dart';
import 'package:netcrux/features/viewer/providers/viewport_transform_notifier.dart';
import 'package:netcrux/services/schematic/schematic_graph_builder.dart';
import 'package:netcrux/services/schematic/wire_selection_builder.dart';

/// Maps analysis-result identifiers (register instance paths, net
/// names) onto the per-tab schematic selection.
///
/// This is the row-click → canvas bridge every docked analysis panel
/// uses: clicking a CDC / reset crossing, an FSM row, an activity row,
/// or a diff row routes its element through one of these probes so the
/// element is *actually selected* on the schematic — which both draws
/// the selection highlight and arms Cross-Probe's "Send selection"
/// (the CXP resolver reads `selectedElementProvider`).
///
/// Path conventions: the Pro analyzers emit either bare leaf names
/// (`async_data`), module-qualified names (`fifo.wr_ptr` — module NAME,
/// not instance path), or dotted register paths. The probes therefore
/// resolve the LEAF against the current scope first, and only when the
/// leaf is absent there do they walk the instance hierarchy for a scope
/// whose module (a) matches the path's qualifier when one is present
/// and (b) contains the leaf — then navigate the tab's scope to it
/// before selecting. All mutations run through the per-tab notifiers,
/// and callers invoke the probes from user-event handlers (row taps),
/// never from build — preserving the no-mutation-during-build
/// invariant.
class AnalysisSelectionProbe {
  /// Creates a probe bound to [tab], a per-tab `ProviderContainer`.
  const AnalysisSelectionProbe(this.tab);

  /// The per-tab container whose hierarchy / selection state the probe
  /// reads and writes.
  final ProviderContainer tab;

  /// Selects the cell instance named by [path] (dotted; the leaf is the
  /// instance name). Navigates the scope when the cell lives in another
  /// module. Returns false when the cell cannot be located — the caller
  /// leaves the existing selection untouched.
  bool selectCell(String path) {
    final located = _locate(
      path,
      (module, leaf) => module.cells.containsKey(leaf),
    );
    if (located == null) return false;
    final (node, leaf) = located;
    _navigateTo(node);
    tab
        .read(selectedElementProvider.notifier)
        .select(SelectedElement.cell(cellId: leaf));
    return true;
  }

  /// Selects the wire(s) carrying the net named by [path] (dotted; the
  /// leaf is the net name). Returns false when no scope declares the net
  /// or the net has no rendered edge.
  ///
  /// A multi-bit bus is a vector of distinct Yosys net ids, and the
  /// schematic graph draws one edge per net id that has both a driver and
  /// a sink in the scope. Selecting a bus lights EVERY drawn strand: this
  /// installs a multi-element wire [Selection] — one
  /// [SelectedElement.wire] per bit that has a laid-out edge — so all
  /// parallel bus edges get the selection accent, not just one faint
  /// strand. The primary stays the first drawn bit, which the CXP name
  /// resolver reverse-resolves to the net's hierarchical name (e.g.
  /// `cdc_capture.sample_a`) — preserving the cross-probe identity fix.
  /// A single-bit net (e.g. `req_b0`) still highlights exactly one edge.
  /// See [buildWholeNetWireSelection].
  bool selectNet(String path) {
    final located = _locate(
      path,
      (module, leaf) => module.nets.containsKey(leaf),
    );
    if (located == null) return false;
    final (node, leaf) = located;
    final tree = tab.read(hierarchyTreeProvider);
    final model = tree.model;
    if (model == null) return false;
    final module = node.resolve(model);
    final net = module?.nets[leaf];
    if (module == null || net == null) return false;
    final graph = const SchematicGraphBuilder().build(model, node);
    final selection = buildWholeNetWireSelection(net, graph);
    if (selection == null) return false;
    _navigateTo(node);
    tab.read(selectedElementProvider.notifier).replace(selection);
    return true;
  }

  /// Selects the cell named exactly [cellName] in a scope of module
  /// [moduleName], navigating there when needed, and asks the canvas to
  /// reveal it. Unlike [selectCell], the name is never split: a
  /// Yosys-generated cell name (`$add$/src/counter.v:14$3`) contains dots.
  /// Returns false when no scope of that module declares the cell.
  bool revealCellIn(String moduleName, String cellName) {
    final node = _scopeOfModule(
      moduleName,
      (module) => module.cells.containsKey(cellName),
    );
    if (node == null) return false;
    _navigateTo(node);
    tab
        .read(selectedElementProvider.notifier)
        .select(SelectedElement.cell(cellId: cellName));
    tab.read(revealRequestProvider.notifier).request(cellName);
    return true;
  }

  /// Selects every drawn strand of the net named exactly [netName] in a
  /// scope of module [moduleName], navigating there when needed, and
  /// reveals the cell driving it (the reveal is cell-addressed). Returns
  /// false when no scope declares the net or the net has no drawn edge.
  bool revealNetIn(String moduleName, String netName) {
    final model = tab.read(hierarchyTreeProvider).model;
    if (model == null) return false;
    final node = _scopeOfModule(
      moduleName,
      (module) => module.nets.containsKey(netName),
    );
    if (node == null) return false;
    final module = node.resolve(model)!;
    final net = module.nets[netName]!;
    final graph = const SchematicGraphBuilder().build(model, node);
    final selection = buildWholeNetWireSelection(net, graph);
    if (selection == null) return false;
    _navigateTo(node);
    tab.read(selectedElementProvider.notifier).replace(selection);
    final driver = _driverOf(module, net);
    if (driver != null) {
      tab.read(revealRequestProvider.notifier).request(driver);
    }
    return true;
  }

  /// Selects the boundary port named [portName] of a scope of module
  /// [moduleName], navigating there when needed. Returns false when no
  /// scope of that module has the port.
  bool selectPortIn(String moduleName, String portName) {
    final node = _scopeOfModule(
      moduleName,
      (module) => module.ports.containsKey(portName),
    );
    if (node == null) return false;
    _navigateTo(node);
    tab
        .read(selectedElementProvider.notifier)
        .select(
          SelectedElement.boundaryPort(
            portId: 'port:$portName',
            portName: portName,
          ),
        );
    return true;
  }

  /// Makes a scope of module [moduleName] the shown scope, clears the
  /// element selection and any trace, and frames the whole module. Returns
  /// false when no instance of the module is in the hierarchy.
  ///
  /// When the module is already the shown scope there is nothing to
  /// navigate to, so the view is fitted to it the way Zoom to Fit does;
  /// without that, choosing the module left the previous element selected
  /// and nothing visibly happened. A scope change fits on its own.
  bool enterModule(String moduleName) {
    final node = _scopeOfModule(moduleName, (_) => true);
    if (node == null) return false;
    final alreadyShown = identical(
      tab.read(hierarchyTreeProvider).selected,
      node,
    );
    _navigateTo(node);
    tab.read(selectedElementProvider.notifier).clear();
    tab.read(traceOverlayProvider.notifier).clear();
    if (alreadyShown) {
      final target = tab.read(canvasFitTargetProvider);
      if (target != null) {
        tab
            .read(viewportTransformProvider.notifier)
            .fitToBounds(target.size, target.bounds);
      }
    }
    return true;
  }

  /// The scope showing module [moduleName] whose module passes [contains]:
  /// the current scope when it qualifies, else the first in a breadth-first
  /// walk of the hierarchy.
  HierarchyNode? _scopeOfModule(
    String moduleName,
    bool Function(Module module) contains,
  ) {
    final tree = tab.read(hierarchyTreeProvider);
    final model = tree.model;
    if (model == null) return null;
    final current = tree.selected;
    final currentModule = current?.resolve(model);
    if (current != null &&
        current.moduleName == moduleName &&
        currentModule != null &&
        contains(currentModule)) {
      return current;
    }
    return _search(
      model,
      (node, module) => node.moduleName == moduleName && contains(module),
    );
  }

  /// The name of the cell in [module] whose output drives a bit of [net],
  /// or null when the net is driven from outside (a port, a constant).
  static String? _driverOf(Module module, Net net) {
    final bits = <int>{
      for (final bit in net.bits)
        if (bit is NetBit) bit.netId,
    };
    for (final cell in module.cells.values) {
      for (final entry in cell.connections.entries) {
        if (cell.portDirections[entry.key] != PortDirection.output) continue;
        for (final bit in entry.value) {
          if (bit is NetBit && bits.contains(bit.netId)) return cell.name;
        }
      }
    }
    return null;
  }

  /// Resolves the hierarchy scope that contains [path]'s leaf, testing
  /// containment with [contains]. Preference order: the current scope,
  /// then a breadth-first walk of the instance hierarchy — filtered to
  /// modules matching the path's qualifier segment when one is present,
  /// with an unqualified retry as fallback. Bounded so a pathological
  /// hierarchy cannot stall a tap handler.
  (HierarchyNode, String)? _locate(
    String path,
    bool Function(Module module, String leaf) contains,
  ) {
    final segments = path.split('.');
    final leaf = segments.isEmpty ? path : segments.last;
    if (leaf.isEmpty) return null;
    final qualifier = segments.length > 1
        ? segments[segments.length - 2]
        : null;
    final tree = tab.read(hierarchyTreeProvider);
    final model = tree.model;
    if (model == null) return null;

    // 1. Current scope wins — no navigation needed.
    final current = tree.selected;
    final currentModule = current?.resolve(model);
    if (current != null &&
        currentModule != null &&
        contains(currentModule, leaf)) {
      return (current, leaf);
    }

    // 2. Qualified walk, then unqualified fallback.
    if (qualifier != null) {
      final qualified = _search(model, (node, module) {
        return node.moduleName == qualifier && contains(module, leaf);
      });
      if (qualified != null) return (qualified, leaf);
    }
    final anywhere = _search(model, (node, module) => contains(module, leaf));
    if (anywhere != null) return (anywhere, leaf);
    return null;
  }

  /// Breadth-first hierarchy walk returning the first node accepted by
  /// [test]. Visits at most [_maxVisitedScopes] scopes.
  HierarchyNode? _search(
    NetlistModel model,
    bool Function(HierarchyNode node, Module module) test,
  ) {
    final root = HierarchyNode.rootOf(model);
    if (root == null) return null;
    final queue = <HierarchyNode>[root];
    var visited = 0;
    while (queue.isNotEmpty && visited < _maxVisitedScopes) {
      final node = queue.removeAt(0);
      visited++;
      final module = node.resolve(model);
      if (module == null) continue;
      if (test(node, module)) return node;
      for (final cellName in module.cells.keys) {
        final child = node.child(model, cellName);
        if (child != null) queue.add(child);
      }
    }
    return null;
  }

  /// Moves the tab's scope to [node] when it differs from the current
  /// selection. `selectScope` is a no-op for the already-selected node.
  void _navigateTo(HierarchyNode node) {
    tab.read(hierarchyTreeProvider.notifier).selectScope(node);
  }

  static const int _maxVisitedScopes = 4096;
}
