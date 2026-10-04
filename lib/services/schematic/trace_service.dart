// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:netcrux/domain/models/schematic/laid_out_graph.dart';
import 'package:netcrux/domain/models/schematic/schematic_graph.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/domain/models/trace/trace_overlay.dart';

/// Computes a fanin / fanout overlay for a selected element.
///
/// Pure function — given a graph, a selection, and a mode, return the
/// set of element ids the painter should keep at full intensity.
///
/// "One-step" tracing semantics: include the directly connected
/// drivers (fanin) or sinks (fanout) of the selected element, plus
/// the edges that connect them, plus the originating cell itself so
/// the user can see where the trace started.
@immutable
class TraceService {
  /// Creates a tracer.
  const TraceService();

  /// Builds a [TraceOverlay] for [selection] inside [laidOut] under
  /// [mode]. Returns [TraceOverlay.empty] when the selection is none
  /// or when no edges are connected.
  TraceOverlay compute({
    required LaidOutGraph laidOut,
    required SelectedElement selection,
    required TraceOverlayMode mode,
  }) {
    if (laidOut.isEmpty) return TraceOverlay.empty;
    final cellIds = <String>{};
    final edgeIds = <String>{};
    final boundaryIds = <String>{};

    final relevantPortIds = _portIdsFor(selection, laidOut);
    if (relevantPortIds.isEmpty) return TraceOverlay.empty;

    // Anchor the originating element.
    switch (selection) {
      case SelectedElementNone():
        return TraceOverlay.empty;
      case SelectedElementCell(:final cellId):
        cellIds.add(cellId);
      case SelectedElementPort(:final cellId):
        cellIds.add(cellId);
      case SelectedElementBoundaryPort(:final portId):
        boundaryIds.add(portId);
      case SelectedElementWire(:final edgeId):
        edgeIds.add(edgeId);
        for (final edge in laidOut.graph.edges) {
          if (edge.id == edgeId) {
            _addPortHost(edge.sourcePortId, cellIds, boundaryIds);
            _addPortHost(edge.targetPortId, cellIds, boundaryIds);
          }
        }
    }

    final targetIsSource = mode == TraceOverlayMode.fanout;
    for (final edge in laidOut.graph.edges) {
      final connectedPortId = targetIsSource
          ? edge.sourcePortId
          : edge.targetPortId;
      final otherPortId = targetIsSource
          ? edge.targetPortId
          : edge.sourcePortId;
      if (relevantPortIds.contains(connectedPortId)) {
        edgeIds.add(edge.id);
        _addPortHost(otherPortId, cellIds, boundaryIds);
      }
    }

    return TraceOverlay(
      mode: mode,
      highlightedCellIds: Set<String>.unmodifiable(cellIds),
      highlightedEdgeIds: Set<String>.unmodifiable(edgeIds),
      highlightedBoundaryPortIds: Set<String>.unmodifiable(boundaryIds),
    );
  }

  /// Returns the set of port-ids that should be considered "the
  /// trace anchor" for the given [selection].
  ///
  /// - Cell selection: all output ports of the cell are anchors for
  ///   fanout; all input ports are anchors for fanin. (We return the
  ///   whole pin set and let the edge filter pick which side matters.)
  /// - Port selection: just that port.
  /// - Wire selection: both endpoint ports.
  /// - Boundary port selection: the boundary port id.
  /// - None: empty set.
  Set<String> _portIdsFor(SelectedElement selection, LaidOutGraph laidOut) {
    switch (selection) {
      case SelectedElementNone():
        return const <String>{};
      case SelectedElementCell(:final cellId):
        return <String>{
          for (final cell in laidOut.graph.cells)
            if (cell.id == cellId)
              for (final port in cell.ports) port.id,
        };
      case SelectedElementPort(:final portId):
        return <String>{portId};
      case SelectedElementBoundaryPort(:final portId):
        return <String>{portId};
      case SelectedElementWire(:final edgeId):
        return <String>{
          for (final edge in laidOut.graph.edges)
            if (edge.id == edgeId) ...<String>[
              edge.sourcePortId,
              edge.targetPortId,
            ],
        };
    }
  }

  /// Helper: given a port id (`<cellName>:<portName>` or
  /// `port:<name>`), add the hosting cell or boundary id to the
  /// matching highlight set.
  void _addPortHost(
    String portId,
    Set<String> cellIds,
    Set<String> boundaries,
  ) {
    if (portId.startsWith('port:')) {
      boundaries.add(portId);
      return;
    }
    final cellId = cellIdOfPinId(portId);
    if (cellId != null) cellIds.add(cellId);
  }
}
