// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:netcrux/domain/models/diff/netlist_diff.dart';
import 'package:netcrux/domain/models/diff/netlist_diff_request.dart';

/// Extension-point service powering the Diff View.
///
/// Compares two netlists end-to-end and emits a structured
/// [NetlistDiff] that consumers (panel widget, schematic overlay,
/// navigation actions, "Copy report") read uniformly. The engine
/// itself is responsible for loading both netlists from the
/// [NetlistDiffRequest]'s [NetlistRef] identifiers — open-core sees
/// only the result.
///
/// **Open-core ships [NoopNetlistDiffService]** as the registered
/// default. It returns the empty [NetlistDiff] for any request and
/// never emits on [diffsInvalidated]. The Pro overlay registers a
/// `ProNetlistDiffService` via `proOverrides` that consumes the same
/// elaboration pipeline `loadedNetlistProvider` uses to produce
/// real [NetlistModel]s for both sides and walks them in lockstep.
abstract interface class NetlistDiffService {
  /// Compares the two netlists in [request] and returns the
  /// structured diff. The future resolves when both sides are
  /// elaborated and walked; large designs (10k+ elements) should
  /// complete in under 2 s on a development workstation.
  ///
  /// Throws [UnsupportedError] when the requested
  /// [NetlistDiffMatchStrategy] is not implemented by this service.
  /// V1 services support only
  /// [NetlistDiffMatchStrategy.exactNameMatch].
  Future<NetlistDiff> compare(NetlistDiffRequest request);

  /// Stream that emits when the underlying inputs to the most recent
  /// comparison change — typically because the baseline or comparison
  /// netlist was re-elaborated. The per-tab `activeDiffProvider`
  /// listens to this stream and re-runs the comparison so the panel
  /// content stays in sync with the live design.
  ///
  /// Open-core's no-op default never emits.
  Stream<void> get diffsInvalidated;
}

/// Open-core default: returns an empty diff for every request and
/// never emits on [diffsInvalidated].
///
/// The open-core build registers this implementation and mounts nothing
/// over it: [DiffPane] is mounted only by the Pro overlay. The
/// `loadComparisonNetlist` / `navigateNextDiff` / etc. actions stay
/// discoverable in the menu bar / palette, and an open-core build refuses
/// them with a "requires NetCrux Pro" notice (the Pro overlay's opener
/// provider is what mounts the file picker and the panel chrome — see the
/// Pro overlay's `diff_pane_panel.dart`).
class NoopNetlistDiffService implements NetlistDiffService {
  /// Creates the no-op service.
  const NoopNetlistDiffService();

  @override
  Future<NetlistDiff> compare(NetlistDiffRequest request) async {
    return NetlistDiff.empty();
  }

  @override
  Stream<void> get diffsInvalidated => const Stream<void>.empty();
}
