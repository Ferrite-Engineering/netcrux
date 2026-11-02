// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:netcrux/domain/models/schematic/cell_kind.dart';

/// How a cell-library cell is drawn, read from its Liberty description: the
/// gate symbol its function maps to, the pins that get a clock wedge, and
/// the power and ground pins, which sit on the top and bottom faces.
///
/// A scope where no instance connects any supply pin (a netlist before place
/// and route) draws none of the unconnected ones; a scope where one does
/// draws them all (`withoutUnconnectedSupplyPins`).
@immutable
class LibertyCellSymbol {
  /// Creates a description.
  const LibertyCellSymbol({
    required this.kind,
    this.clockPins = const <String>{},
    this.powerPins = const <String>{},
    this.groundPins = const <String>{},
    this.otherSupplyPins = const <String>{},
  });

  /// The symbol: a gate, a flip-flop or a latch, or [CellKind.generic] for
  /// a cell that keeps its box.
  final CellKind kind;

  /// The pins drawn with a clock wedge.
  final Set<String> clockPins;

  /// The power pins, drawn on the top face.
  final Set<String> powerPins;

  /// The ground pins, drawn on the bottom face.
  final Set<String> groundPins;

  /// The `pg_pin`s that are neither power nor ground as far as can be told,
  /// drawn where their direction puts them.
  final Set<String> otherSupplyPins;

  /// Whether the cell has a power or ground pin to place.
  bool get hasSupplyPins => powerPins.isNotEmpty || groundPins.isNotEmpty;

  /// Whether [pin] is one of the cell's `pg_pin`s, of any type.
  bool isSupplyPin(String pin) =>
      powerPins.contains(pin) ||
      groundPins.contains(pin) ||
      otherSupplyPins.contains(pin);

  /// The ELK face of [pin] when it is a supply pin (`NORTH` for power,
  /// `SOUTH` for ground), or `null` for any other pin.
  String? supplyFace(String pin) {
    if (powerPins.contains(pin)) return 'NORTH';
    if (groundPins.contains(pin)) return 'SOUTH';
    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LibertyCellSymbol &&
          other.kind == kind &&
          _setEquals(other.clockPins, clockPins) &&
          _setEquals(other.powerPins, powerPins) &&
          _setEquals(other.groundPins, groundPins) &&
          _setEquals(other.otherSupplyPins, otherSupplyPins));

  @override
  int get hashCode => Object.hash(
    kind,
    Object.hashAllUnordered(clockPins),
    Object.hashAllUnordered(powerPins),
    Object.hashAllUnordered(groundPins),
    Object.hashAllUnordered(otherSupplyPins),
  );

  @override
  String toString() => 'LibertyCellSymbol(${kind.name})';
}

/// The [LibertyCellSymbol] of every cell type a design draws from its cell
/// libraries, keyed by cell type. Value-equal, so a provider holding it only
/// notifies when a drawing actually changes. A type a source module defines
/// is not here: the module's definition wins, as it does for elaboration.
@immutable
class LibertyCellSymbols {
  /// Wraps [byType].
  const LibertyCellSymbols(this.byType);

  /// No cell-library cells: every cell is drawn as before.
  static const LibertyCellSymbols none = LibertyCellSymbols(
    <String, LibertyCellSymbol>{},
  );

  /// Cell type to drawing.
  final Map<String, LibertyCellSymbol> byType;

  /// Whether there is nothing to draw differently.
  bool get isEmpty => byType.isEmpty;

  /// The drawing of cells of [type], or `null`.
  LibertyCellSymbol? operator [](String type) => byType[type];

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! LibertyCellSymbols) return false;
    if (other.byType.length != byType.length) return false;
    for (final entry in byType.entries) {
      if (other.byType[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAllUnordered(
    byType.entries.map((e) => Object.hash(e.key, e.value)),
  );
}

bool _setEquals(Set<String> a, Set<String> b) =>
    a.length == b.length && a.containsAll(b);
