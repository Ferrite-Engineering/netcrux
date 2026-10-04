// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:netcrux/domain/models/layout/bounding_box.dart';
import 'package:netcrux/domain/models/layout/edge_route.dart';
import 'package:netcrux/domain/models/schematic/laid_out_graph.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/domain/models/trace/trace_overlay.dart';

/// The design-space box Zoom to Selection frames: the union of every selected
/// element and, while a trace overlay is active, every cell, wire and
/// boundary port the overlay highlights.
///
/// A cell or boundary port contributes its laid-out node, a pin its host
/// cell, and a wire every routed segment of its net (a wire is matched on
/// its net id as well as its edge id, the way the painter highlights it).
/// Overlay edge ids are graph ids, which the routes share; an overlay edge
/// on a net the layout leaves unrouted has no route and adds nothing.
/// Returns `null` when nothing resolves to laid-out geometry.
///
/// The result is never thinner than [minExtent] on either axis: a single
/// straight wire has zero height, and the viewport fit refuses an empty box.
BoundingBox? selectionBounds(
  LaidOutGraph laidOut, {
  required Iterable<SelectedElement> selection,
  TraceOverlay overlay = TraceOverlay.empty,
  double minExtent = 40,
}) {
  if (laidOut.isEmpty) return null;
  final layout = laidOut.layout;
  final boxes = <BoundingBox>[];

  void addNode(String id) {
    final node = layout.findNode(id);
    if (node != null) boxes.add(node.bounds);
  }

  void addRoute(EdgeRoute route) {
    final box = _routeBounds(route);
    if (box != null) boxes.add(box);
  }

  void addEdge(String edgeId, {int? netId}) {
    final route = layout.findEdge(edgeId);
    if (route != null) addRoute(route);
    if (netId == null) return;
    for (final candidate in layout.edges) {
      if (candidate.id != edgeId && candidate.netId == netId) {
        addRoute(candidate);
      }
    }
  }

  for (final element in selection) {
    switch (element) {
      case SelectedElementCell(:final cellId):
        addNode(cellId);
      case SelectedElementPort(:final cellId):
        addNode(cellId);
      case SelectedElementBoundaryPort(:final portId):
        addNode(portId);
      case SelectedElementWire(:final edgeId, :final netId):
        addEdge(edgeId, netId: netId);
      case SelectedElementNone():
        break;
    }
  }
  overlay.highlightedCellIds.forEach(addNode);
  overlay.highlightedBoundaryPortIds.forEach(addNode);
  overlay.highlightedEdgeIds.forEach(addEdge);

  final union = BoundingBox.encompass(boxes);
  if (union == null) return null;
  return _atLeast(union, minExtent);
}

BoundingBox? _routeBounds(EdgeRoute route) {
  if (route.points.isEmpty) return null;
  var minX = route.points.first.x;
  var minY = route.points.first.y;
  var maxX = minX;
  var maxY = minY;
  for (final point in route.points) {
    if (point.x < minX) minX = point.x;
    if (point.y < minY) minY = point.y;
    if (point.x > maxX) maxX = point.x;
    if (point.y > maxY) maxY = point.y;
  }
  return BoundingBox(x: minX, y: minY, width: maxX - minX, height: maxY - minY);
}

BoundingBox _atLeast(BoundingBox box, double extent) {
  final width = box.width < extent ? extent : box.width;
  final height = box.height < extent ? extent : box.height;
  return BoundingBox(
    x: box.x - (width - box.width) / 2,
    y: box.y - (height - box.height) / 2,
    width: width,
    height: height,
  );
}
