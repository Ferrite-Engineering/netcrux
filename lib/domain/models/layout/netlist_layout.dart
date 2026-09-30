// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:netcrux/domain/models/layout/bounding_box.dart';
import 'package:netcrux/domain/models/layout/edge_route.dart';
import 'package:netcrux/domain/models/layout/node_position.dart';

/// Result of running an ELK layout over one netlist scope. Contains the
/// laid-out [nodes], the routed [edges], and the overall [bounds] of the
/// composition (the bounding box of the root container).
@immutable
class NetlistLayout {
  /// Creates a layout.
  const NetlistLayout({
    required this.nodes,
    required this.edges,
    required this.bounds,
  });

  /// Parses ELK's root layout output: `{ "id": "root", "x": …, "y": …,
  /// "width": …, "height": …, "children": [...], "edges": [...] }`.
  ///
  /// Tolerant of missing/empty `children` and `edges` keys so callers
  /// don't need to special-case "no graph to lay out".
  factory NetlistLayout.fromJson(Map<String, Object?> json) {
    final bounds = BoundingBox.fromJson(json);
    final children = json['children'] as List<Object?>? ?? const <Object?>[];
    final nodes = <NodePosition>[
      for (final child in children)
        if (child is Map<String, Object?>) NodePosition.fromJson(child),
    ];
    final edgesRaw = json['edges'] as List<Object?>? ?? const <Object?>[];
    final edges = <EdgeRoute>[
      for (final edge in edgesRaw)
        if (edge is Map<String, Object?>) EdgeRoute.fromJson(edge),
    ];
    return NetlistLayout(nodes: nodes, edges: edges, bounds: bounds);
  }

  /// Position and size of each laid-out node.
  final List<NodePosition> nodes;

  /// Routed edges between nodes.
  final List<EdgeRoute> edges;

  /// Overall layout bounds, taken from the root ELK container.
  final BoundingBox bounds;

  /// Looks up a node by id in O(1). Returns `null` when there is no
  /// node with that id.
  ///
  /// Backed by [_nodesById], a lazily-built id→node index. The viewer
  /// resolves elements by id throughout — once per cell and module port
  /// when a scope's scene index is built, and per frame for the selection
  /// and presence overlays — so the former linear scan made those paths
  /// O(n²); the cache makes them O(n).
  NodePosition? findNode(String id) => _nodesById[id];

  /// Looks up an edge by id in O(1). Returns `null` when there is no
  /// edge with that id. Backed by [_edgesById].
  EdgeRoute? findEdge(String id) => _edgesById[id];

  /// Lazily-built id→node index, memoized per instance via [_nodeIndexCache].
  ///
  /// [NetlistLayout] is immutable, so the index is built at most once
  /// per instance and reused for every [findNode]. The cache is an
  /// identity [Expando] rather than a field so the `const` constructor
  /// (and its `const NetlistLayout(...)` call sites) are preserved and
  /// the entry is garbage-collected with the layout. This mirrors the
  /// identity-cache idiom in the Pro `connectivity_projection`.
  ///
  /// On the (malformed) duplicate-id case the first occurrence wins,
  /// matching the previous first-match scan semantics.
  Map<String, NodePosition> get _nodesById =>
      _nodeIndexCache[this] ??= _indexById<NodePosition>(
        nodes,
        (node) => node.id,
      );

  /// Lazily-built id→edge index, memoized per instance via [_edgeIndexCache].
  Map<String, EdgeRoute> get _edgesById =>
      _edgeIndexCache[this] ??= _indexById<EdgeRoute>(
        edges,
        (edge) => edge.id,
      );

  /// Builds an id→item map preserving first-match semantics (the linear
  /// scans this replaces returned the first item with a matching id).
  static Map<String, T> _indexById<T>(
    List<T> items,
    String Function(T) idOf,
  ) {
    final index = <String, T>{};
    for (final item in items) {
      index.putIfAbsent(idOf(item), () => item);
    }
    return index;
  }

  /// Per-instance identity caches for the lazily-built lookup indices.
  /// Keyed by object identity, so equal-but-distinct layouts get their
  /// own index and entries are freed when the layout is collected.
  static final Expando<Map<String, NodePosition>> _nodeIndexCache =
      Expando<Map<String, NodePosition>>('NetlistLayout.nodeIndex');
  static final Expando<Map<String, EdgeRoute>> _edgeIndexCache =
      Expando<Map<String, EdgeRoute>>('NetlistLayout.edgeIndex');

  /// Returns a copy with the given fields replaced.
  NetlistLayout copyWith({
    List<NodePosition>? nodes,
    List<EdgeRoute>? edges,
    BoundingBox? bounds,
  }) {
    return NetlistLayout(
      nodes: nodes ?? this.nodes,
      edges: edges ?? this.edges,
      bounds: bounds ?? this.bounds,
    );
  }

  /// Serializes to ELK's root shape.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': 'root',
    ...bounds.toJson(),
    'children': <Map<String, Object?>>[
      for (final node in nodes) node.toJson(),
    ],
    'edges': <Map<String, Object?>>[
      for (final edge in edges) edge.toJson(),
    ],
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! NetlistLayout) return false;
    if (other.bounds != bounds) return false;
    if (other.nodes.length != nodes.length) return false;
    for (var i = 0; i < nodes.length; i++) {
      if (other.nodes[i] != nodes[i]) return false;
    }
    if (other.edges.length != edges.length) return false;
    for (var i = 0; i < edges.length; i++) {
      if (other.edges[i] != edges[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    bounds,
    Object.hashAll(nodes),
    Object.hashAll(edges),
  );

  @override
  String toString() =>
      'NetlistLayout(nodes: ${nodes.length}, edges: ${edges.length}, bounds: $bounds)';
}
