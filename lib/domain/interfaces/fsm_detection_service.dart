// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:netcrux/domain/models/fsm/fsm.dart';
import 'package:netcrux/domain/models/fsm/fsm_detection_options.dart';
import 'package:netcrux/domain/models/fsm/fsm_detection_result.dart';

/// Thrown by [FsmDetectionService.detectAt] when the service cannot
/// detect an FSM for the targeted register (e.g. open-core's no-op
/// implementation or an empty/missing project).
class UnimplementedFsmDetection implements Exception {
  /// Creates the exception with an optional [message] describing why
  /// detection could not run.
  const UnimplementedFsmDetection([this.message]);

  /// Human-readable reason. Surfaced by the Pro overlay's snackbar
  /// when an attempted forced detection bounces off the no-op.
  final String? message;

  @override
  String toString() =>
      'UnimplementedFsmDetection${message != null ? ": $message" : ""}';
}

/// Extension-point service powering the FSM bubble diagram.
///
/// Walks the elaborated netlist to find finite state machines —
/// registers whose value enumerates the FSM's states, together with
/// the combinational logic that drives next-state transitions — and
/// emits a structured [FsmDetectionResult].
///
/// **Open-core ships [NoopFsmDetectionService]** as the registered
/// default: `detect` returns the empty result and `detectAt` throws
/// [UnimplementedFsmDetection]. The Pro overlay registers a concrete
/// `ProFsmDetectionService` via `proOverrides` that consumes the same
/// elaborated netlist `loadedNetlistProvider` produces and runs the
/// v1 detection engine.
abstract interface class FsmDetectionService {
  /// Walks the netlist and returns every FSM it can detect.
  ///
  /// [scopeFilter] is an optional canonical hierarchical-path prefix
  /// that restricts the walk to a sub-tree of the design (e.g.
  /// `"top.cpu"`). Null walks the entire design.
  ///
  /// [options] tunes detection knobs; pass [FsmDetectionOptions.defaults]
  /// (or omit) for the default behavior.
  ///
  /// Large designs (1k+ registers) should complete in under 3 s on a
  /// development workstation. Open-core's no-op resolves immediately.
  Future<FsmDetectionResult> detect({
    ElementId? scopeFilter,
    FsmDetectionOptions? options,
  });

  /// Forces detection for a specific register, skipping the structural-
  /// signature filter `detect` applies. Used by the schematic context
  /// menu's "Detect FSM for This Register" entry — the user is
  /// asserting "this is an FSM register, try harder".
  ///
  /// [stateRegisterId] takes the same `<moduleName>.<cellName>` path form
  /// as [Fsm.stateRegisterId], so a caller holding a schematic cell id
  /// qualifies it with the viewed scope's module name first.
  ///
  /// Returns the detected [Fsm], or null when the targeted register
  /// has no parseable driving logic. Open-core's no-op throws
  /// [UnimplementedFsmDetection].
  Future<Fsm?> detectAt(ElementId stateRegisterId);

  /// Stream that emits when the underlying inputs to the most recent
  /// detection change — typically because the loaded netlist was
  /// re-elaborated. The per-tab `perTabFsmDetectionResultProvider`
  /// listens to this stream and re-runs detection so the panel
  /// content stays in sync with the live design.
  ///
  /// Open-core's no-op default never emits.
  Stream<void> get detectionInvalidated;
}

/// Open-core default: returns an empty detection result for every
/// request, throws [UnimplementedFsmDetection] on `detectAt`, and
/// never emits on [detectionInvalidated].
///
/// The open-core build registers this implementation and mounts nothing
/// over it: [FsmBubbleDiagramPane] is mounted only by the Pro overlay. The
/// `showFsmBubbleDiagram` / `detectFsmForCurrentRegister` /
/// `runFsmDetectionAcrossDesign` actions stay discoverable in the menu bar /
/// palette, and an open-core build refuses them with a "requires NetCrux
/// Pro" notice before any service call.
class NoopFsmDetectionService implements FsmDetectionService {
  /// Creates the no-op service.
  const NoopFsmDetectionService();

  @override
  Future<FsmDetectionResult> detect({
    ElementId? scopeFilter,
    FsmDetectionOptions? options,
  }) async {
    return FsmDetectionResult.empty;
  }

  @override
  Future<Fsm?> detectAt(ElementId stateRegisterId) async {
    throw const UnimplementedFsmDetection(
      'FSM detection is unavailable in the open-core build. '
      'Install the Pro overlay to enable structural FSM detection.',
    );
  }

  @override
  Stream<void> get detectionInvalidated => const Stream<void>.empty();
}
