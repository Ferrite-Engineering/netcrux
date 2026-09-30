// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// A single state in a detected finite state machine.
///
/// Distinct from WaveCrux's `FsmState` (which describes a state
/// observed in a waveform trace) — this models a state recovered from
/// **netlist analysis**: a constant value the FSM's state register
/// takes, together with the logic-graph properties the detector
/// inferred (reachability from reset, terminality).
///
/// State naming priority:
///   1. Source-attributed name from elaboration metadata (enum
///      members, parameter assignments). Surfaces as `"IDLE"` / `"RUN"`.
///   2. Generated fallback `"S<i>"` where `i` is the discovery index.
///
/// State values are kept as hex strings to avoid lossy `int` conversion
/// for wide state registers and to keep them JSON-natural for fixture
/// round-trip.
@immutable
class FsmState {
  /// Creates an FSM state.
  const FsmState({
    required this.id,
    required this.name,
    required this.value,
    required this.isReachable,
    required this.isTerminal,
  });

  /// JSON round-trip constructor.
  factory FsmState.fromJson(Map<String, Object?> json) => FsmState(
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    value: json['value']?.toString() ?? '0x0',
    isReachable: json['isReachable'] as bool? ?? true,
    isTerminal: json['isTerminal'] as bool? ?? false,
  );

  /// Stable identifier within the FSM scope (typically `"s0"`, `"s1"`,
  /// …). Used as the from/to handle on [FsmTransition]s; not the same
  /// as the register's runtime value, which is stored in [value].
  final String id;

  /// Human-readable name. Falls back to `"S<i>"` when no source
  /// attribution is available.
  final String name;

  /// Hex-encoded state value the register takes when the FSM is in
  /// this state. Format: `"0xNN"` (lower-case hex, two or more digits).
  /// Wide enough to round-trip the originating register's width
  /// without loss.
  final String value;

  /// True when this state is reachable from the FSM's reset state by
  /// following transitions. Detector treats unknown reachability as
  /// `true` (defensive — surfaces a candidate state to the user rather
  /// than hiding it).
  final bool isReachable;

  /// True when no outgoing transitions were detected from this state.
  /// Often indicates a deadlock state, an error trap, or a state the
  /// detector could not fully analyse.
  final bool isTerminal;

  /// JSON map suitable for fixture round-trip.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'value': value,
    'isReachable': isReachable,
    'isTerminal': isTerminal,
  };

  /// Returns a copy with the given fields replaced.
  FsmState copyWith({
    String? id,
    String? name,
    String? value,
    bool? isReachable,
    bool? isTerminal,
  }) => FsmState(
    id: id ?? this.id,
    name: name ?? this.name,
    value: value ?? this.value,
    isReachable: isReachable ?? this.isReachable,
    isTerminal: isTerminal ?? this.isTerminal,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FsmState &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          value == other.value &&
          isReachable == other.isReachable &&
          isTerminal == other.isTerminal;

  @override
  int get hashCode => Object.hash(id, name, value, isReachable, isTerminal);

  @override
  String toString() =>
      'FsmState(id: $id, name: $name, value: $value, '
      'reachable: $isReachable, terminal: $isTerminal)';
}
