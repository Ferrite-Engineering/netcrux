// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:netcrux/domain/interfaces/cone_of_influence_service.dart';
import 'package:netcrux/domain/models/schematic/schematic_graph.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/domain/models/trace/cone_view.dart';
import 'package:netcrux/domain/models/trace/trace_overlay.dart';

/// The cells, boundary ports and wires within [depth] levels of [root] in
/// [graph], walked [mode], as a [TraceOverlay].
///
/// The walk is the one the fan-in and fan-out trace takes, repeated: it
/// starts from the pins [root] names (every pin of a cell, the one pin of a
/// pin, both ends of a wire, the boundary port itself), follows each wire
/// into a frontier pin (fan-in) or out of one (fan-out) to the pin at its
/// far end, and steps through that pin's cell, whose other pins not yet
/// reached form the next frontier. A boundary port, or a pin of a cell the
/// scope does not hold, ends the walk on that branch. One level reproduces
/// the one-step trace; the Pro Cone of Influence walk at the same depth
/// reaches the same set.
///
/// The overlay always holds [root]'s own anchor (its cell, its boundary
/// port, or its wire and the wire's two ends), so a cone of an element
/// with no connectivity is that element alone. [depth] below one walks
/// nothing.
TraceOverlay coneMembership(
  SchematicGraph graph,
  SelectedElement root, {
  required ConeOfInfluenceMode mode,
  required int depth,
}) {
  final fanIn = mode == ConeOfInfluenceMode.fanin;
  final cells = <String>{};
  final boundaries = <String>{};
  final edges = <String>{};
  addConeAnchors(graph, root, cells, boundaries, edges);

  // The first cell of an id owns it, as everywhere else an id is looked up.
  final pinsByCell = <String, List<String>>{};
  for (final cell in graph.cells) {
    pinsByCell.putIfAbsent(
      cell.id,
      () => <String>[for (final port in cell.ports) port.id],
    );
  }

  final seeds = _seedPins(graph, root);
  final visited = <String>{...seeds};
  var frontier = seeds.toSet();
  for (var level = 0; level < depth && frontier.isNotEmpty; level++) {
    final next = <String>{};
    // Each level takes the scope's wires in their own order, not the
    // frontier's: when two pins of one cell are reached in the same level,
    // which of them steps the walk on depends on it, and graph order is the
    // order the Pro Cone of Influence walk takes, so the two agree.
    for (final edge in graph.edges) {
      final near = fanIn ? edge.targetPortId : edge.sourcePortId;
      if (!frontier.contains(near)) continue;
      edges.add(edge.id);
      final far = fanIn ? edge.sourcePortId : edge.targetPortId;
      if (far.startsWith('port:')) {
        boundaries.add(far);
        continue;
      }
      final cellId = cellIdOfPinId(far);
      if (cellId == null) continue;
      cells.add(cellId);
      if (!visited.add(far)) continue;
      for (final other in pinsByCell[cellId] ?? const <String>[]) {
        if (visited.add(other)) next.add(other);
      }
    }
    frontier = next;
  }

  return TraceOverlay(
    mode: fanIn ? TraceOverlayMode.fanin : TraceOverlayMode.fanout,
    highlightedCellIds: Set<String>.unmodifiable(cells),
    highlightedEdgeIds: Set<String>.unmodifiable(edges),
    highlightedBoundaryPortIds: Set<String>.unmodifiable(boundaries),
  );
}

/// The members of both [a] and [b] together, in [a]'s mode.
TraceOverlay unionConeMembership(TraceOverlay a, TraceOverlay b) =>
    TraceOverlay(
      mode: a.mode ?? b.mode,
      highlightedCellIds: Set<String>.unmodifiable(<String>{
        ...a.highlightedCellIds,
        ...b.highlightedCellIds,
      }),
      highlightedEdgeIds: Set<String>.unmodifiable(<String>{
        ...a.highlightedEdgeIds,
        ...b.highlightedEdgeIds,
      }),
      highlightedBoundaryPortIds: Set<String>.unmodifiable(<String>{
        ...a.highlightedBoundaryPortIds,
        ...b.highlightedBoundaryPortIds,
      }),
    );

/// The cone of [root] in [graph] for a cone view walked [direction] for
/// [depth] levels: [coneMembership] once for fan-in, or the union of the
/// fan-in and fan-out walks.
TraceOverlay coneViewMembership(
  SchematicGraph graph,
  SelectedElement root, {
  required ConeViewDirection direction,
  required int depth,
}) {
  final fanIn = coneMembership(
    graph,
    root,
    mode: ConeOfInfluenceMode.fanin,
    depth: depth,
  );
  if (direction == ConeViewDirection.fanIn) return fanIn;
  return unionConeMembership(
    fanIn,
    coneMembership(
      graph,
      root,
      mode: ConeOfInfluenceMode.fanout,
      depth: depth,
    ),
  );
}

/// Adds [root]'s own anchor in [graph] to the three sets: its cell (a cell
/// or a pin), its boundary port, or its wire with the cells or boundary
/// ports at both ends. Every occurrence of a wire id counts.
void addConeAnchors(
  SchematicGraph graph,
  SelectedElement root,
  Set<String> cells,
  Set<String> boundaries,
  Set<String> edges,
) {
  void addHost(String pinId) {
    if (pinId.startsWith('port:')) {
      boundaries.add(pinId);
      return;
    }
    final cellId = cellIdOfPinId(pinId);
    if (cellId != null) cells.add(cellId);
  }

  switch (root) {
    case SelectedElementNone():
      break;
    case SelectedElementCell(:final cellId):
      cells.add(cellId);
    case SelectedElementPort(:final cellId):
      cells.add(cellId);
    case SelectedElementBoundaryPort(:final portId):
      boundaries.add(portId);
    case SelectedElementWire(:final edgeId):
      edges.add(edgeId);
      for (final edge in graph.edges) {
        if (edge.id != edgeId) continue;
        addHost(edge.sourcePortId);
        addHost(edge.targetPortId);
      }
  }
}

/// The sub-graph of [graph] a cone view draws for the cone [members]: its
/// cells and boundary ports, and every wire of [graph] whose two ends both
/// sit on a member, whether or not the walk crossed it. Cells, ports and
/// wires keep the ids, order and pin ties [graph] gives them.
SchematicGraph coneSubgraph(SchematicGraph graph, TraceOverlay members) {
  final cellIds = members.highlightedCellIds;
  final boundaryIds = members.highlightedBoundaryPortIds;
  bool onMember(String pinId) {
    if (pinId.startsWith('port:')) return boundaryIds.contains(pinId);
    final cellId = cellIdOfPinId(pinId);
    return cellId != null && cellIds.contains(cellId);
  }

  return SchematicGraph(
    moduleName: graph.moduleName,
    cells: List<SchematicCell>.unmodifiable(
      graph.cells.where((c) => cellIds.contains(c.id)),
    ),
    boundaryPorts: List<SchematicBoundaryPort>.unmodifiable(
      graph.boundaryPorts.where((b) => boundaryIds.contains(b.id)),
    ),
    edges: List<SchematicEdge>.unmodifiable(
      graph.edges.where(
        (e) => onMember(e.sourcePortId) && onMember(e.targetPortId),
      ),
    ),
  );
}

/// The pins the walk from [root] starts at: every pin of a cell, the pin
/// itself, both ends of every occurrence of a wire, or the boundary port.
List<String> _seedPins(SchematicGraph graph, SelectedElement root) {
  switch (root) {
    case SelectedElementNone():
      return const <String>[];
    case SelectedElementCell(:final cellId):
      // Every occurrence of the id seeds, as the trace does.
      return <String>{
        for (final cell in graph.cells)
          if (cell.id == cellId)
            for (final port in cell.ports) port.id,
      }.toList();
    case SelectedElementPort(:final portId):
      return <String>[portId];
    case SelectedElementBoundaryPort(:final portId):
      return <String>[portId];
    case SelectedElementWire(:final edgeId):
      return <String>{
        for (final edge in graph.edges)
          if (edge.id == edgeId) ...<String>[
            edge.sourcePortId,
            edge.targetPortId,
          ],
      }.toList();
  }
}
