// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart' show cxpMappingValues;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How a received timing path's registers were derived from the
/// implementation netlist (CXP `crux.mapping`), strongest first.
enum TimingPathFidelity {
  /// An exact register.
  register,

  /// The statement that drives it.
  statement,

  /// A source span only (an `always` or `process` block).
  span,

  /// No source location survived synthesis.
  unmapped;

  /// Reads a `crux.mapping` value. Anything that is not one of the four
  /// registered values, or no value at all, is [unmapped]: the weakest
  /// claim, so a mapping is never shown stronger than the sender said.
  static TimingPathFidelity parse(Object? value) {
    if (value is! String) return unmapped;
    final index = cxpMappingValues.indexOf(value);
    return index < 0 ? unmapped : TimingPathFidelity.values[index];
  }

  /// The telemetry token, the wire value itself.
  String get token => name;
}

/// Where one register of a received path landed in the open design.
enum TimingPathRegisterPlace {
  /// Highlighted in the scope on screen.
  shown,

  /// In the design, in a scope other than the one on screen.
  otherScope,

  /// Not in the open design.
  notFound,
}

/// One register of a received timing path.
@immutable
class TimingPathRegister {
  /// Creates a register row.
  const TimingPathRegister({required this.name, required this.place});

  /// The register's RTL name, as the peer sent it. Display only.
  final String name;

  /// Where it landed.
  final TimingPathRegisterPlace place;

  @override
  bool operator ==(Object other) =>
      other is TimingPathRegister && other.name == name && other.place == place;

  @override
  int get hashCode => Object.hash(name, place);
}

/// A timing path a peer sent in a `notify_selection`, as the Inspector's
/// read-only "Timing path from …" section shows it.
@immutable
class ReceivedTimingPath {
  /// Creates a received path.
  const ReceivedTimingPath({
    required this.peer,
    required this.fidelity,
    required this.registers,
    required this.statements,
  });

  /// The sending product's display name.
  final String peer;

  /// The mapping the sender stated; never upgraded.
  final TimingPathFidelity fidelity;

  /// The path's mapped registers, start first.
  final List<TimingPathRegister> registers;

  /// The path's statements, as `file:line` labels. Display only.
  final List<String> statements;

  /// Whether any register is in the open design.
  bool get resolved =>
      registers.any((r) => r.place != TimingPathRegisterPlace.notFound);

  @override
  bool operator ==(Object other) =>
      other is ReceivedTimingPath &&
      other.peer == peer &&
      other.fidelity == fidelity &&
      listEquals(other.registers, registers) &&
      listEquals(other.statements, statements);

  @override
  int get hashCode => Object.hash(
    peer,
    fidelity,
    Object.hashAll(registers),
    Object.hashAll(statements),
  );
}

/// The timing path this tab last received, or null. Written by the CXP
/// request handler when a path arrives, cleared by the section's Dismiss and
/// replaced by the next path.
///
/// Per-tab (re-bound in `netcruxTabOverridesFactory`): a path names
/// registers of the design in the tab it was shown in.
final NotifierProvider<ReceivedTimingPathNotifier, ReceivedTimingPath?>
receivedTimingPathProvider =
    NotifierProvider<ReceivedTimingPathNotifier, ReceivedTimingPath?>(
      ReceivedTimingPathNotifier.new,
      name: 'receivedTimingPathProvider',
    );

/// Notifier behind [receivedTimingPathProvider].
class ReceivedTimingPathNotifier extends Notifier<ReceivedTimingPath?> {
  @override
  ReceivedTimingPath? build() => null;

  /// Shows [path], replacing any path shown before.
  // ignore: use_setters_to_change_properties
  void show(ReceivedTimingPath path) => state = path;

  /// Dismisses the path.
  void dismiss() => state = null;
}
