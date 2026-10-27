// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_annotations/crux_annotations.dart';
import 'package:flutter/painting.dart';
import 'package:netcrux/domain/models/annotation.dart';
import 'package:netcrux/domain/models/annotation_target.dart';
import 'package:netcrux/domain/models/schematic/laid_out_graph.dart';
import 'package:netcrux/domain/models/schematic/schematic_graph.dart';
import 'package:netcrux/features/viewer/rendering/lod_band.dart';

/// Where a note's callout is anchored on the laid-out schematic, in design
/// coordinates, or `null` when its element is not on this layout (a scope, a
/// net with no routed wire here, an element of another module).
///
/// The anchor is data, never pixels: an element of the laid-out scope,
/// projected afresh on every frame through the viewport transform, so the
/// callout stays on its element through pan, zoom and re-layout.
///
/// * a cell or a boundary port: the middle of the top edge of its box, beside
///   the corner badge rather than on it;
/// * a pin: the centre of the pin's box on its cell;
/// * a net: the middle point of its wire's route.
Offset? calloutAnchorInDesign(LaidOutGraph laidOut, Annotation note) {
  final layout = laidOut.layout;
  switch (note.targetKind) {
    case AnnotationTargetKind.cell:
    case AnnotationTargetKind.boundaryPort:
      final node = layout.findNode(note.targetId);
      if (node == null) return null;
      final b = node.bounds;
      return Offset(b.x + b.width / 2, b.y);
    case AnnotationTargetKind.port:
      final cellId = cellIdOfPinId(note.targetId);
      if (cellId == null) return null;
      final node = layout.findNode(cellId);
      final box = node?.ports[note.targetId];
      if (node == null || box == null) return null;
      return Offset(
        node.bounds.x + box.x + box.width / 2,
        node.bounds.y + box.y + box.height / 2,
      );
    case AnnotationTargetKind.net:
      final route = layout.findEdge(note.targetId);
      if (route == null || route.points.isEmpty) return null;
      final points = route.points;
      if (points.length.isEven) {
        final a = points[points.length ~/ 2 - 1];
        final b = points[points.length ~/ 2];
        return Offset((a.x + b.x) / 2, (a.y + b.y) / 2);
      }
      final mid = points[points.length ~/ 2];
      return Offset(mid.x, mid.y);
    case AnnotationTargetKind.scope:
      return null;
  }
}

/// How much of a callout the schematic draws in [band]: the balloon at the
/// detail zoom where cell labels are legible, the numbered dot at middle zoom
/// where cells are bare symbols, and nothing in the overview, where cells are
/// coloured blocks and even a dot would be clutter.
CruxCalloutDetail calloutDetailFor(LodBand band) => switch (band) {
  LodBand.detail => CruxCalloutDetail.full,
  LodBand.mid => CruxCalloutDetail.dot,
  LodBand.overview => CruxCalloutDetail.hidden,
};

/// The short text a balloon shows: the note's heading, then its body's
/// remaining text with the Markdown marks dropped, on as many lines as the
/// balloon allows. The whole note is a hover or a panel row away.
String calloutExcerpt(String heading, String spokenDetails) =>
    spokenDetails.isEmpty ? heading : '$heading\n$spokenDetails';
