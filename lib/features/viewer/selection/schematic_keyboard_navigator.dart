// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:netcrux/domain/models/layout/bounding_box.dart';
import 'package:netcrux/domain/models/schematic/laid_out_graph.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/features/viewer/rendering/schematic_scene_index.dart';

/// Keyboard selection over the elements drawn in one scope.
///
/// The mouse selects by pointing at a cell, a module port or a wire; the
/// keyboard steps to them instead, along two axes:
///
/// * [stepElement] walks the scope's cells and module boundary ports in
///   reading order — top to bottom, then left to right, by laid-out
///   position — so the order matches what a sighted user scans.
/// * [stepConnection] walks what is attached to an anchor element: for a
///   cell, each pin in declaration order followed by the net on it; for a
///   boundary port, its net. Interleaving keeps pins and nets on one axis —
///   a pin and the net it carries are adjacent, which is how a schematic is
///   read — instead of spending a third pair of keys on pins.
///
/// Pure: it reads the [LaidOutGraph] and returns the element to select. The
/// gesture handler applies it, announces it and brings it into view.
class SchematicKeyboardNavigator {
  /// Creates a navigator over [laidOut].
  const SchematicKeyboardNavigator(this.laidOut);

  /// The scope currently drawn on the canvas.
  final LaidOutGraph laidOut;

  /// Cells and boundary ports that have a laid-out position, in reading
  /// order.
  ///
  /// Sorted once per scope and kept in the [SchematicSceneIndex]; every
  /// keypress used to rebuild and re-sort the whole list.
  List<SelectedElement> get elements => _scene.readingOrder;

  SchematicSceneIndex get _scene => SchematicSceneIndex.of(laidOut);

  /// The element after (or, when [forward] is false, before) [current],
  /// wrapping at either end. A pin or a wire counts as the element it
  /// belongs to ([anchorFor]); with nothing selected the walk starts at the
  /// first (or last) element. Returns none when the scope draws nothing.
  SelectedElement stepElement(
    SelectedElement current, {
    required bool forward,
  }) {
    final list = elements;
    if (list.isEmpty) return const SelectedElement.none();
    final index = _scene.readingIndexOf(anchorFor(current));
    if (index == -1) return forward ? list.first : list.last;
    return list[(index + (forward ? 1 : -1)) % list.length];
  }

  /// The element a net walk from [current] is anchored on: a cell or a
  /// boundary port is its own anchor, a pin's anchor is its cell, and a
  /// wire's anchor is the element that drives it. None when [current] is
  /// none or no longer drawn.
  SelectedElement anchorFor(SelectedElement current) => switch (current) {
    SelectedElementCell() || SelectedElementBoundaryPort() => current,
    SelectedElementPort(:final cellId) => SelectedElement.cell(cellId: cellId),
    SelectedElementWire(:final edgeId) => _driverOf(edgeId),
    SelectedElementNone() => const SelectedElement.none(),
  };

  /// What a connection walk visits on [anchor], in pin order: for a cell,
  /// each pin followed by the net on it; for a boundary port, its net. A net
  /// reached through an earlier pin is not repeated, so each net appears
  /// once, as one of its wires.
  List<SelectedElement> connectionsOf(SelectedElement anchor) {
    final seen = <int>{};
    SelectedElementWire? netOn(String pinId) {
      for (final edge in laidOut.graph.edges) {
        if (edge.sourcePortId == pinId || edge.targetPortId == pinId) {
          return seen.add(edge.netId)
              ? SelectedElementWire(edgeId: edge.id, netId: edge.netId)
              : null;
        }
      }
      return null;
    }

    return switch (anchor) {
      SelectedElementCell(:final cellId) => <SelectedElement>[
        for (final cell in laidOut.graph.cells)
          if (cell.id == cellId)
            for (final pin in cell.ports) ...<SelectedElement>[
              SelectedElementPort(
                cellId: cellId,
                portId: pin.id,
                portName: pin.name,
              ),
              ?netOn(pin.id),
            ],
      ],
      SelectedElementBoundaryPort(:final portId) => <SelectedElement>[
        ?netOn(portId),
      ],
      _ => const <SelectedElement>[],
    };
  }

  /// Where [element] sits among [connections]: a pin by identity, a wire by
  /// the net it carries. -1 when it is not one of them.
  static int indexIn(
    List<SelectedElement> connections,
    SelectedElement element,
  ) => switch (element) {
    SelectedElementWire(:final netId) => connections.indexWhere(
      (c) => c is SelectedElementWire && c.netId == netId,
    ),
    SelectedElementPort() => connections.indexOf(element),
    _ => -1,
  };

  /// The pin or net after (or before) [current] among the connections of
  /// [anchor], wrapping. When [current] is not one of them — the anchor
  /// itself is selected — the walk starts at the first (or last). Returns
  /// none when [anchor] has no pins and no nets.
  SelectedElement stepConnection(
    SelectedElement current,
    SelectedElement anchor, {
    required bool forward,
  }) {
    final connections = connectionsOf(anchor);
    if (connections.isEmpty) return const SelectedElement.none();
    final index = indexIn(connections, current);
    if (index == -1) return forward ? connections.first : connections.last;
    return connections[(index + (forward ? 1 : -1)) % connections.length];
  }

  /// The design-space box to bring into view for [element]: its node for a
  /// cell or a boundary port, the hosting cell for a pin, and the driving
  /// element for a wire. Null when nothing is laid out for it.
  BoundingBox? boundsOf(SelectedElement element) =>
      switch (anchorFor(element)) {
        SelectedElementCell(:final cellId) =>
          laidOut.layout.findNode(cellId)?.bounds,
        SelectedElementBoundaryPort(:final portId) =>
          laidOut.layout.findNode(portId)?.bounds,
        _ => null,
      };

  SelectedElement _driverOf(String edgeId) {
    final edge = laidOut.graph.findEdge(edgeId);
    if (edge == null) return const SelectedElement.none();
    final pinId = edge.sourcePortId;
    for (final port in laidOut.graph.boundaryPorts) {
      if (port.id == pinId) {
        return SelectedElement.boundaryPort(
          portId: port.id,
          portName: port.name,
        );
      }
    }
    for (final cell in laidOut.graph.cells) {
      if (cell.ports.any((port) => port.id == pinId)) {
        return SelectedElement.cell(cellId: cell.id);
      }
    }
    return const SelectedElement.none();
  }
}
