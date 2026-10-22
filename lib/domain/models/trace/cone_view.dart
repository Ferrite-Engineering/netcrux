// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:netcrux/domain/models/netlist/hierarchy_node.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';

/// Which way a cone view walks from its root.
enum ConeViewDirection {
  /// The drivers of the root: what feeds it, level by level.
  fanIn,

  /// The drivers and the loads of the root together.
  fanInAndFanOut,
}

/// The depth a cone view starts at when nothing chose another one.
const int kDefaultConeViewDepth = 2;

/// The depth-limited cone views offered, in levels. One level is the
/// one-step fan-in or fan-out trace; every other entry walks that many
/// levels. The cone with no limit ([ConeViewRequest.depth] null) is the Pro
/// form.
const List<int> kConeViewDepths = <int>[1, 2, 3, 4, 6, 8];

/// What a cone view lays out: the neighbourhood of [root] in [scope], walked
/// [direction] for [depth] levels.
///
/// A cone view replaces the scope's full layout on the canvas with a layout
/// of the cone's cells alone. It belongs to the scope it was made in: the
/// canvas shows it only while that scope is selected.
@immutable
class ConeViewRequest {
  /// Creates a request.
  const ConeViewRequest({
    required this.scope,
    required this.root,
    this.direction = ConeViewDirection.fanIn,
    this.depth = kDefaultConeViewDepth,
  });

  /// The scope the cone is cut from.
  final HierarchyNode scope;

  /// The element the cone grows from: a cell, a pin, a wire or a boundary
  /// port of [scope].
  final SelectedElement root;

  /// Which way the walk goes.
  final ConeViewDirection direction;

  /// How many levels the walk takes, or null for the whole cone to the
  /// scope's boundary and its registers' far side (the Pro form).
  final int? depth;

  /// Whether the walk has no depth limit.
  bool get isTransitive => depth == null;

  /// A copy with [direction] replaced.
  ConeViewRequest withDirection(ConeViewDirection direction) => ConeViewRequest(
    scope: scope,
    root: root,
    direction: direction,
    depth: depth,
  );

  /// A copy with [depth] replaced; null makes the walk unlimited.
  ConeViewRequest withDepth(int? depth) => ConeViewRequest(
    scope: scope,
    root: root,
    direction: direction,
    depth: depth,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ConeViewRequest &&
          other.scope == scope &&
          other.root == root &&
          other.direction == direction &&
          other.depth == depth);

  @override
  int get hashCode => Object.hash(scope, root, direction, depth);

  @override
  String toString() =>
      'ConeViewRequest(${scope.path}, $root, $direction, depth: $depth)';
}

/// What the canvas shows when its layout is a cone view: the [request] it
/// answers and how many cells the whole scope holds, so the cone can be
/// described against it.
@immutable
class ConeViewExtent {
  /// Creates an extent.
  const ConeViewExtent({required this.request, required this.scopeCellCount});

  /// The cone the layout is of.
  final ConeViewRequest request;

  /// The number of cells in the whole scope.
  final int scopeCellCount;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ConeViewExtent &&
          other.request == request &&
          other.scopeCellCount == scopeCellCount);

  @override
  int get hashCode => Object.hash(request, scopeCellCount);
}
