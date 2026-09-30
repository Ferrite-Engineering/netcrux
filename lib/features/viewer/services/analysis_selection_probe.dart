// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/models/netlist/hierarchy_node.dart';
import 'package:netcrux/domain/models/netlist/module.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
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
