// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:netcrux/domain/models/layout/bounding_box.dart';
import 'package:netcrux/domain/models/layout/edge_route.dart';
import 'package:netcrux/domain/models/layout/netlist_layout.dart';
import 'package:netcrux/domain/models/layout/node_position.dart';
import 'package:netcrux/domain/models/schematic/schematic_graph.dart';

/// A [SchematicGraph] paired with the [NetlistLayout] elkjs produced
/// for it. Carries enough metadata that the renderer can paint
/// without holding references back to the parent design / scope.
///
/// Construction is the caller's responsibility — typically the
/// elaboration → graph-build → layout pipeline. This type is pure
/// data, just like [SchematicGraph] and [NetlistLayout].
@immutable
class LaidOutGraph {
  /// Creates a laid-out graph.
  const LaidOutGraph({
    required this.graph,
    required this.layout,
    this.symbolCells = const <String, Set<String>>{},
  });

  /// Empty pair — empty schematic + empty layout. The renderer paints
  /// nothing when handed this.
  static const LaidOutGraph empty = LaidOutGraph(
    graph: SchematicGraph.empty,
    layout: NetlistLayout(
      nodes: <NodePosition>[],
      edges: <EdgeRoute>[],
      bounds: BoundingBox(x: 0, y: 0, width: 0, height: 0),
    ),
  );

  /// Connectivity, cells, boundary ports.
  final SchematicGraph graph;

  /// Positions and routed paths from elkjs.
  final NetlistLayout layout;

  /// The cells drawn with a custom symbol, by cell id, each with the names
  /// of the pins a symbol anchor names exactly. The layout gave these cells
  /// their symbol's shape, so the painter puts their label outside the
  /// drawing and names the listed pins beside them. Empty in open core,
  /// which has no symbols.
  final Map<String, Set<String>> symbolCells;

  /// True when there is nothing to paint.
  bool get isEmpty => graph.isEmpty || layout.nodes.isEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LaidOutGraph &&
          other.graph == graph &&
          other.layout == layout &&
          _symbolCellsEqual(other.symbolCells, symbolCells));

  @override
  int get hashCode => Object.hash(graph, layout, symbolCells.length);

  static bool _symbolCellsEqual(
    Map<String, Set<String>> a,
    Map<String, Set<String>> b,
  ) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      final other = b[entry.key];
      if (other == null || other.length != entry.value.length) return false;
      if (!other.containsAll(entry.value)) return false;
    }
    return true;
  }

  @override
  String toString() =>
      'LaidOutGraph(${graph.moduleName}, '
      '${layout.nodes.length} nodes, ${layout.edges.length} edges)';
}
