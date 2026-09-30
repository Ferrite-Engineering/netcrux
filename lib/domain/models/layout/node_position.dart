// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:netcrux/domain/models/layout/bounding_box.dart';

/// Position and size of one node in an ELK-style layout.
///
/// The [id] matches the corresponding node identifier in the original
/// graph (typically a cell instance name or a module port name). The
/// optional [ports] map carries per-port positions relative to the node
/// origin — useful for hooking edge endpoints onto specific pins on the
/// rendered cell.
@immutable
class NodePosition {
  /// Creates a node position.
  const NodePosition({
    required this.id,
    required this.bounds,
    this.ports = const <String, BoundingBox>{},
  });

  /// Parses ELK's node JSON: `{ "id": …, "x": …, "y": …, "width": …,
  /// "height": …, "ports": [{"id": …, "x": …, …}, …] }`.
  factory NodePosition.fromJson(Map<String, Object?> json) {
    final ports = <String, BoundingBox>{};
    final rawPorts = json['ports'] as List<Object?>? ?? const <Object?>[];
    for (final port in rawPorts) {
      if (port is! Map<String, Object?>) continue;
      final portId = port['id'];
      if (portId is! String) continue;
      ports[portId] = BoundingBox.fromJson(port);
    }
    return NodePosition(
      id: json['id']! as String,
      bounds: BoundingBox.fromJson(json),
      ports: ports,
    );
  }

  /// Node identifier used to cross-reference back to the original graph.
  final String id;

  /// Position and size of the node.
  final BoundingBox bounds;

  /// Port positions keyed by port id. Coordinates are in the same
  /// reference frame as [bounds] (ELK's convention).
  final Map<String, BoundingBox> ports;

  /// Returns a copy with the given fields replaced.
  NodePosition copyWith({
    String? id,
    BoundingBox? bounds,
    Map<String, BoundingBox>? ports,
  }) {
    return NodePosition(
      id: id ?? this.id,
      bounds: bounds ?? this.bounds,
      ports: ports ?? this.ports,
    );
  }

  /// Serializes to the JSON shape consumed by [NodePosition.fromJson].
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    ...bounds.toJson(),
    'ports': <Map<String, Object?>>[
      for (final entry in ports.entries)
        <String, Object?>{
          'id': entry.key,
          ...entry.value.toJson(),
        },
    ],
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! NodePosition) return false;
    if (other.id != id) return false;
    if (other.bounds != bounds) return false;
    if (other.ports.length != ports.length) return false;
    for (final entry in ports.entries) {
      if (other.ports[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(id, bounds, _mapHash(ports));

  @override
  String toString() =>
      'NodePosition(id: $id, bounds: $bounds, ports: ${ports.length})';
}

int _mapHash<K, V>(Map<K, V> map) {
  var hash = 0;
  for (final entry in map.entries) {
    hash ^= Object.hash(entry.key, entry.value);
  }
  return hash;
}
