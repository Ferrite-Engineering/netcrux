// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:netcrux/domain/models/netlist/bit_ref.dart';
import 'package:netcrux/domain/models/netlist/hierarchy_node.dart';
import 'package:netcrux/domain/models/netlist/module.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/netlist/port_direction.dart';
import 'package:netcrux/domain/models/schematic/cell_kind.dart';
import 'package:netcrux/domain/models/schematic/schematic_graph.dart';

/// Derives a renderable [SchematicGraph] for the scope addressed by a
/// [HierarchyNode] in a [NetlistModel].
///
/// Pure function — no caching, no I/O, no isolate boundary. The
/// service is a no-state class only so it can be swapped out via
/// Riverpod for diagnostic instrumentation or alternative cell-kind
/// taxonomies later.
///
/// The builder *only* walks one scope. It does not descend into child
/// instances — the schematic canvas paints whatever is at the current
/// scope, and push-in / pop-out re-runs the builder against the new
/// scope. No recursive descent keeps the per-scope graph small enough
/// that elkjs can lay
/// it out interactively.
class SchematicGraphBuilder {
  /// Creates a builder. Stateless — instances are interchangeable.
  const SchematicGraphBuilder();

  /// Builds a [SchematicGraph] for the [node] inside [model]. Returns
  /// [SchematicGraph.empty] when the node fails to resolve (e.g. the
  /// model was replaced).
  SchematicGraph build(NetlistModel model, HierarchyNode node) {
    final module = node.resolve(model);
    if (module == null) return SchematicGraph.empty;

    final cells = <SchematicCell>[];
    for (final entry in module.cells.entries) {
      final cell = entry.value;
      final kind = cellKindFromYosysType(cell.type);
      final ports = <SchematicPort>[];
      // Yosys keeps `connections` in declaration order via
      // LinkedHashMap; that order is the source of truth for the
      // renderer's pin layout. We split sides by direction so the
      // symbol painter doesn't have to guess.
      for (final portEntry in cell.connections.entries) {
        // Yosys may omit `port_directions` for known primitives —
        // fall back to "input" so we don't lose the pin entirely.
        final direction =
            cell.portDirections[portEntry.key] ?? PortDirection.input;
        ports.add(
          SchematicPort(
            id: '${cell.name}:${portEntry.key}',
            name: portEntry.key,
            direction: direction,
            side: _sideForDirection(direction),
          ),
        );
      }
      cells.add(
        SchematicCell(
          id: cell.name,
          kind: kind,
          type: cell.type,
          ports: ports,
        ),
      );
    }

    final boundaryPorts = <SchematicBoundaryPort>[
      for (final entry in module.ports.entries)
        SchematicBoundaryPort(
          id: 'port:${entry.value.name}',
          name: entry.value.name,
          direction: entry.value.direction,
          width: entry.value.bits.length,
        ),
    ];

    final edges = _buildEdges(module);

    return SchematicGraph(
      moduleName: module.name,
      cells: cells,
      boundaryPorts: boundaryPorts,
      edges: edges,
    );
  }

  SchematicPortSide _sideForDirection(PortDirection direction) {
    switch (direction) {
      case PortDirection.input:
        return SchematicPortSide.west;
      case PortDirection.output:
        return SchematicPortSide.east;
      case PortDirection.inout:
        return SchematicPortSide.south;
    }
  }

  /// Builds the list of [SchematicEdge]s by intersecting drivers and
  /// sinks per Yosys net id. Mirrors the algorithm in
  /// `buildElkInput` so the schematic graph and the ELK input agree
  /// on connectivity — divergence here would mean a wire renders
  /// without ELK routing it (or vice-versa).
  List<SchematicEdge> _buildEdges(Module module) {
    final attachmentsByNetId = <int, List<_Attachment>>{};

    // Collect cell-side attachments.
    for (final cellEntry in module.cells.entries) {
      final cell = cellEntry.value;
      for (final entry in cell.connections.entries) {
        final direction = cell.portDirections[entry.key] ?? PortDirection.input;
        final isDriver = direction == PortDirection.output;
        final portId = '${cell.name}:${entry.key}';
        for (final bit in entry.value) {
          if (bit is! NetBit) continue;
          attachmentsByNetId
              .putIfAbsent(bit.netId, _attachmentsList)
              .add(_Attachment(portId: portId, isDriver: isDriver));
        }
      }
    }

    // Collect boundary-port attachments. Module-input ports drive the
    // net (they source bits into the design); module-output ports
    // sink the net.
    for (final portEntry in module.ports.entries) {
      final port = portEntry.value;
      final isDriver = port.direction == PortDirection.input;
      final portId = 'port:${port.name}';
      for (final bit in port.bits) {
        if (bit is! NetBit) continue;
        attachmentsByNetId
            .putIfAbsent(bit.netId, _attachmentsList)
            .add(_Attachment(portId: portId, isDriver: isDriver));
      }
    }

    // Pair every driver with every sink on the same net. Use sets to
    // collapse identical attachments — Yosys can list the same port
    // bit twice when a bus is fanned out manually.
    final edges = <SchematicEdge>[];
    var counter = 0;
    for (final entry in attachmentsByNetId.entries) {
      final attachments = entry.value;
      final drivers = attachments.where((a) => a.isDriver).toSet();
      final sinks = attachments.where((a) => !a.isDriver).toSet();
      for (final driver in drivers) {
        for (final sink in sinks) {
          if (driver.portId == sink.portId) continue;
          edges.add(
            SchematicEdge(
              id: 'e_${entry.key}_${counter++}',
              sourcePortId: driver.portId,
              targetPortId: sink.portId,
              netId: entry.key,
            ),
          );
        }
      }
    }
    return edges;
  }

  // Tear-off helper for putIfAbsent.
  static List<_Attachment> _attachmentsList() => <_Attachment>[];
}

@immutable
class _Attachment {
  const _Attachment({required this.portId, required this.isDriver});
  final String portId;
  final bool isDriver;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is _Attachment &&
          other.portId == portId &&
          other.isDriver == isDriver);

  @override
  int get hashCode => Object.hash(portId, isDriver);
}
