// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:netcrux/domain/models/schematic/laid_out_graph.dart';
import 'package:netcrux/domain/models/schematic/schematic_graph.dart';
import 'package:netcrux/features/viewer/rendering/lod_band.dart';
import 'package:netcrux/services/schematic/schematic_annotation_markers_provider.dart';

/// One annotation badge placed on the canvas, in design space.
@immutable
class AnnotationBadge {
  /// Creates a placed badge.
  const AnnotationBadge({required this.marker, required this.center});

  /// The annotated element the badge marks.
  final SchematicAnnotationMarker marker;

  /// The badge's centre, in design-space coordinates.
  final Offset center;
}

/// Where the annotation badges sit and how large they are drawn, shared by
/// the painter and the click test so a click lands on exactly the circle
/// that was painted.
///
/// The corner rule: a badge is centred on the top-right corner of the
/// element it marks. For a cell that is the cell's box; for a pin, the
/// pin's own small box on its cell, so the badge sits beside the pin
/// rather than on the cell's corner; for a boundary port, the port's box.
abstract final class AnnotationBadgeLayout {
  /// The badge radius in design units at the zooms where that is large
  /// enough to see.
  static const double designRadius = 6;

  /// The smallest radius, in screen pixels, a badge is drawn at. At the low
  /// end of the mid band a design-sized badge would shrink to a dot, so the
  /// radius grows in design units to hold this on screen.
  static const double minScreenRadius = 5;

  /// Whether badges are drawn in [band]. The overview band draws each cell
  /// as a coloured block a few pixels across, too small to carry a badge.
  static bool drawnIn(LodBand band) => band != LodBand.overview;

  /// The badge radius, in design units, at [zoom].
  static double radiusAt(double zoom) =>
      zoom > 0 ? math.max(designRadius, minScreenRadius / zoom) : designRadius;

  /// The anchor of a badge for an element occupying [rect].
  static Offset anchorOf(Rect rect) => rect.topRight;

  /// Places a badge for every marker whose element is laid out in
  /// [laidOut], in paint order: cells, then pins, then boundary ports.
  /// A marker whose element is not on this layout is skipped.
  ///
  /// O(markers): every element resolves through [NetlistLayout.findNode]'s
  /// O(1) index, never a scan of the design.
  static List<AnnotationBadge> place(
    LaidOutGraph laidOut,
    SchematicAnnotationMarkers markers,
  ) {
    final layout = laidOut.layout;
    final badges = <AnnotationBadge>[];
    for (final marker in markers.cells.values) {
      final node = layout.findNode(marker.targetId);
      if (node == null) continue;
      badges.add(
        AnnotationBadge(
          marker: marker,
          center: anchorOf(
            Rect.fromLTWH(
              node.bounds.x,
              node.bounds.y,
              node.bounds.width,
              node.bounds.height,
            ),
          ),
        ),
      );
    }
    for (final marker in markers.pins.values) {
      final cellId = cellIdOfPinId(marker.targetId);
      if (cellId == null) continue;
      final node = layout.findNode(cellId);
      final box = node?.ports[marker.targetId];
      if (node == null || box == null) continue;
      badges.add(
        AnnotationBadge(
          marker: marker,
          center: anchorOf(
            Rect.fromLTWH(
              node.bounds.x + box.x,
              node.bounds.y + box.y,
              box.width,
              box.height,
            ),
          ),
        ),
      );
    }
    for (final marker in markers.boundaryPorts.values) {
      final node = layout.findNode(marker.targetId);
      if (node == null) continue;
      badges.add(
        AnnotationBadge(
          marker: marker,
          center: anchorOf(
            Rect.fromLTWH(
              node.bounds.x,
              node.bounds.y,
              node.bounds.width,
              node.bounds.height,
            ),
          ),
        ),
      );
    }
    return badges;
  }

  /// The badge under [designPoint] at [zoom], or `null` when the point is
  /// on none or the zoom's band draws no badges. When badges overlap, the
  /// one painted last, which is the one on top, wins.
  static AnnotationBadge? hitTest({
    required LaidOutGraph laidOut,
    required SchematicAnnotationMarkers markers,
    required double zoom,
    required Offset designPoint,
  }) {
    if (markers.isEmpty || !drawnIn(LodBandRouter.bandFor(zoom))) {
      return null;
    }
    final radius = radiusAt(zoom);
    final badges = place(laidOut, markers);
    for (var i = badges.length - 1; i >= 0; i--) {
      if ((badges[i].center - designPoint).distance <= radius) {
        return badges[i];
      }
    }
    return null;
  }
}

/// The colours an annotation badge is drawn in, taken from the theme so the
/// badge follows the colour preset.
@immutable
class AnnotationBadgeColors {
  /// Creates the colour set.
  const AnnotationBadgeColors({
    required this.fill,
    required this.glyph,
    required this.ring,
  });

  /// The colours for [theme]: the secondary role for the disc and its
  /// on-colour for the note glyph, ringed in the canvas background so the
  /// badge separates from the cell outline it overlaps.
  factory AnnotationBadgeColors.of(ThemeData theme) {
    final scheme = theme.colorScheme;
    return AnnotationBadgeColors(
      fill: scheme.secondary,
      glyph: scheme.onSecondary,
      ring: scheme.surface,
    );
  }

  /// The disc.
  final Color fill;

  /// The lines of the note glyph on the disc.
  final Color glyph;

  /// The thin ring around the disc.
  final Color ring;
}
