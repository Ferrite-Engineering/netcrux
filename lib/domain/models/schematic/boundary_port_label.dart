// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:math' as math;

import 'package:netcrux/domain/models/netlist/port_direction.dart';
import 'package:netcrux/domain/models/schematic/schematic_graph.dart';

/// Where a module port's name goes, and how much room the layout leaves for
/// it. The layout (`buildElkInput`), the canvas and the SVG export all follow
/// these rules, so the room the layout leaves is where the name is drawn.
abstract final class BoundaryPortLabel {
  /// The widest a port's name is drawn, in layout units. A longer name is
  /// cut short with an ellipsis.
  static const double maxWidth = 80;

  /// The height the layout leaves for a port's name: one line of the small
  /// label style.
  static const double height = 16;

  /// The width the layout leaves per character of a port's name: a little
  /// more than the average advance of the small label style, so a name
  /// fits in the room left for it.
  static const double charAdvance = 7;

  /// The width the layout leaves for the name [name].
  static double widthFor(String name) =>
      math.min(maxWidth, name.length * charAdvance);

  /// Whether a port's name goes on the west side of its box.
  ///
  /// An input's wire leaves the east face of its box, and so does the wire of
  /// an inout port that drives its net (a supply net, say, that nothing else
  /// drives). Every other port's wire arrives at the west face. The name goes
  /// on the side its wire does not use, so it never lies over that wire.
  static bool onWest({
    required PortDirection direction,
    required bool drivesWire,
  }) =>
      direction == PortDirection.input ||
      (direction == PortDirection.inout && drivesWire);

  /// Whether [port]'s name goes on the west side of its box in [graph].
  static bool onWestIn(SchematicGraph graph, SchematicBoundaryPort port) =>
      onWest(
        direction: port.direction,
        drivesWire:
            port.direction == PortDirection.inout &&
            _drivingPorts(graph).contains(port.id),
      );

  static final Expando<Set<String>> _driving = Expando<Set<String>>(
    'BoundaryPortLabel.driving',
  );

  /// The ids of [graph]'s boundary ports that are the source of a wire,
  /// worked out once per graph.
  static Set<String> _drivingPorts(SchematicGraph graph) =>
      _driving[graph] ??= () {
        final ports = <String>{for (final p in graph.boundaryPorts) p.id};
        return <String>{
          for (final edge in graph.edges)
            if (ports.contains(edge.sourcePortId)) edge.sourcePortId,
        };
      }();
}
