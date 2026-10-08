// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:netcrux/domain/models/bookmark.dart';

/// One annotated element on the scope the canvas shows: the element, and
/// the annotations written on it.
///
/// [kind] and [targetId] use the bookmark target taxonomy
/// ([BookmarkTargetKind]), so a marker names the element the same way the
/// annotation that produced it does.
@immutable
class SchematicAnnotationMarker {
  /// Creates a marker.
  const SchematicAnnotationMarker({
    required this.kind,
    required this.targetId,
    required this.annotationIds,
  });

  /// Which kind of element is annotated.
  final BookmarkTargetKind kind;

  /// The element's id on the canvas: a cell id, a `<cell>:<port>` pin id,
  /// or a `port:<name>` boundary-port id.
  final String targetId;

  /// The ids of the annotations on the element, oldest first. Never empty.
  final List<String> annotationIds;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! SchematicAnnotationMarker) return false;
    if (other.kind != kind || other.targetId != targetId) return false;
    if (other.annotationIds.length != annotationIds.length) return false;
    for (var i = 0; i < annotationIds.length; i++) {
      if (other.annotationIds[i] != annotationIds[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(kind, targetId, Object.hashAll(annotationIds));

  @override
  String toString() =>
      'SchematicAnnotationMarker($kind:$targetId, ${annotationIds.length})';
}

/// The annotated elements of the scope the canvas shows, which the
/// schematic painter marks with a badge and the gesture handler hit-tests.
///
/// Only the element kinds the canvas can badge are kept: cells, cell pins
/// and boundary ports. A net's annotation has no corner to sit on, and a
/// scope's annotation is about the whole sheet, so both are left to the
/// Annotations panel.
///
/// This is the seam on-canvas annotation surfaces build on. The painter
/// reads only which elements carry a marker; a richer surface (a callout
/// showing the note beside its element) reads the same markers, through the
/// same provider, and resolves [SchematicAnnotationMarker.annotationIds]
/// against the annotation store for the text.
@immutable
class SchematicAnnotationMarkers {
  /// Creates a marker set from per-kind maps keyed by element id.
  const SchematicAnnotationMarkers({
    this.cells = const <String, SchematicAnnotationMarker>{},
    this.pins = const <String, SchematicAnnotationMarker>{},
    this.boundaryPorts = const <String, SchematicAnnotationMarker>{},
  });

  /// Builds a marker set from [markers], dropping the kinds the canvas
  /// cannot badge. A second marker for the same element is merged into the
  /// first, keeping the annotation ids in order.
  factory SchematicAnnotationMarkers.from(
    Iterable<SchematicAnnotationMarker> markers,
  ) {
    final cells = <String, SchematicAnnotationMarker>{};
    final pins = <String, SchematicAnnotationMarker>{};
    final boundaryPorts = <String, SchematicAnnotationMarker>{};
    for (final marker in markers) {
      if (marker.annotationIds.isEmpty) continue;
      final into = switch (marker.kind) {
        BookmarkTargetKind.cell => cells,
        BookmarkTargetKind.port => pins,
        BookmarkTargetKind.boundaryPort => boundaryPorts,
        BookmarkTargetKind.net || BookmarkTargetKind.scope => null,
      };
      if (into == null) continue;
      final existing = into[marker.targetId];
      into[marker.targetId] = existing == null
          ? marker
          : SchematicAnnotationMarker(
              kind: marker.kind,
              targetId: marker.targetId,
              annotationIds: <String>[
                ...existing.annotationIds,
                ...marker.annotationIds,
              ],
            );
    }
    return SchematicAnnotationMarkers(
      cells: Map<String, SchematicAnnotationMarker>.unmodifiable(cells),
      pins: Map<String, SchematicAnnotationMarker>.unmodifiable(pins),
      boundaryPorts: Map<String, SchematicAnnotationMarker>.unmodifiable(
        boundaryPorts,
      ),
    );
  }

  /// The empty set, which the painter treats exactly like `null`.
  static const SchematicAnnotationMarkers empty = SchematicAnnotationMarkers();

  /// Annotated cells, by cell id.
  final Map<String, SchematicAnnotationMarker> cells;

  /// Annotated cell pins, by `<cell>:<port>` pin id.
  final Map<String, SchematicAnnotationMarker> pins;

  /// Annotated boundary ports, by `port:<name>` id.
  final Map<String, SchematicAnnotationMarker> boundaryPorts;

  /// True when no element carries a marker.
  bool get isEmpty => cells.isEmpty && pins.isEmpty && boundaryPorts.isEmpty;

  /// Every marker: cells, then pins, then boundary ports.
  Iterable<SchematicAnnotationMarker> get all => <SchematicAnnotationMarker>[
    ...cells.values,
    ...pins.values,
    ...boundaryPorts.values,
  ];

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! SchematicAnnotationMarkers) return false;
    return _mapEquals(other.cells, cells) &&
        _mapEquals(other.pins, pins) &&
        _mapEquals(other.boundaryPorts, boundaryPorts);
  }

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(cells.values),
    Object.hashAllUnordered(pins.values),
    Object.hashAllUnordered(boundaryPorts.values),
  );

  static bool _mapEquals(
    Map<String, SchematicAnnotationMarker> a,
    Map<String, SchematicAnnotationMarker> b,
  ) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }
}

/// The annotated elements of the scope on the canvas, published by the
/// annotations feature for the painter and the gesture handler.
///
/// The root-scope instance resolves to `null`: the root has no design on
/// screen, so the painter skips the badge pass and the gesture handler never
/// finds a badge under a click. The per-tab override list re-binds it with a
/// provider derived from the tab's annotations and the scope its hierarchy
/// shows, the same shape as `schematicCrossingOverlayProvider`.
///
/// Declared as a manual `Provider` so the tab override list overrides it with
/// `.overrideWith` without a codegen dependency.
final schematicAnnotationMarkersProvider =
    Provider<SchematicAnnotationMarkers?>(
      (_) => null,
      name: 'schematicAnnotationMarkersProvider',
    );
