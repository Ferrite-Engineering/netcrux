// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/services/liberty/liberty_library.dart';

/// One port of a cell whose interface is known without its body: a Liberty
/// pin, or a port declared in the header of a Verilog cell model.
@immutable
class CellPort {
  /// Creates a port. [msb] and [lsb] are both set for a vector whose range
  /// is known, and both `null` for a scalar or a vector of unknown range.
  const CellPort({
    required this.name,
    required this.direction,
    this.msb,
    this.lsb,
    this.rangeUnknown = false,
  });

  /// The port name as the definition spells it.
  final String name;

  /// The declared direction.
  final PortDirection direction;

  /// The left bound of the range as written (`[msb:lsb]`), or `null`.
  final int? msb;

  /// The right bound of the range as written, or `null`.
  final int? lsb;

  /// Whether the port is a vector whose range the reader could not evaluate
  /// (it names a parameter, say). Its width is not known.
  final bool rangeUnknown;

  /// The number of bits, or `null` when the range is unknown.
  int? get width {
    if (rangeUnknown) return null;
    final left = msb;
    final right = lsb;
    if (left == null || right == null) return 1;
    return (left - right).abs() + 1;
  }
}

/// The interface of one cell type: its name and its ports in declaration
/// order, which is the order a positional instance connects them.
@immutable
class CellInterface {
  /// Creates an interface.
  CellInterface({required this.name, required List<CellPort> ports})
    : ports = List<CellPort>.unmodifiable(ports);

  /// The cell (module) name.
  final String name;

  /// The ports, in declaration order.
  final List<CellPort> ports;
}

/// Cell interfaces by name, with the first definition of a name winning.
///
/// Built from the Liberty libraries of a project, in order, and then from the
/// cell model files, in order: a Liberty cell is never replaced by a model of
/// the same name, as the Yosys route's stubs are never replaced by one.
class CellInterfaces {
  /// Creates an empty set.
  CellInterfaces();

  final Map<String, CellInterface> _byName = <String, CellInterface>{};

  /// Warnings noticed while building the set, for Diagnostics.
  final List<String> warnings = <String>[];

  /// How many interfaces came from Liberty libraries.
  int libertyCount = 0;

  /// How many came from cell model files.
  int modelCount = 0;

  /// The interface of [name], or `null`.
  CellInterface? operator [](String name) => _byName[name];

  /// How many interfaces are held.
  int get length => _byName.length;

  /// Adds [interface] unless [source]'s earlier definition of the name
  /// exists, noting the duplicate in [warnings].
  void add(CellInterface interface, {required String source}) {
    if (_byName.containsKey(interface.name)) {
      warnings.add(
        'Cell "${interface.name}" is defined more than once among the cell '
        'libraries and cell models; the first definition is used '
        '(ignored in $source).',
      );
      return;
    }
    _byName[interface.name] = interface;
  }

  /// Adds every cell of [library].
  void addLiberty(LibertyLibrary library) {
    for (final cell in library.cells) {
      final before = _byName.length;
      add(
        CellInterface(
          name: cell.name,
          ports: <CellPort>[
            for (final port in cell.ports)
              CellPort(
                name: port.name,
                direction: switch (port.direction) {
                  LibertyPortDirection.input => PortDirection.input,
                  LibertyPortDirection.output => PortDirection.output,
                  LibertyPortDirection.inout => PortDirection.inout,
                },
                msb: port.msb,
                lsb: port.lsb,
              ),
          ],
        ),
        source: library.path,
      );
      if (_byName.length > before) libertyCount++;
    }
  }

  /// Adds every module [cells] holds, read from the cell model file [path].
  void addModels(String path, List<CellInterface> cells) {
    for (final cell in cells) {
      final before = _byName.length;
      add(cell, source: path);
      if (_byName.length > before) modelCount++;
    }
  }
}
