// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:netcrux/domain/models/netlist/bit_ref.dart';
import 'package:netcrux/domain/models/netlist/hierarchy_node.dart';
import 'package:netcrux/domain/models/netlist/module.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/netlist/port_direction.dart';
import 'package:netcrux/domain/models/schematic/cell_kind.dart';
import 'package:netcrux/domain/models/schematic/pin_tie.dart';
import 'package:netcrux/domain/models/schematic/schematic_graph.dart';
import 'package:netcrux/services/schematic/declared_cell_ports.dart';
import 'package:netcrux/services/schematic/net_edge_enumeration.dart';

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
  ///
  /// Every port a cell's module or Yosys primitive declares is drawn, the
  /// unconnected ones included ([withDeclaredCellPorts]); the layout
  /// pipeline lays out the same patched module, so each pin has a place.
  SchematicGraph build(NetlistModel model, HierarchyNode node) {
    final resolved = node.resolve(model);
    if (resolved == null) return SchematicGraph.empty;
    final module = withDeclaredCellPorts(model, resolved);
    final driven = drivenNetIds(module);

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
            tie: pinTieFor(
              portEntry.value,
              direction: direction,
              drivenNets: driven,
            ),
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

    // The shared enumeration `buildElkInput` lays out, so every routed
    // edge carries the id the graph gives the same wire.
    final edges = <SchematicEdge>[
      for (final group in enumerateNetEdges(module)) ...group.edges,
    ];

    return SchematicGraph(
      moduleName: module.name,
      cells: cells,
      boundaryPorts: boundaryPorts,
      edges: edges,
    );
  }

  /// The net ids something in [module] drives: every bit of a cell output
  /// or inout, and of a module input or inout port. A net outside this set
  /// that a cell input reads is undriven in the scope.
  @visibleForTesting
  static Set<int> drivenNetIds(Module module) {
    final driven = <int>{};
    void addBits(Iterable<BitRef> bits) {
      for (final bit in bits) {
        if (bit is NetBit) driven.add(bit.netId);
      }
    }

    for (final cell in module.cells.values) {
      for (final entry in cell.connections.entries) {
        final direction = cell.portDirections[entry.key];
        if (direction == PortDirection.output ||
            direction == PortDirection.inout) {
          addBits(entry.value);
        }
      }
    }
    for (final port in module.ports.values) {
      if (port.direction != PortDirection.output) addBits(port.bits);
    }
    return driven;
  }

  /// What a pin with [bits] and [direction] is tied to, given the
  /// [drivenNets] of its scope.
  ///
  /// No bits is [PinTie.unconnected]. An input with any bit on a net
  /// outside [drivenNets] is [PinTie.undriven], whatever its other bits
  /// are. Otherwise a pin whose every bit is a constant is
  /// [PinTie.constant], and anything else is [PinTie.net]. An output or
  /// inout is never undriven: it is a driver, and an inout's other driver
  /// may sit outside the scope.
  @visibleForTesting
  static PinTie pinTieFor(
    List<BitRef> bits, {
    required PortDirection direction,
    required Set<int> drivenNets,
  }) {
    if (bits.isEmpty) return PinTie.unconnected;
    if (direction == PortDirection.input &&
        bits.any((b) => b is NetBit && !drivenNets.contains(b.netId))) {
      return PinTie.undriven;
    }
    final constants = <ConstantBit>[
      for (final bit in bits)
        if (bit is ConstantBit) bit,
    ];
    if (constants.length != bits.length) return PinTie.net;
    final first = constants.first;
    if (constants.every((b) => b == first)) {
      return PinTie.constant(first.toJson() as String);
    }
    return PinTie.constant(
      constants.reversed.map((b) => b.toJson() as String).join(),
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
}
