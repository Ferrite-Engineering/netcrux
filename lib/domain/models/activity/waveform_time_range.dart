// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// A user-selected (or analyzer-derived) time window over a loaded
/// waveform, expressed in nanoseconds.
///
/// Activity analysis runs over a [WaveformTimeRange]; the panel's
/// time-range picker exposes a small set of preset windows ("full
/// simulation", "first 10%", "last 10%", "middle 10%") plus an
/// explicit custom range.
///
/// The range is half-open: `[startNs, endNs)`. A transition at
/// exactly `endNs` is not counted; a transition at exactly `startNs`
/// is.
@immutable
class WaveformTimeRange {
  /// Creates a time range.
  const WaveformTimeRange({
    required this.startNs,
    required this.endNs,
    required this.label,
  }) : assert(endNs >= startNs, 'endNs must be >= startNs');

  /// JSON round-trip constructor.
  factory WaveformTimeRange.fromJson(Map<String, Object?> json) {
    return WaveformTimeRange(
      startNs: (json['startNs'] as num?)?.toInt() ?? 0,
      endNs: (json['endNs'] as num?)?.toInt() ?? 0,
      label: json['label']?.toString() ?? '',
    );
  }

  /// Returns the first-10-percent window of a source whose simulation
  /// ends at [sourceEndNs].
  factory WaveformTimeRange.firstPercent(
    int sourceEndNs, {
    int percent = 10,
    String label = 'first',
  }) {
    final width = (sourceEndNs * percent) ~/ 100;
    return WaveformTimeRange(startNs: 0, endNs: width, label: label);
  }

  /// Returns the last-10-percent window of a source whose simulation
  /// ends at [sourceEndNs].
  factory WaveformTimeRange.lastPercent(
    int sourceEndNs, {
    int percent = 10,
    String label = 'last',
  }) {
    final width = (sourceEndNs * percent) ~/ 100;
    return WaveformTimeRange(
      startNs: sourceEndNs - width,
      endNs: sourceEndNs,
      label: label,
    );
  }

  /// Returns the centered middle-10-percent window of a source whose
  /// simulation ends at [sourceEndNs].
  factory WaveformTimeRange.middlePercent(
    int sourceEndNs, {
    int percent = 10,
    String label = 'middle',
  }) {
    final width = (sourceEndNs * percent) ~/ 100;
    final midpoint = sourceEndNs ~/ 2;
    return WaveformTimeRange(
      startNs: midpoint - (width ~/ 2),
      endNs: midpoint + (width ~/ 2),
      label: label,
    );
  }

  /// Canonical "full simulation" sentinel — bounds 0..0 with an empty
  /// label. The activity analyzer reinterprets a zero-length range as
  /// "use the source's full duration".
  static const WaveformTimeRange fullSimulationSentinel = WaveformTimeRange(
    startNs: 0,
    endNs: 0,
    label: 'full',
  );

  /// Inclusive start of the window, in nanoseconds.
  final int startNs;

  /// Exclusive end of the window, in nanoseconds. Equal to [startNs]
  /// marks the "full simulation" sentinel — see
  /// [fullSimulationSentinel].
  final int endNs;

  /// Short user-facing label ("Full simulation", "First 10%", "User
  /// defined"). Carried through analysis so the panel footer can
  /// surface the human description that produced the result.
  final String label;

  /// Window width in nanoseconds (`endNs - startNs`). Returns 0 for
  /// the [fullSimulationSentinel] — callers expand it via
  /// [expandedAgainst].
  int get widthNs => endNs - startNs;

  /// True when this range is the "full simulation" sentinel that the
  /// analyzer must expand against the source's actual duration.
  bool get isFullSimulationSentinel => startNs == 0 && endNs == 0;

  /// Returns this range with `startNs == 0, endNs == 0` expanded
  /// against [sourceEndNs] so callers always have a concrete window
  /// to compute duty-cycle against. Non-sentinel ranges are returned
  /// unchanged.
  WaveformTimeRange expandedAgainst(int sourceEndNs, {String? fullLabel}) {
    if (!isFullSimulationSentinel) return this;
    return WaveformTimeRange(
      startNs: 0,
      endNs: sourceEndNs < 0 ? 0 : sourceEndNs,
      label: fullLabel ?? label,
    );
  }

  /// Returns a copy with the given fields replaced.
  WaveformTimeRange copyWith({int? startNs, int? endNs, String? label}) =>
      WaveformTimeRange(
        startNs: startNs ?? this.startNs,
        endNs: endNs ?? this.endNs,
        label: label ?? this.label,
      );

  /// JSON map suitable for fixture round-trip.
  Map<String, Object?> toJson() => <String, Object?>{
    'startNs': startNs,
    'endNs': endNs,
    'label': label,
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! WaveformTimeRange) return false;
    return startNs == other.startNs &&
        endNs == other.endNs &&
        label == other.label;
  }

  @override
  int get hashCode => Object.hash(startNs, endNs, label);

  @override
  String toString() => 'WaveformTimeRange($startNs..$endNs ns, label: $label)';
}
