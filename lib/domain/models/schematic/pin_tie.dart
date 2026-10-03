// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// What a cell pin is tied to, as far as the schematic can tell from one
/// scope.
enum PinTieKind {
  /// Every bit is on a net: a driven net for an input, any net for an
  /// output. The ordinary case, drawn as a pin with its wires.
  net,

  /// Every bit is a constant (`0`, `1`, `x` or `z`). Drawn with a short
  /// stub labelled with [PinTie.constantText].
  constant,

  /// An input with at least one bit on a net nothing in the scope drives:
  /// no cell output, inout or module input carries it. Drawn with a
  /// warning stub.
  undriven,

  /// The cell's module or primitive declares the port, but the netlist
  /// connects nothing to it: Yosys left it out of `connections`, or wrote
  /// it with no bits. Drawn as a bare pin.
  unconnected,
}

/// The tie of one `SchematicPort`, computed by `SchematicGraphBuilder`.
@immutable
class PinTie {
  /// A pin whose every bit is a constant, written as [text].
  const PinTie.constant(String text) : this._(PinTieKind.constant, text);

  const PinTie._(this.kind, [this.constantText]);

  /// A pin on nets.
  static const PinTie net = PinTie._(PinTieKind.net);

  /// An input on a net with no driver in the scope.
  static const PinTie undriven = PinTie._(PinTieKind.undriven);

  /// A declared port with nothing connected.
  static const PinTie unconnected = PinTie._(PinTieKind.unconnected);

  /// Which case this is.
  final PinTieKind kind;

  /// For [PinTieKind.constant], the constant as the canvas labels it: one
  /// character (`0`, `1`, `x` or `z`) when every bit has the same value,
  /// otherwise the bits most-significant first. `null` for every other
  /// kind.
  final String? constantText;

  /// Whether every bit is tied to `x`.
  bool get isX => kind == PinTieKind.constant && constantText == 'x';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PinTie &&
          other.kind == kind &&
          other.constantText == constantText);

  @override
  int get hashCode => Object.hash(kind, constantText);

  @override
  String toString() => constantText == null
      ? 'PinTie(${kind.name})'
      : 'PinTie(${kind.name} $constantText)';
}
