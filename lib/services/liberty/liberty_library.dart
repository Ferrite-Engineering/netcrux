// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// The direction a cell port is declared with in its Verilog stub.
///
/// Liberty's `internal` pins have no port and never reach this type; a
/// `pg_pin` (power or ground) is always [inout], as is a pin whose
/// direction is missing or unrecognized, since `inout` accepts any
/// connection.
enum LibertyPortDirection {
  /// `direction : input`.
  input,

  /// `direction : output`.
  output,

  /// `direction : inout`, every `pg_pin`, and any pin without a usable
  /// direction.
  inout,
}

/// One port of a Liberty cell: a scalar `pin`, a `pg_pin`, or a `bus`
/// (a vector, when [msb] and [lsb] are set).
@immutable
class LibertyPort {
  /// Creates a port. [msb] and [lsb] are both set for a vector and both
  /// `null` for a scalar.
  const LibertyPort({
    required this.name,
    required this.direction,
    this.msb,
    this.lsb,
  }) : assert((msb == null) == (lsb == null), 'msb and lsb go together');

  /// Decodes a port written by [toJson].
  factory LibertyPort.fromJson(Map<String, Object?> json) => LibertyPort(
    name: json['name']! as String,
    direction: LibertyPortDirection.values.byName(json['dir']! as String),
    msb: json['msb'] as int?,
    lsb: json['lsb'] as int?,
  );

  /// The pin or bus name as the Liberty file spells it.
  final String name;

  /// The Verilog direction.
  final LibertyPortDirection direction;

  /// The left index of a vector's range, as declared (`[msb:lsb]`).
  final int? msb;

  /// The right index of a vector's range, as declared (`[msb:lsb]`).
  final int? lsb;

  /// Whether this port is a vector.
  bool get isVector => msb != null;

  /// The cache's JSON form.
  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'dir': direction.name,
    if (msb != null) 'msb': msb,
    if (lsb != null) 'lsb': lsb,
  };

  @override
  bool operator ==(Object other) =>
      other is LibertyPort &&
      other.name == name &&
      other.direction == direction &&
      other.msb == msb &&
      other.lsb == lsb;

  @override
  int get hashCode => Object.hash(name, direction, msb, lsb);

  @override
  String toString() =>
      'LibertyPort(${direction.name} '
      '${isVector ? '[$msb:$lsb] ' : ''}$name)';
}

/// One `cell` group: its name and its ports in declaration order.
@immutable
class LibertyCell {
  /// Creates a cell.
  LibertyCell({required this.name, required List<LibertyPort> ports})
    : ports = List<LibertyPort>.unmodifiable(ports);

  /// Decodes a cell written by [toJson].
  factory LibertyCell.fromJson(Map<String, Object?> json) => LibertyCell(
    name: json['name']! as String,
    ports: <LibertyPort>[
      for (final port in json['ports']! as List<Object?>)
        LibertyPort.fromJson(port! as Map<String, Object?>),
    ],
  );

  /// The cell name, which is the module name the RTL instantiates.
  final String name;

  /// The cell's ports, in the order the Liberty file declares them.
  final List<LibertyPort> ports;

  /// The cache's JSON form.
  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'ports': <Object?>[for (final port in ports) port.toJson()],
  };

  @override
  String toString() => 'LibertyCell($name, $ports)';
}

/// The cell interfaces read from one Liberty file.
@immutable
class LibertyLibrary {
  /// Creates a library read from [path].
  LibertyLibrary({
    required this.path,
    required List<LibertyCell> cells,
    List<String> warnings = const <String>[],
  }) : cells = List<LibertyCell>.unmodifiable(cells),
       warnings = List<String>.unmodifiable(warnings);

  /// Decodes a library written by [toJson].
  factory LibertyLibrary.fromJson(Map<String, Object?> json) => LibertyLibrary(
    path: json['path']! as String,
    cells: <LibertyCell>[
      for (final cell in json['cells']! as List<Object?>)
        LibertyCell.fromJson(cell! as Map<String, Object?>),
    ],
    warnings: <String>[
      for (final warning in json['warnings']! as List<Object?>)
        warning! as String,
    ],
  );

  /// The Liberty file the cells came from.
  final String path;

  /// Every cell in the file, in declaration order.
  final List<LibertyCell> cells;

  /// Things the reader noticed but read past, such as a cell declared
  /// twice in the same file.
  final List<String> warnings;

  /// The cache's JSON form.
  Map<String, Object?> toJson() => <String, Object?>{
    'path': path,
    'cells': <Object?>[for (final cell in cells) cell.toJson()],
    'warnings': warnings,
  };
}

/// Thrown when a Liberty file cannot be read as Liberty: a syntax error,
/// an unterminated group or string, or a file that cannot be opened.
@immutable
class LibertyParseException implements Exception {
  /// Creates an exception for [path], at [line] when there is one.
  const LibertyParseException(this.path, this.message, {this.line});

  /// The Liberty file that failed.
  final String path;

  /// What went wrong, in English.
  final String message;

  /// The 1-based line the problem was found on, when it has one.
  final int? line;

  /// `path, line N: message`, the form shown to the user.
  String get description =>
      line == null ? '$path: $message' : '$path, line $line: $message';

  @override
  String toString() => 'LibertyParseException: $description';
}
