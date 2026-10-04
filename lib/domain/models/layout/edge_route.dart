// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:netcrux/domain/models/schematic/schematic_graph.dart';

/// A single (x, y) point in layout coordinates.
@immutable
class LayoutPoint {
  /// Creates a point.
  const LayoutPoint(this.x, this.y);

  /// Parses `{ "x": …, "y": … }`.
  factory LayoutPoint.fromJson(Map<String, Object?> json) =>
      LayoutPoint(_asDouble(json['x']), _asDouble(json['y']));

  /// X coordinate.
  final double x;

  /// Y coordinate.
  final double y;

  /// Serializes to the JSON shape consumed by [LayoutPoint.fromJson].
  Map<String, Object?> toJson() => <String, Object?>{'x': x, 'y': y};

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LayoutPoint && other.x == x && other.y == y);

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => '($x, $y)';
}

/// Routed path of one edge in an ELK layout.
///
/// ELK emits edges with one or more *sections* (each a polyline from a
/// start point through bend points to an end point). They are
/// flattened to a single ordered list of [points]; the start of
/// the path is `points.first` and the end is `points.last`. The optional
/// [sourceNodeId] / [targetNodeId] / [sourcePortId] / [targetPortId]
/// retain enough metadata for a renderer to highlight the endpoints or
/// for cross-probe code to ask "what edge connects these two pins?".
@immutable
class EdgeRoute {
  /// Creates an edge route.
  const EdgeRoute({
    required this.id,
    required this.points,
    this.sourceNodeId,
    this.targetNodeId,
    this.sourcePortId,
    this.targetPortId,
  });

  /// Parses ELK's edge JSON. Accepts both the modern `sections` shape
  /// (preferred) and the legacy `bendPoints` shape (older ELK
  /// releases).
  factory EdgeRoute.fromJson(Map<String, Object?> json) {
    final points = <LayoutPoint>[];

    final sections = json['sections'];
    if (sections is List<Object?>) {
      for (final raw in sections) {
        if (raw is! Map<String, Object?>) continue;
        final start = raw['startPoint'];
        if (start is Map<String, Object?>) {
          points.add(LayoutPoint.fromJson(start));
        }
        final bends = raw['bendPoints'];
        if (bends is List<Object?>) {
          for (final bend in bends) {
            if (bend is Map<String, Object?>) {
              points.add(LayoutPoint.fromJson(bend));
            }
          }
        }
        final end = raw['endPoint'];
        if (end is Map<String, Object?>) {
          points.add(LayoutPoint.fromJson(end));
        }
      }
    } else {
      // Legacy shape: flat bendPoints array on the edge object.
      final bends = json['bendPoints'];
      if (bends is List<Object?>) {
        for (final bend in bends) {
          if (bend is Map<String, Object?>) {
            points.add(LayoutPoint.fromJson(bend));
          }
        }
      }
    }

    return EdgeRoute(
      id: json['id']! as String,
      points: points,
      sourceNodeId: json['source'] as String?,
      targetNodeId: json['target'] as String?,
      sourcePortId: json['sourcePort'] as String?,
      targetPortId: json['targetPort'] as String?,
    );
  }

  /// Edge identifier used to cross-reference back to the original graph.
  final String id;

  /// Polyline of (x, y) points the edge passes through, in order.
  /// `points.first` is the start; `points.last` is the end. Length is
  /// always ≥ 2 for a well-formed ELK output, but the model accepts
  /// shorter lists for defensive parsing.
  final List<LayoutPoint> points;

  /// Source node id (the cell the edge leaves), if known.
  final String? sourceNodeId;

  /// Target node id (the cell the edge enters), if known.
  final String? targetNodeId;

  /// Source port id on [sourceNodeId], if the layout includes port-level
  /// routing.
  final String? sourcePortId;

  /// Target port id on [targetNodeId], if the layout includes port-level
  /// routing.
  final String? targetPortId;

  /// The Yosys net id this routed edge carries, parsed from the [id]'s
  /// `e_<netId>_<k>` form, where `k` counts the edge within its net: the
  /// ids [netEdgeId] makes and `enumerateNetEdges` gives, which the ELK layout input and
  /// `SchematicGraphBuilder` share. Returns `null` for ids that don't
  /// follow that scheme (e.g. hand-authored test ids like `e1`), so
  /// callers fall back to id matching.
  ///
  /// The renderer keys wire-selection highlighting off this as well as
  /// the [id], so a selected wire lights every routed segment of its net.
  int? get netId => netIdOfEdgeId(id);

  /// Returns a copy with the given fields replaced.
  EdgeRoute copyWith({
    String? id,
    List<LayoutPoint>? points,
    String? sourceNodeId,
    String? targetNodeId,
    String? sourcePortId,
    String? targetPortId,
  }) {
    return EdgeRoute(
      id: id ?? this.id,
      points: points ?? this.points,
      sourceNodeId: sourceNodeId ?? this.sourceNodeId,
      targetNodeId: targetNodeId ?? this.targetNodeId,
      sourcePortId: sourcePortId ?? this.sourcePortId,
      targetPortId: targetPortId ?? this.targetPortId,
    );
  }

  /// Serializes to the modern ELK `sections` shape (single section).
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    if (sourceNodeId != null) 'source': sourceNodeId,
    if (targetNodeId != null) 'target': targetNodeId,
    if (sourcePortId != null) 'sourcePort': sourcePortId,
    if (targetPortId != null) 'targetPort': targetPortId,
    'sections': <Map<String, Object?>>[
      if (points.length >= 2)
        <String, Object?>{
          'startPoint': points.first.toJson(),
          if (points.length > 2)
            'bendPoints': <Map<String, Object?>>[
              for (final bend in points.sublist(1, points.length - 1))
                bend.toJson(),
            ],
          'endPoint': points.last.toJson(),
        },
    ],
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! EdgeRoute) return false;
    if (other.id != id) return false;
    if (other.sourceNodeId != sourceNodeId) return false;
    if (other.targetNodeId != targetNodeId) return false;
    if (other.sourcePortId != sourcePortId) return false;
    if (other.targetPortId != targetPortId) return false;
    if (other.points.length != points.length) return false;
    for (var i = 0; i < points.length; i++) {
      if (other.points[i] != points[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    id,
    sourceNodeId,
    targetNodeId,
    sourcePortId,
    targetPortId,
    Object.hashAll(points),
  );

  @override
  String toString() => 'EdgeRoute(id: $id, points: ${points.length})';
}

double _asDouble(Object? value) {
  if (value == null) return 0;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0;
  return 0;
}
