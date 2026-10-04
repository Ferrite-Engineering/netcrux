// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart' show Color;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';

/// Severity-coded overlay drawn on top of the schematic to highlight
/// a single CDC or Reset-domain crossing.
///
/// The Pro overlay's CDC + Reset-domain features populate this provider
/// when the user picks a crossing in the analysis panel: the source-
/// side flop and the destination-side flop are the canonical "starts
/// here / ends there" anchors, and the intermediate synchronizer
/// chain (when present) names the cell instances the crossing path
/// traverses. The schematic painter consults the overlay and draws a
/// severity-colored outline around each named cell so the user can
/// see at a glance where the crossing lives in the design. The
/// crossing net's own wires ride along in [SchematicCrossingOverlay.netIds]
/// (every bit of a bus), so an unsynchronized crossing, which has no
/// synchronizer chain to outline, still paints the net that crosses.
///
/// Open-core resolves to `null` so the painter falls through to its
/// default rendering. The Pro overlay registers a controller (one for CDC,
/// one for reset domains) that mirrors
/// the analysis-state notifier's selected-crossing path into an
/// instance of [SchematicCrossingOverlay] and publishes it through
/// this provider. Clearing the panel selection clears the overlay.
///
/// Generalized across CDC + Reset because the overlay shape is
/// identical (source flop + dest flop + chain of intermediate
/// instances + severity colour) — splitting into per-feature
/// providers would duplicate the painter integration point without
/// adding signal. The provider returns `null` (not an empty record)
/// when no overlay is active so the painter can branch off the null
/// check rather than iterating empty sets every frame.
///
/// Declared as a manual `Provider<SchematicCrossingOverlay?>` so the
/// Pro overlay overrides with `.overrideWith` without a codegen dep.
@immutable
class SchematicCrossingOverlay {
  /// Creates a crossing overlay.
  const SchematicCrossingOverlay({
    required this.sourceCellIds,
    required this.destinationCellIds,
    required this.intermediateCellIds,
    required this.severityColor,
    this.netIds = const <int>{},
  });

  /// Empty sentinel — `isEmpty` returns true and the painter treats
  /// this identically to `null`. Useful for tests that want to assert
  /// "overlay is cleared" without dealing with nullable state.
  static const SchematicCrossingOverlay empty = SchematicCrossingOverlay(
    sourceCellIds: <String>{},
    destinationCellIds: <String>{},
    intermediateCellIds: <String>{},
    severityColor: Color(0x00000000),
  );

  /// Cell instance ids on the source side of the crossing (typically
  /// the source-domain register that drives the crossing net).
  final Set<String> sourceCellIds;

  /// Cell instance ids on the destination side of the crossing
  /// (typically the destination-domain sync flops or the destination
  /// register receiving the crossing net).
  final Set<String> destinationCellIds;

  /// Cell instance ids the synchronizer chain (or combinational
  /// path) traverses between source and destination. May be empty
  /// when the source net drives the destination flop directly.
  final Set<String> intermediateCellIds;

  /// Yosys net ids of the crossing net's wires, one per bit of a bus.
  /// The painter strokes every laid-out edge whose `EdgeRoute.netId` is
  /// in this set in [severityColor], the same net-id match a wire
  /// selection uses. Empty by default, which paints no wires.
  final Set<int> netIds;

  /// Severity-coded outline colour the painter uses. Sourced from
  /// the crossing's severity (`critical` → red, `warning` → amber,
  /// `info` → blue) — the Pro overlay applies the project's design-
  /// system colour tokens before publishing.
  final Color severityColor;

  /// True when all three cell id sets and [netIds] are empty.
  bool get isEmpty =>
      sourceCellIds.isEmpty &&
      destinationCellIds.isEmpty &&
      intermediateCellIds.isEmpty &&
      netIds.isEmpty;

  /// Returns `true` when [cellId] participates in the overlay (any
  /// of the three roles).
  bool involvesCell(String cellId) =>
      sourceCellIds.contains(cellId) ||
      destinationCellIds.contains(cellId) ||
      intermediateCellIds.contains(cellId);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! SchematicCrossingOverlay) return false;
    if (other.severityColor != severityColor) return false;
    if (other.sourceCellIds.length != sourceCellIds.length) return false;
    for (final id in sourceCellIds) {
      if (!other.sourceCellIds.contains(id)) return false;
    }
    if (other.destinationCellIds.length != destinationCellIds.length) {
      return false;
    }
    for (final id in destinationCellIds) {
      if (!other.destinationCellIds.contains(id)) return false;
    }
    if (other.intermediateCellIds.length != intermediateCellIds.length) {
      return false;
    }
    for (final id in intermediateCellIds) {
      if (!other.intermediateCellIds.contains(id)) return false;
    }
    if (other.netIds.length != netIds.length) return false;
    for (final id in netIds) {
      if (!other.netIds.contains(id)) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    severityColor,
    Object.hashAllUnordered(sourceCellIds),
    Object.hashAllUnordered(destinationCellIds),
    Object.hashAllUnordered(intermediateCellIds),
    Object.hashAllUnordered(netIds),
  );
}

/// Open-core extension point through which the Pro overlay's CDC +
/// Reset-domain features publish a single crossing overlay the
/// schematic painter applies on top of the regular rendering pass.
///
/// Open-core resolves to `null`. The Pro overlay overrides with a
/// notifier that derives the overlay from the active CDC / Reset
/// analysis state's selected crossing.
final schematicCrossingOverlayProvider = Provider<SchematicCrossingOverlay?>(
  (_) => null,
  name: 'schematicCrossingOverlayProvider',
);
