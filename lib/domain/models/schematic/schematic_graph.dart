// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:netcrux/domain/models/netlist/port_direction.dart';
import 'package:netcrux/domain/models/schematic/cell_kind.dart';
import 'package:netcrux/domain/models/schematic/pin_tie.dart';

/// Direction of a [SchematicPort] on its parent [SchematicCell].
enum SchematicPortSide {
  /// Input — drawn on the left side of the symbol body.
  west,

  /// Output — drawn on the right side of the symbol body.
  east,

  /// Bidirectional / control — drawn on the bottom side.
  south,

  /// Reserved for the rare case where a top-side pin is needed (e.g.
  /// reset on a flip-flop). Not currently emitted by the builder but
  /// honored by the renderer, so the builder can emit it without a
  /// renderer change.
  north,
}

/// One drawn pin on a [SchematicCell]. The id pairs the cell name with
/// the port name (`<cellName>:<portName>`) so it matches the ELK input
/// the layout engine consumes, and so edges can address pins
/// unambiguously even when two cells share a port name.
@immutable
class SchematicPort {
  /// Creates a schematic port.
  const SchematicPort({
    required this.id,
    required this.name,
    required this.direction,
    required this.side,
    this.tie = PinTie.net,
  });

  /// `<cellName>:<portName>` — stable across builder runs.
  final String id;

  /// Port name on the cell (e.g. `A`, `Y`, `CLK`).
  final String name;

  /// Logical direction (input / output / inout). Drives default
  /// [side] but also surfaces to the renderer for accent colors.
  final PortDirection direction;

  /// Which face of the cell symbol the port lives on.
  final SchematicPortSide side;

  /// What the pin is tied to: nets, a constant, an undriven net, or
  /// nothing. Drives the stub the canvas draws beside the pin and the
  /// inspector's "Tied to" row.
  final PinTie tie;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SchematicPort &&
          other.id == id &&
          other.name == name &&
          other.direction == direction &&
          other.side == side &&
          other.tie == tie);

  @override
  int get hashCode => Object.hash(id, name, direction, side, tie);

  @override
  String toString() => 'SchematicPort($id, $direction, $side, $tie)';
}

/// A drawn cell on the schematic canvas. May be a primitive ([CellKind]
/// classifies which symbol painter draws it) or a user-defined module
/// instance ([CellKind.generic]).
@immutable
class SchematicCell {
  /// Creates a schematic cell.
  const SchematicCell({
    required this.id,
    required this.kind,
    required this.type,
    required this.ports,
    this.label,
  });

  /// Cell instance name. Stable id used by [SchematicEdge] endpoints.
  final String id;

  /// Coarse classification driving the symbol the renderer paints.
  final CellKind kind;

  /// Yosys cell type, kept for diagnostic display ("u_dff ($dff)").
  final String type;

  /// Display label override (otherwise [id] is used).
  final String? label;

  /// Ports on this cell, in declaration order. The order is preserved
  /// because ELK uses port index as a tie-breaker for layout-side
  /// ordering when multiple pins share the same face.
  final List<SchematicPort> ports;

  /// Convenience: the text the renderer should show for the cell.
  String get displayLabel => label ?? id;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! SchematicCell) return false;
    if (other.id != id) return false;
    if (other.kind != kind) return false;
    if (other.type != type) return false;
    if (other.label != label) return false;
    if (other.ports.length != ports.length) return false;
    for (var i = 0; i < ports.length; i++) {
      if (other.ports[i] != ports[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(id, kind, type, label, Object.hashAll(ports));

  @override
  String toString() =>
      'SchematicCell($id type=$type kind=$kind ports=${ports.length})';
}

/// A module boundary port rendered as a stub on the perimeter of the
/// schematic canvas. Distinct from [SchematicPort], which lives on a
/// cell symbol — boundary ports are drawn as small triangle stubs that
/// edges terminate at.
@immutable
class SchematicBoundaryPort {
  /// Creates a boundary port.
  const SchematicBoundaryPort({
    required this.id,
    required this.name,
    required this.direction,
    required this.width,
  });

  /// `port:<portName>` — matches the ELK-side id [SchematicGraphBuilder]
  /// emits.
  final String id;

  /// Port name as declared in the source HDL.
  final String name;

  /// Direction (input / output / inout).
  final PortDirection direction;

  /// Width in bits — surfaces in the label for multi-bit ports.
  final int width;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SchematicBoundaryPort &&
          other.id == id &&
          other.name == name &&
          other.direction == direction &&
          other.width == width);

  @override
  int get hashCode => Object.hash(id, name, direction, width);

  @override
  String toString() => 'SchematicBoundaryPort($id, $direction, w=$width)';
}

/// A wire on the schematic — one driver port to one sink port, derived
/// from one Yosys net.
@immutable
class SchematicEdge {
  /// Creates a schematic edge.
  const SchematicEdge({
    required this.id,
    required this.sourcePortId,
    required this.targetPortId,
    required this.netId,
  });

  /// Stable per-graph edge id.
  final String id;

  /// `<cellName>:<portName>` (or `port:<name>`) of the driver pin.
  final String sourcePortId;

  /// `<cellName>:<portName>` (or `port:<name>`) of the sink pin.
  final String targetPortId;

  /// Underlying Yosys net id this edge carries. Multiple edges may
  /// share a [netId] when a net fans out to several sinks.
  final int netId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SchematicEdge &&
          other.id == id &&
          other.sourcePortId == sourcePortId &&
          other.targetPortId == targetPortId &&
          other.netId == netId);

  @override
  int get hashCode => Object.hash(id, sourcePortId, targetPortId, netId);

  @override
  String toString() =>
      'SchematicEdge($id, $sourcePortId → $targetPortId, net=$netId)';
}

/// One scope's worth of schematic-ready data: the cells, boundary
/// ports, and wires the renderer paints and the layout engine
/// arranges.
///
/// Produced by [SchematicGraphBuilder.build] from a [NetlistModel] +
/// [HierarchyNode]. Pure data — no callbacks, no Flutter imports.
@immutable
class SchematicGraph {
  /// Creates a schematic graph.
  const SchematicGraph({
    required this.moduleName,
    required this.cells,
    required this.boundaryPorts,
    required this.edges,
  });

  /// Empty schematic for an empty / missing scope.
  static const SchematicGraph empty = SchematicGraph(
    moduleName: '',
    cells: <SchematicCell>[],
    boundaryPorts: <SchematicBoundaryPort>[],
    edges: <SchematicEdge>[],
  );

  /// Module name behind this scope.
  final String moduleName;

  /// Cells in declaration order.
  final List<SchematicCell> cells;

  /// Module boundary ports.
  final List<SchematicBoundaryPort> boundaryPorts;

  /// Wires connecting cells to each other and to the boundary.
  final List<SchematicEdge> edges;

  /// True when there is nothing to render.
  bool get isEmpty => cells.isEmpty && boundaryPorts.isEmpty && edges.isEmpty;

  /// Looks up an edge by [SchematicEdge.id] in O(1). Returns `null` when
  /// there is no edge with that id.
  ///
  /// Backed by [_edgesById]. The hit-tester needs an edge's `netId` for
  /// every wire it tests against a click; building a throwaway id→edge
  /// map on each hit-test made a click O(edges) in map construction even
  /// when the first segment matched.
  SchematicEdge? findEdge(String id) => _edgesById[id];

  /// Lazily-built id→edge index, memoized per instance via
  /// [_edgeIndexCache].
  ///
  /// [SchematicGraph] is immutable, so the index is built at most once
  /// per instance and reused for every [findEdge]. The cache is an
  /// identity [Expando] rather than a field so the `const` constructor
  /// (and [empty]) are preserved and the entry is garbage-collected with
  /// the graph — the same idiom [NetlistLayout] uses for its node/edge
  /// indices.
  ///
  /// On the (malformed) duplicate-id case the first occurrence wins,
  /// matching the previous first-match map-build semantics.
  Map<String, SchematicEdge> get _edgesById =>
      _edgeIndexCache[this] ??= _buildEdgeIndex(edges);

  static Map<String, SchematicEdge> _buildEdgeIndex(List<SchematicEdge> edges) {
    final index = <String, SchematicEdge>{};
    for (final edge in edges) {
      index.putIfAbsent(edge.id, () => edge);
    }
    return index;
  }

  /// Per-instance identity cache for [_edgesById]. Keyed by object
  /// identity, so equal-but-distinct graphs get their own index and
  /// entries are freed when the graph is collected.
  static final Expando<Map<String, SchematicEdge>> _edgeIndexCache =
      Expando<Map<String, SchematicEdge>>('SchematicGraph.edgeIndex');

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! SchematicGraph) return false;
    if (other.moduleName != moduleName) return false;
    if (other.cells.length != cells.length) return false;
    for (var i = 0; i < cells.length; i++) {
      if (other.cells[i] != cells[i]) return false;
    }
    if (other.boundaryPorts.length != boundaryPorts.length) return false;
    for (var i = 0; i < boundaryPorts.length; i++) {
      if (other.boundaryPorts[i] != boundaryPorts[i]) return false;
    }
    if (other.edges.length != edges.length) return false;
    for (var i = 0; i < edges.length; i++) {
      if (other.edges[i] != edges[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    moduleName,
    Object.hashAll(cells),
    Object.hashAll(boundaryPorts),
    Object.hashAll(edges),
  );

  @override
  String toString() =>
      'SchematicGraph(module: $moduleName, cells: ${cells.length}, '
      'boundary: ${boundaryPorts.length}, edges: ${edges.length})';
}
