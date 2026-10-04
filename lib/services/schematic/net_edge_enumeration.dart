// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:netcrux/domain/models/netlist/bit_ref.dart';
import 'package:netcrux/domain/models/netlist/module.dart';
import 'package:netcrux/domain/models/netlist/port_direction.dart';
import 'package:netcrux/domain/models/schematic/schematic_graph.dart';

/// The point-to-point edges of one Yosys net in a scope.
@immutable
class NetEdges {
  /// Creates the edge group of net [netId].
  const NetEdges({required this.netId, required this.edges});

  /// The Yosys net id.
  final int netId;

  /// Every de-duplicated driver × sink pair of the net, in a stable order,
  /// each with the id `netEdgeId` gives it.
  final List<SchematicEdge> edges;
}

/// Enumerates the wires of [module], one [NetEdges] per net that has at
/// least one driver and one sink.
///
/// The one edge list both the schematic graph (`SchematicGraphBuilder`)
/// and the layout input (`buildElkInput`) are built from, so a wire has the
/// same id on the canvas, in the inspector, in a trace and in the routes.
/// The layout leaves some nets unrouted; it filters whole groups out of this
/// list and never renumbers what remains.
///
/// A driver is a cell output or a module input port; everything else (a
/// cell input, inout or pin with no recorded direction, a module output or
/// inout port) is a sink. Attachments are de-duplicated per net, since Yosys
/// lists a pin once per bit and a bus can carry one net on several bits, and
/// a pin is never paired with itself. Nets keep the order their first
/// attachment appears in (cells, then module ports); drivers and sinks keep
/// theirs within a net.
List<NetEdges> enumerateNetEdges(Module module) {
  final attachmentsByNetId = <int, _NetAttachments>{};

  for (final cell in module.cells.values) {
    for (final entry in cell.connections.entries) {
      final direction = cell.portDirections[entry.key] ?? PortDirection.input;
      final isDriver = direction == PortDirection.output;
      final portId = '${cell.name}:${entry.key}';
      for (final bit in entry.value) {
        if (bit is! NetBit) continue;
        attachmentsByNetId
            .putIfAbsent(bit.netId, _NetAttachments.new)
            .add(portId, isDriver: isDriver);
      }
    }
  }
  for (final port in module.ports.values) {
    final isDriver = port.direction == PortDirection.input;
    final portId = 'port:${port.name}';
    for (final bit in port.bits) {
      if (bit is! NetBit) continue;
      attachmentsByNetId
          .putIfAbsent(bit.netId, _NetAttachments.new)
          .add(portId, isDriver: isDriver);
    }
  }

  final groups = <NetEdges>[];
  for (final entry in attachmentsByNetId.entries) {
    final netId = entry.key;
    final attachments = entry.value;
    final edges = <SchematicEdge>[];
    for (final driver in attachments.drivers) {
      for (final sink in attachments.sinks) {
        if (driver == sink) continue;
        edges.add(
          SchematicEdge(
            id: netEdgeId(netId, edges.length),
            sourcePortId: driver,
            targetPortId: sink,
            netId: netId,
          ),
        );
      }
    }
    if (edges.isNotEmpty) {
      groups.add(NetEdges(netId: netId, edges: List.unmodifiable(edges)));
    }
  }
  return groups;
}

/// The distinct driver and sink pins on one net, in first-seen order.
class _NetAttachments {
  // Linked sets: de-duplicated, insertion-ordered.
  final Set<String> drivers = <String>{};
  final Set<String> sinks = <String>{};

  void add(String portId, {required bool isDriver}) {
    (isDriver ? drivers : sinks).add(portId);
  }
}
