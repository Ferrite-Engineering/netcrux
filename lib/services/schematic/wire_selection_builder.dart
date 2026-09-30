// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:netcrux/domain/models/netlist/bit_ref.dart';
import 'package:netcrux/domain/models/netlist/net.dart';
import 'package:netcrux/domain/models/schematic/schematic_graph.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/domain/models/selection/selection.dart';

/// Builds a whole-net wire [Selection] for [net] against [graph], or
/// `null` when no bit of the net has a rendered edge.
///
/// A multi-bit bus is a vector of distinct Yosys net ids, and the
/// schematic graph draws one edge per net id that has both a driver and a
/// sink in the scope. Selecting the bus must accent EVERY drawn strand,
/// not just one, so this emits one [SelectedElement.wire] per bit that has
/// a laid-out edge. The painter keys its selection accent off each wire's
/// net id (see `_selectedWireNetIds` / `_paintEdges`), so N wire elements
/// light all N strands — a single faint strand was the whole-bus
/// visibility bug this fixes.
///
/// The primary — the element outbound cross-probe (`resolveCxpSelection`)
/// and the inspector read — is the FIRST bit with a drawn edge, the same
/// bit the legacy single-wire path selected and the one the CXP name
/// resolver reverse-resolves to the net's hierarchical name (e.g.
/// `cdc_capture.sample_a`). Keeping it stable preserves the identity fix.
///
/// A single-bit net (e.g. `req_b0`) yields a one-element selection
/// identical to the old behaviour: one drawn edge, one highlighted strand.
Selection? buildWholeNetWireSelection(Net net, SchematicGraph graph) {
  SelectedElement? primary;
  final elements = <SelectedElement>{};
  for (final bit in net.bits.whereType<NetBit>()) {
    final edge = graph.edges.where((e) => e.netId == bit.netId).firstOrNull;
    if (edge == null) continue;
    final wire = SelectedElement.wire(edgeId: edge.id, netId: bit.netId);
    primary ??= wire;
    elements.add(wire);
  }
  if (primary == null) return null;
  return Selection(elements: elements, primary: primary);
}
