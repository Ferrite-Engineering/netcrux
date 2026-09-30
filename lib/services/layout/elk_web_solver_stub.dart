// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Non-web fallback for the browser elkjs solver.
///
/// Selected by the conditional import in `elk_layout_service.dart` on
/// every non-web target. Desktop/VM builds run the elkjs solve on a
/// flutter_js-backed background isolate (see `_ElkLayoutIsolate`), so
/// this backend reports itself unavailable and its solve entry point
/// must never be reached.
library;

/// Whether the browser-native elkjs solver is available on this target.
/// `false` off-web — the isolate/flutter_js path is used instead.
const bool kElkWebSolverAvailable = false;

/// Solve entry point. Unreachable off-web because [kElkWebSolverAvailable]
/// gates the call site; present only to satisfy the conditional-import
/// contract.
Future<String> solveElkOnWeb(
  String inputJson,
  Future<String> Function() loadSource,
) {
  throw UnsupportedError(
    'solveElkOnWeb is not available on this platform — the elkjs solve '
    'runs on a background isolate off-web. This entry point is gated by '
    'kElkWebSolverAvailable and should never be called here.',
  );
}
