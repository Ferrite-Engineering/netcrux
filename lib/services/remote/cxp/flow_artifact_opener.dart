// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The implementation-run artifact kinds a peer may ask NetCrux to open
/// (CXP §9.10.2): a run directory and one timing report of a run.
const String kCxpFlowRunArtifactKind = 'flow_run';

/// See [kCxpFlowRunArtifactKind].
const String kCxpTimingReportArtifactKind = 'timing_report';

/// Opens an implementation run or timing report a peer sent: the slack
/// overlay's input, a NetCrux Pro capability.
///
/// The request handler has already held the path to CXP §11.3 (the floor,
/// and the right kind of file system entry) before it calls [open]; the
/// opener reads only what it was handed. Open core resolves
/// [flowArtifactOpenerProvider] to null and answers such a request with the
/// "requires NetCrux Pro" message.
abstract interface class FlowArtifactOpener {
  /// The tier opening needs when the licence in force does not admit it, or
  /// null when it may open. Evaluated without a dialog: a peer started it.
  LicenseTier? deniedTier();

  /// Opens the [kind] artifact at [path] (a contained, existing run
  /// directory or report file). Returns a reason it could not, which never
  /// repeats [path], or null when it opened.
  Future<String?> open({required String kind, required String path});
}

/// The overlay's [FlowArtifactOpener]; null in open core.
final Provider<FlowArtifactOpener?> flowArtifactOpenerProvider =
    Provider<FlowArtifactOpener?>(
      (_) => null,
      name: 'flowArtifactOpenerProvider',
    );
