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

/// Which storage group a sequential cell declares.
enum LibertyStorageKind {
  /// An `ff` group: edge-triggered.
  flipFlop,

  /// A `latch` group: level-sensitive.
  latch,
}

/// The `ff` or `latch` group of a sequential cell: the names of its state
/// variables and the expressions that drive them, as the file writes them.
@immutable
class LibertyStorage {
  /// Creates a storage description.
  LibertyStorage({
    required this.kind,
    required List<String> stateNames,
    this.clockedOn,
    this.nextState,
    this.enable,
    this.dataIn,
    this.clear,
    this.preset,
  }) : stateNames = List<String>.unmodifiable(stateNames);

  /// Decodes a description written by [toJson].
  factory LibertyStorage.fromJson(Map<String, Object?> json) => LibertyStorage(
    kind: LibertyStorageKind.values.byName(json['kind']! as String),
    stateNames: <String>[
      for (final name in json['state']! as List<Object?>) name! as String,
    ],
    clockedOn: json['clocked_on'] as String?,
    nextState: json['next_state'] as String?,
    enable: json['enable'] as String?,
    dataIn: json['data_in'] as String?,
    clear: json['clear'] as String?,
    preset: json['preset'] as String?,
  );

  /// Whether this is a flip-flop or a latch.
  final LibertyStorageKind kind;

  /// The group's arguments: the state variable and its complement
  /// (`ff (IQ, IQN)`), which output pin functions refer to.
  final List<String> stateNames;

  /// A flip-flop's `clocked_on` expression.
  final String? clockedOn;

  /// A flip-flop's `next_state` expression.
  final String? nextState;

  /// A latch's `enable` expression.
  final String? enable;

  /// A latch's `data_in` expression.
  final String? dataIn;

  /// The `clear` expression, when the cell has one.
  final String? clear;

  /// The `preset` expression, when the cell has one.
  final String? preset;

  /// The cache's JSON form.
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind.name,
    'state': stateNames,
    if (clockedOn != null) 'clocked_on': clockedOn,
    if (nextState != null) 'next_state': nextState,
    if (enable != null) 'enable': enable,
    if (dataIn != null) 'data_in': dataIn,
    if (clear != null) 'clear': clear,
    if (preset != null) 'preset': preset,
  };
}

/// One `cell` group: its name and its ports in declaration order, and the
/// parts of its data sheet a schematic shows: the function of each output
/// pin, which pins are clocks and which are tri-state, the type of each
/// power and ground pin, its storage group and its area.
@immutable
class LibertyCell {
  /// Creates a cell.
  LibertyCell({
    required this.name,
    required List<LibertyPort> ports,
    this.area,
    Map<String, String> functions = const <String, String>{},
    List<String> clockPins = const <String>[],
    List<String> threeStatePins = const <String>[],
    Map<String, String?> pgPins = const <String, String?>{},
    this.storage,
    this.hasOtherStorage = false,
  }) : ports = List<LibertyPort>.unmodifiable(ports),
       functions = Map<String, String>.unmodifiable(functions),
       clockPins = List<String>.unmodifiable(clockPins),
       threeStatePins = List<String>.unmodifiable(threeStatePins),
       pgPins = Map<String, String?>.unmodifiable(pgPins);

  /// Decodes a cell written by [toJson].
  factory LibertyCell.fromJson(Map<String, Object?> json) {
    final storage = json['storage'];
    return LibertyCell(
      name: json['name']! as String,
      ports: <LibertyPort>[
        for (final port in json['ports']! as List<Object?>)
          LibertyPort.fromJson(port! as Map<String, Object?>),
      ],
      area: (json['area'] as num?)?.toDouble(),
      functions: <String, String>{
        for (final entry
            in ((json['functions'] as Map<String, Object?>?) ??
                    const <String, Object?>{})
                .entries)
          entry.key: entry.value! as String,
      },
      clockPins: <String>[
        for (final pin
            in (json['clocks'] as List<Object?>?) ?? const <Object?>[])
          pin! as String,
      ],
      threeStatePins: <String>[
        for (final pin
            in (json['three_state'] as List<Object?>?) ?? const <Object?>[])
          pin! as String,
      ],
      pgPins: <String, String?>{
        for (final entry
            in ((json['pg'] as Map<String, Object?>?) ??
                    const <String, Object?>{})
                .entries)
          entry.key: entry.value as String?,
      },
      storage: storage == null
          ? null
          : LibertyStorage.fromJson(storage as Map<String, Object?>),
      hasOtherStorage: json['other_storage'] == true,
    );
  }

  /// The cell name, which is the module name the RTL instantiates.
  final String name;

  /// The cell's ports, in the order the Liberty file declares them.
  final List<LibertyPort> ports;

  /// The `area` attribute, in the library's units (square micrometres in
  /// every common library), or `null` when the cell has none.
  final double? area;

  /// The `function` of each pin that has one, by pin name, as written.
  final Map<String, String> functions;

  /// The pins marked `clock : true`, in declaration order.
  final List<String> clockPins;

  /// The pins with a `three_state` attribute, which can drive high
  /// impedance, in declaration order.
  final List<String> threeStatePins;

  /// Every `pg_pin` by name, with its `pg_type` (`primary_power`,
  /// `primary_ground`, `nwell`, ...) or `null` when it declares none.
  final Map<String, String?> pgPins;

  /// The cell's single `ff` or `latch` group, or `null`.
  final LibertyStorage? storage;

  /// Whether the cell describes its state some other way: more than one
  /// storage group, an `ff_bank` or `latch_bank`, or a `statetable`.
  final bool hasOtherStorage;

  /// The cache's JSON form.
  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'ports': <Object?>[for (final port in ports) port.toJson()],
    if (area != null) 'area': area,
    if (functions.isNotEmpty) 'functions': functions,
    if (clockPins.isNotEmpty) 'clocks': clockPins,
    if (threeStatePins.isNotEmpty) 'three_state': threeStatePins,
    if (pgPins.isNotEmpty) 'pg': pgPins,
    if (storage != null) 'storage': storage!.toJson(),
    if (hasOtherStorage) 'other_storage': true,
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
    this.name,
    List<String> warnings = const <String>[],
  }) : cells = List<LibertyCell>.unmodifiable(cells),
       warnings = List<String>.unmodifiable(warnings);

  /// Decodes a library written by [toJson].
  factory LibertyLibrary.fromJson(Map<String, Object?> json) => LibertyLibrary(
    path: json['path']! as String,
    name: json['name'] as String?,
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

  /// The name the `library (...)` group gives, which for a characterised
  /// library usually names its corner (`..._tt_025C_1v80`); `null` when the
  /// group has none.
  final String? name;

  /// Every cell in the file, in declaration order.
  final List<LibertyCell> cells;

  /// Things the reader noticed but read past, such as a cell declared
  /// twice in the same file.
  final List<String> warnings;

  /// The cache's JSON form.
  Map<String, Object?> toJson() => <String, Object?>{
    'path': path,
    if (name != null) 'name': name,
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
