// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Non-web stand-in for the browser layout solver.
///
/// Selected by the conditional import in `elk_layout_service.dart` on
/// every non-web target. Desktop/VM builds solve on a background isolate
/// (see `_ElkLayoutIsolate`), so this backend reports itself unavailable and
/// its entry points must never be reached.
library;

/// Whether the browser solver is available on this target. `false` off-web;
/// the isolate path is used instead.
const bool kElkWebSolverAvailable = false;

/// Never true off-web: the browser solver has nothing in flight here.
bool get elkWebLayoutInFlight => false;

/// A no-op off-web: cancelling goes to the isolate there.
void cancelElkOnWeb() {}

/// Solve entry point. Unreachable off-web because [kElkWebSolverAvailable]
/// gates the call site; present only to satisfy the conditional-import
/// contract.
Future<String> solveElkOnWeb(
  String inputJson,
  Future<String> Function() loadSource, {
  Duration? timeout,
}) {
  throw UnsupportedError(
    'solveElkOnWeb is not available on this platform; the layout solve '
    'runs on a background isolate off-web. This entry point is gated by '
    'kElkWebSolverAvailable and should never be called here.',
  );
}
