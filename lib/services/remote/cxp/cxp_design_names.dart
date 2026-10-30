// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:netcrux/domain/models/netlist/bit_ref.dart';
import 'package:netcrux/domain/models/netlist/hierarchy_node.dart';
import 'package:netcrux/domain/models/netlist/module.dart';
import 'package:netcrux/domain/models/netlist/net.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/netlist/port_direction.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/domain/models/selection/selection.dart';
import 'package:netcrux/services/remote/cxp/netcrux_name_resolver.dart';
import 'package:netcrux/services/schematic/netlist_element_lookup.dart';

/// A name a peer sent, placed in the design: the scope it lives in and its
/// name there.
@immutable
class CxpScopedName {
  /// Creates a scoped name.
  const CxpScopedName({required this.scope, required this.leaf});

  /// The scope the name lives in.
  final HierarchyNode scope;

  /// The name inside [scope], as the netlist names it: one segment, which
  /// may itself contain `.` (an escaped identifier, a `$`-name, a flattened
  /// cell name).
  final String leaf;
}

/// The maximum instance depth a received name is walked to.
const int _kMaxNameDepth = 64;

/// Places a hierarchical name [local] that is rooted at the design's top
/// module (`top.u_div.cnt_q`) in the design: walks the instance chain from
/// the top for as long as the segments name child instances, and returns
/// the scope reached and the rest of the name.
///
/// Returns null when [model] has no top, or [local]'s first segment is not
/// the top module's name: such a name (a waveform's testbench path,
/// `tb.dut.state`) is not rooted in this design, and the caller decides what
/// to do with it. A rooted name is never moved to another scope: the scope
/// returned is the one the name says.
///
/// Segments are read by [NetcruxNameResolver.splitHierarchicalPath], so an
/// escaped identifier, a `$`-name or a bracketed index is one segment. The
/// last segment is always the leaf, even when it also names an instance.
CxpScopedName? scopeOfHierarchicalName(NetlistModel model, String local) {
  final root = HierarchyNode.rootOf(model);
  if (root == null) return null;
  final segments = NetcruxNameResolver.splitHierarchicalPath(local);
  if (segments.length < 2 || segments.first != root.moduleName) return null;
  var node = root;
  var i = 1;
  while (i < segments.length - 1 && node.depth < _kMaxNameDepth) {
    final child = node.child(model, segments[i]);
    if (child == null) break;
    node = child;
    i++;
  }
  return CxpScopedName(scope: node, leaf: segments.sublist(i).join('.'));
}

/// The hierarchy node at [path] (instance names below the top), or null
/// when the path leaves the design.
HierarchyNode? hierarchyNodeAt(NetlistModel model, List<String> path) {
  var node = HierarchyNode.rootOf(model);
  for (final name in path) {
    node = node?.child(model, name);
    if (node == null) return null;
  }
  return node;
}

/// A trailing numeric bit-select or slice: `[7:0]`, `[3]`.
final RegExp _busSuffix = RegExp(r'\[\d+(?::\d+)?\]$');

/// The net of [module] named [leaf], or, when [leaf] ends in a numeric bit
/// select or slice (`cnt_q[3]`), the whole net it selects from.
Net? findNetNamed(Module module, String leaf) {
  final exact = module.nets[leaf];
  if (exact != null) return exact;
  final stripped = leaf.replaceFirst(_busSuffix, '');
  if (stripped == leaf || stripped.isEmpty) return null;
  return module.nets[stripped];
}

/// What highlights [net] on the schematic of [module]: every drawn strand of
/// the net, or, when the net has no drawn edge (a register whose output goes
/// nowhere in this scope), the cell that drives it. Null when neither is on
/// the schematic.
///
/// Read from the netlist module alone, so a highlight does not build the
/// scope's schematic graph (see `netlist_element_lookup.dart`).
Selection? selectionForNet(Module module, Net net) {
  final wires = wholeNetWireSelection(module, net);
  if (wires != null) return wires;
  final driver = driverCellOf(module, net);
  if (driver == null || !schematicDrawsCell(module, driver)) return null;
  return Selection.single(SelectedElement.cell(cellId: driver));
}

/// The name of the cell of [module] whose output drives a bit of [net], or
/// null when no cell does (a primary input, an undriven net).
String? driverCellOf(Module module, Net net) {
  final bits = <int>{
    for (final bit in net.bits)
      if (bit is NetBit) bit.netId,
  };
  if (bits.isEmpty) return null;
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

/// The RTL name of the net a register cell's `Q` drives, in [module]: the
/// source-level name a user would recognise, preferring one that is not a
/// Yosys `$`-name. Null when the cell has no `Q` or no named net carries it.
String? registerOutputNetName(Module module, String cellName) {
  final cell = module.cells[cellName];
  if (cell == null) return null;
  final q = cell.connections['Q'];
  if (q == null || q.isEmpty) return null;
  final ids = <int>{
    for (final bit in q)
      if (bit is NetBit) bit.netId,
  };
  if (ids.isEmpty) return null;
  String? internal;
  for (final net in module.nets.values) {
    final carries = net.bits.any((b) => b is NetBit && ids.contains(b.netId));
    if (!carries) continue;
    if (!net.name.startsWith(r'$') && !net.hideName) return net.name;
    internal ??= net.name;
  }
  return internal;
}

/// The nodes of [model]'s instance tree in pre-order, the top first.
/// Bounded in depth and count, so a malformed or enormous hierarchy cannot
/// stall the caller.
Iterable<HierarchyNode> hierarchyPreOrder(
  NetlistModel model, {
  int maxNodes = 20000,
}) sync* {
  final root = HierarchyNode.rootOf(model);
  if (root == null) return;
  final stack = <HierarchyNode>[root];
  var seen = 0;
  while (stack.isNotEmpty && seen < maxNodes) {
    final node = stack.removeLast();
    seen++;
    yield node;
    if (node.depth >= _kMaxNameDepth) continue;
    final children = node.childInstanceNames(model);
    for (final name in children.reversed) {
      final child = node.child(model, name);
      if (child != null) stack.add(child);
    }
  }
}
