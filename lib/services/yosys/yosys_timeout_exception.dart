// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// Raised when a Yosys elaboration exceeded its time budget and the runner
/// killed the subprocess. Sibling to
/// `YosysJsonParseException`: a distinct typed failure so the elaboration
/// pipeline can surface a "timed out" diagnostic rather than a generic
/// non-zero-exit message.
@immutable
class YosysTimeoutException implements Exception {
  /// Creates a timeout exception for the elapsed [budget].
  const YosysTimeoutException(this.budget, {this.cause});

  /// The budget after which the runner killed the process.
  final Duration budget;

  /// Optional underlying cause (e.g. captured Yosys stderr) for the
  /// diagnostics drawer. `null` when there was nothing to capture.
  final Object? cause;

  /// Short, user-actionable English detail. Interpolated into the
  /// localized "Elaboration failed: {message}" envelope at the UI layer,
  /// matching the sibling [Exception] messages on the elaboration path.
  String get message =>
      'Yosys elaboration timed out after ${budget.inSeconds}s and was '
      'terminated. The design may be pathologically large or Yosys may be '
      'stuck; raise the timeout or simplify the top module.';

  @override
  String toString() => 'YosysTimeoutException: $message';
}
