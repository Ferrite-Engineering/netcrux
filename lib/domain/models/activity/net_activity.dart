// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// Per-net switching-activity result row.
///
/// One [NetActivity] is emitted per analyzed net (or per net-bit, for
/// multi-bit vectors that the analyzer chooses to break out). The
/// panel sorts by [activityScore] descending to find "hot" nets and
/// ascending to find "cold" ones.
///
/// The [netPath] is the canonical hierarchical name the analyzer
/// resolved through the loaded netlist (e.g. `top.cpu.alu.sum`). It
/// matches the [SchematicEdge.netId]'s name attribute after
/// Yosys-name resolution.
@immutable
class NetActivity {
  /// Creates a per-net activity record.
  const NetActivity({
    required this.netPath,
    required this.transitionCount,
    required this.dutyCyclePercent,
    required this.activityScore,
    this.netBitWidth = 1,
    this.isClock = false,
  }) : assert(transitionCount >= 0, 'transitionCount must be >= 0'),
       assert(
         dutyCyclePercent >= 0 && dutyCyclePercent <= 100,
         'dutyCyclePercent must be in [0, 100]',
       ),
       assert(
         activityScore >= 0 && activityScore <= 1,
         'activityScore must be in [0.0, 1.0]',
       );

  /// JSON round-trip constructor.
  factory NetActivity.fromJson(Map<String, Object?> json) {
    return NetActivity(
      netPath: json['netPath']?.toString() ?? '',
      transitionCount: (json['transitionCount'] as num?)?.toInt() ?? 0,
      dutyCyclePercent: (json['dutyCyclePercent'] as num?)?.toDouble() ?? 0.0,
      activityScore: (json['activityScore'] as num?)?.toDouble() ?? 0.0,
      netBitWidth: (json['netBitWidth'] as num?)?.toInt() ?? 1,
      isClock: json['isClock'] == true,
    );
  }

  /// Canonical hierarchical net path (the analyzer's resolved name in
  /// the loaded netlist).
  final String netPath;

  /// Number of value transitions observed inside the analysis time
  /// range. Includes 0→1, 1→0, X→{0,1}, {0,1}→X (every change).
  final int transitionCount;

  /// Fraction of the analysis time range the net was at logical-high
  /// (`1`), expressed as a percentage in `[0, 100]`. For multi-bit
  /// nets the analyzer reports the average per-bit duty cycle.
  final double dutyCyclePercent;

  /// Normalized activity score in `[0.0, 1.0]`. 0.0 = idle / 1.0 =
  /// hottest observed in this analysis result. The exact
  /// normalization is determined by [ActivityNormalization] passed
  /// to the analyzer.
  final double activityScore;

  /// Width of the underlying net in bits. 1 for scalar nets; > 1 for
  /// vectors the analyzer chose to summarize as a single row rather
  /// than break out per-bit.
  final int netBitWidth;

  /// True when the analyzer identified this net as a clock (it feeds the
  /// clock pin of a register). A clock is scored apart: it is left out of
  /// the range the other nets are normalized against, so it cannot push
  /// them all to the cold end, and it paints in
  /// `ActivityColorScheme.clockColor` rather than on the scheme's ramp.
  /// Its [activityScore] is 1.0.
  final bool isClock;

  /// Returns a copy with the given fields replaced.
  NetActivity copyWith({
    String? netPath,
    int? transitionCount,
    double? dutyCyclePercent,
    double? activityScore,
    int? netBitWidth,
    bool? isClock,
  }) => NetActivity(
    netPath: netPath ?? this.netPath,
    transitionCount: transitionCount ?? this.transitionCount,
    dutyCyclePercent: dutyCyclePercent ?? this.dutyCyclePercent,
    activityScore: activityScore ?? this.activityScore,
    netBitWidth: netBitWidth ?? this.netBitWidth,
    isClock: isClock ?? this.isClock,
  );

  /// JSON map suitable for fixture round-trip.
  Map<String, Object?> toJson() => <String, Object?>{
    'netPath': netPath,
    'transitionCount': transitionCount,
    'dutyCyclePercent': dutyCyclePercent,
    'activityScore': activityScore,
    'netBitWidth': netBitWidth,
    if (isClock) 'isClock': true,
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! NetActivity) return false;
    return netPath == other.netPath &&
        transitionCount == other.transitionCount &&
        dutyCyclePercent == other.dutyCyclePercent &&
        activityScore == other.activityScore &&
        netBitWidth == other.netBitWidth &&
        isClock == other.isClock;
  }

  @override
  int get hashCode => Object.hash(
    netPath,
    transitionCount,
    dutyCyclePercent,
    activityScore,
    netBitWidth,
    isClock,
  );

  @override
  String toString() =>
      'NetActivity('
      'net: $netPath, '
      'transitions: $transitionCount, '
      'duty: ${dutyCyclePercent.toStringAsFixed(1)}%, '
      'score: ${activityScore.toStringAsFixed(3)}'
      '${isClock ? ', clock' : ''})';
}
