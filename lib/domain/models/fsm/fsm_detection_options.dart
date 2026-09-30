// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:meta/meta.dart';
import 'package:netcrux/domain/models/fsm/fsm_encoding_hint.dart';

/// Tuning knobs passed to [FsmDetectionService.detect].
///
/// All knobs are optional; the defaults give a sensible behavior for
/// typical netlists (a few hundred to a few thousand registers).
@immutable
class FsmDetectionOptions {
  /// Creates an options bundle. All fields are optional.
  const FsmDetectionOptions({
    this.maxDepthHint,
    this.includeUnreachableStates = false,
    this.encodingHints = const <ElementId, FsmEncodingHint>{},
  });

  /// Canonical "use all defaults" instance.
  static const FsmDetectionOptions defaults = FsmDetectionOptions();

  /// Upper bound on the number of state-graph transitions the detector
  /// will explore before bailing. Guards against pathological designs
  /// that produce runaway analysis. Null means "use the service's
  /// internal default" (typically 1000).
  final int? maxDepthHint;

  /// When `true`, states that were detected but found to be
  /// unreachable from the reset state through observed transitions
  /// are still surfaced in the result. The bubble diagram renders
  /// them in a muted style so the user can audit dead code. When
  /// `false` (default), unreachable states are dropped from the
  /// returned [Fsm.states] but their count is still surfaced via
  /// detection diagnostics.
  final bool includeUnreachableStates;

  /// Optional per-register encoding hints. When non-empty, the
  /// detector trusts the caller-supplied hint over its own
  /// classification for the matching registers. Useful when the user
  /// knows the design's encoding convention better than the detector
  /// can infer (e.g. vendor-specific one-hot pragmas the detector
  /// doesn't recognise).
  final Map<ElementId, FsmEncodingHint> encodingHints;

  /// Returns a copy with the given fields replaced.
  FsmDetectionOptions copyWith({
    int? maxDepthHint,
    bool? includeUnreachableStates,
    Map<ElementId, FsmEncodingHint>? encodingHints,
    bool clearMaxDepthHint = false,
  }) => FsmDetectionOptions(
    maxDepthHint: clearMaxDepthHint
        ? null
        : (maxDepthHint ?? this.maxDepthHint),
    includeUnreachableStates:
        includeUnreachableStates ?? this.includeUnreachableStates,
    encodingHints: encodingHints ?? this.encodingHints,
  );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! FsmDetectionOptions) return false;
    if (maxDepthHint != other.maxDepthHint) return false;
    if (includeUnreachableStates != other.includeUnreachableStates) {
      return false;
    }
    if (encodingHints.length != other.encodingHints.length) return false;
    for (final entry in encodingHints.entries) {
      if (other.encodingHints[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode {
    var hash = Object.hash(maxDepthHint, includeUnreachableStates);
    for (final entry in encodingHints.entries) {
      hash ^= Object.hash(entry.key, entry.value);
    }
    return hash;
  }

  @override
  String toString() =>
      'FsmDetectionOptions('
      'maxDepth: ${maxDepthHint ?? "default"}, '
      'includeUnreachable: $includeUnreachableStates, '
      'hints: ${encodingHints.length})';
}
