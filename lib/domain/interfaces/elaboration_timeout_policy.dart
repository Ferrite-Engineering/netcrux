// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// A pre-elaboration size signal used to scale the Yosys timeout budget.
///
/// We do not know the elaborated cell count *before* running Yosys, so the
/// policy is driven by what is knowable up front: how many source files the
/// design has and their combined byte size. A 300-line testbench and a
/// 40-MB SoC top get very different budgets.
class ElaborationSizeEstimate {
  /// Creates a size estimate.
  const ElaborationSizeEstimate({
    required this.sourceFileCount,
    required this.totalSourceBytes,
  });

  /// A zero-size estimate (no source files / sizes unknown). The policy
  /// still returns its floor budget for this — never an unbounded wait.
  static const ElaborationSizeEstimate empty = ElaborationSizeEstimate(
    sourceFileCount: 0,
    totalSourceBytes: 0,
  );

  /// Number of source files in the elaboration request.
  final int sourceFileCount;

  /// Combined size, in bytes, of all source files in the request. `0`
  /// when the sizes could not be stat'd.
  final int totalSourceBytes;
}

/// Extension-point seam: how long a single
/// Yosys elaboration is allowed to run before the runner kills it.
///
/// The open-core default ([DefaultElaborationTimeoutPolicy] in
/// `services/yosys/elaboration_timeout_provider.dart`) is a size-aware
/// budget with a floor and a cap; it is sufficient on its own to close
/// the "hung Yosys blocks the elaboration future forever" gap with no Pro
/// override required. A Pro tier may override the provider to expose a
/// user-configurable per-design budget.
///
/// Zero Flutter imports by design — this is a pure domain seam.
abstract interface class ElaborationTimeoutPolicy {
  /// The wall-clock budget for an elaboration of the given [estimate].
  /// Implementations must always return a finite, positive duration — the
  /// whole point of the policy is that no elaboration runs unbounded.
  Duration timeoutFor(ElaborationSizeEstimate estimate);

  /// Whether a timed-out Yosys should be killed (`true`) or merely
  /// surfaced as a soft warning while the process keeps running. The
  /// open-core default is `true`; `false` exists only for diagnostics /
  /// tests where killing the subprocess is undesirable.
  bool get killOnTimeout;
}
