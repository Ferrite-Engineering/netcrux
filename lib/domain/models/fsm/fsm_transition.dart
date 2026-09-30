// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// A directed transition between two FSM states detected in the netlist.
///
/// Unlike WaveCrux's transition record (which counts how many times a
/// transition fires in a waveform trace), this model is purely
/// structural: it describes the *possibility* of a transition based on
/// the next-state combinational logic that drives the state register.
/// The optional [conditionExpression] carries a human-readable form of
/// the predicate that triggers the transition, recovered from
/// elaboration metadata when available.
@immutable
class FsmTransition {
  /// Creates a transition record.
  const FsmTransition({
    required this.fromStateId,
    required this.toStateId,
    this.conditionExpression,
    this.priorityRank,
  });

  /// JSON round-trip constructor.
  factory FsmTransition.fromJson(Map<String, Object?> json) => FsmTransition(
    fromStateId: json['fromStateId']?.toString() ?? '',
    toStateId: json['toStateId']?.toString() ?? '',
    conditionExpression: json['conditionExpression']?.toString(),
    priorityRank: json['priorityRank'] is int
        ? json['priorityRank']! as int
        : null,
  );

  /// Source state — the `FsmState.id` of the state the transition
  /// leaves.
  final String fromStateId;

  /// Destination state — the `FsmState.id` of the state the transition
  /// enters.
  final String toStateId;

  /// Human-readable predicate that triggers this transition, e.g.
  /// `"req && !busy"`. Null when the detector could not recover the
  /// expression (very common: the bubble diagram still renders the
  /// transition arrow with no label).
  final String? conditionExpression;

  /// When multiple transitions from the same state are mutually
  /// exclusive in source order (`if/else if/else` or case-priority),
  /// this is the priority rank (0 = highest). Null when the detector
  /// could not establish ordering — in that case the diagram shows
  /// transitions in arbitrary order.
  final int? priorityRank;

  /// True for a self-loop (state to itself). Detector emits these only
  /// when the next-state logic genuinely re-asserts the same state
  /// under some condition; sequential "stays the same when no event"
  /// behavior is the default and is not rendered as a self-loop unless
  /// the detector found an explicit condition.
  bool get isSelfLoop => fromStateId == toStateId;

  /// JSON map suitable for fixture round-trip.
  Map<String, Object?> toJson() => <String, Object?>{
    'fromStateId': fromStateId,
    'toStateId': toStateId,
    if (conditionExpression != null) 'conditionExpression': conditionExpression,
    if (priorityRank != null) 'priorityRank': priorityRank,
  };

  /// Returns a copy with the given fields replaced. Pass `clear*` flags
  /// to explicitly reset a field to null.
  FsmTransition copyWith({
    String? fromStateId,
    String? toStateId,
    String? conditionExpression,
    int? priorityRank,
    bool clearConditionExpression = false,
    bool clearPriorityRank = false,
  }) => FsmTransition(
    fromStateId: fromStateId ?? this.fromStateId,
    toStateId: toStateId ?? this.toStateId,
    conditionExpression: clearConditionExpression
        ? null
        : (conditionExpression ?? this.conditionExpression),
    priorityRank: clearPriorityRank
        ? null
        : (priorityRank ?? this.priorityRank),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FsmTransition &&
          runtimeType == other.runtimeType &&
          fromStateId == other.fromStateId &&
          toStateId == other.toStateId &&
          conditionExpression == other.conditionExpression &&
          priorityRank == other.priorityRank;

  @override
  int get hashCode => Object.hash(
    fromStateId,
    toStateId,
    conditionExpression,
    priorityRank,
  );

  @override
  String toString() =>
      'FsmTransition($fromStateId → $toStateId'
      '${conditionExpression != null ? ", cond: $conditionExpression" : ""}'
      '${priorityRank != null ? ", prio: $priorityRank" : ""})';
}
