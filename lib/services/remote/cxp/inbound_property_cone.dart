// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/schematic/laid_out_graph.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/domain/models/trace/trace_overlay.dart';

/// The Pro side of a property a peer sent (CXP `property`, Formal's
/// "property cone"): the cone of every signal the property reads, unioned.
///
/// Open core finds the property and the signals it reads, which is free;
/// the multi-step cone is NetCrux Pro's `coi` capability, so the gate and
/// the cone live in the overlay. Open core resolves
/// [inboundPropertyConeProvider] to null, and a property that arrives in a
/// build without the overlay is answered as `allowProAction` answers a Pro
/// action there: the "requires NetCrux Pro" message.
abstract interface class InboundPropertyCone {
  /// The tier the cone needs when the licence in force does not admit it,
  /// or null when it may run. Evaluated without a dialog: nobody in this
  /// window asked for the cone, so a denial is a toast that names the tier,
  /// never the upgrade dialog.
  LicenseTier? deniedTier();

  /// The fanin cone of every element of [seeds], traced to the natural
  /// boundary in [laidOut] and unioned into one overlay. Never throws.
  Future<TraceOverlay> unionCone(
    LaidOutGraph laidOut,
    List<SelectedElement> seeds,
  );

  /// The nets of the scope at [scopePath] (instance names below the top)
  /// that are the same electrical net as the hierarchical [names] the
  /// property reads from inside that scope (`u_sub.state`), by name. A name
  /// that reaches no net of the scope is left out: it is named, not traced.
  List<String> sameNetsInScope({
    required NetlistModel model,
    required List<String> scopePath,
    required List<String> names,
  });
}

/// The overlay's [InboundPropertyCone]; null in open core.
final Provider<InboundPropertyCone?> inboundPropertyConeProvider =
    Provider<InboundPropertyCone?>(
      (_) => null,
      name: 'inboundPropertyConeProvider',
    );
