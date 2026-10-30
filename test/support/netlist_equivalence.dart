// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Compares two netlist models that describe the same design, built by
// different readers (the native gate-level reader and the Yosys JSON
// route), and says what differs.
//
// The models number their nets independently, so bits are compared by what
// they are connected to, not by id: a bit's label is the smallest
// `name[index]` among the nets (and ports) of its module that contain it, and
// two models agree when every port, net and cell pin carries the same labels
// in both. Two nets that one reader aliases and the other keeps apart carry
// different labels and are reported.
//
// What is compared: the modules that are not unreferenced black boxes (the
// Yosys route keeps every cell of a Liberty library, the native reader the
// cells the design instantiates), their `top` and `blackbox` flags, ports
// (names, directions, widths, labels, order), nets (names, labels, order),
// cells (names, types, connected pins, `port_directions`, labels, order) and,
// as chosen, the `src` attributes. Other attributes (`module_not_derived`,
// instance attributes) are not compared.

import 'package:netcrux/domain/models/netlist/netlist_model.dart';

/// How `src` attributes are compared.
enum SrcComparison {
  /// Not compared.
  ignore,

  /// File base name and start line.
  line,

  /// Exactly, file base name included.
  exact,
}

/// Options for [compareNetlists].
class EquivalenceOptions {
  /// Creates options.
  const EquivalenceOptions({
    this.src = SrcComparison.exact,
    this.compareOrder = true,
    this.maxDifferences = 40,
  });

  /// How `src` attributes are compared.
  final SrcComparison src;

  /// Whether the iteration order of ports, nets, cells, pins and modules
  /// must match, as it decides pin layout and tree order downstream.
  final bool compareOrder;

  /// The most differences collected before comparing stops.
  final int maxDifferences;
}

/// The differences between [actual] and [reference]; empty when they
/// describe the same design.
List<String> compareNetlists(
  NetlistModel actual,
  NetlistModel reference, {
  EquivalenceOptions options = const EquivalenceOptions(),
}) {
  final out = <String>[];
  void note(String text) {
    if (out.length < options.maxDifferences) out.add(text);
  }

  final a = _compared(actual);
  final r = _compared(reference);
  final aNames = a.keys.toList();
  final rNames = r.keys.toList();
  for (final name in aNames) {
    if (!r.containsKey(name)) note('module $name only in the compared model');
  }
  for (final name in rNames) {
    if (!a.containsKey(name)) note('module $name only in the reference');
  }
  if (options.compareOrder) {
    final common = aNames.where(r.containsKey).toList();
    final commonR = rNames.where(a.containsKey).toList();
    if (common.join('\u0000') != commonR.join('\u0000')) {
      note('module order differs: $common vs $commonR');
    }
  }
  for (final name in aNames) {
    final other = r[name];
    if (other == null) continue;
    _compareModule(a[name]!, other, options, note);
    if (out.length >= options.maxDifferences) break;
  }
  return out;
}

/// The modules to compare: every module except a black box nothing
/// instantiates (in the compared set).
Map<String, Module> _compared(NetlistModel model) {
  final referenced = <String>{};
  for (final module in model.modules.values) {
    if (module.isBlackBox) continue;
    for (final cell in module.cells.values) {
      referenced.add(cell.type);
    }
  }
  return <String, Module>{
    for (final entry in model.modules.entries)
      if (!entry.value.isBlackBox || referenced.contains(entry.key))
        entry.key: entry.value,
  };
}

void _compareModule(
  Module a,
  Module r,
  EquivalenceOptions options,
  void Function(String) note,
) {
  final where = 'module ${a.name}';
  if (a.isTop != r.isTop) note('$where: top flag ${a.isTop} vs ${r.isTop}');
  if (a.isBlackBox != r.isBlackBox) {
    note('$where: blackbox flag ${a.isBlackBox} vs ${r.isBlackBox}');
  }
  if (!a.isBlackBox) {
    _compareSrc(where, a.attributes['src'], r.attributes['src'], options, note);
  }
  final labelsA = _Labels(a);
  final labelsR = _Labels(r);

  _compareKeys('$where ports', a.ports.keys, r.ports.keys, options, note);
  for (final entry in a.ports.entries) {
    final other = r.ports[entry.key];
    if (other == null) continue;
    final port = entry.value;
    if (port.direction != other.direction) {
      note(
        '$where: port ${port.name} direction ${port.direction.name} vs '
        '${other.direction.name}',
      );
    }
    if (a.isBlackBox) {
      if (port.width != other.width) {
        note('$where: port ${port.name} width ${port.width} vs ${other.width}');
      }
      continue;
    }
    _compareBits(
      '$where: port ${port.name}',
      labelsA.of(port.bits),
      labelsR.of(other.bits),
      note,
    );
  }
  if (a.isBlackBox) return;

  _compareKeys('$where nets', a.nets.keys, r.nets.keys, options, note);
  for (final entry in a.nets.entries) {
    final other = r.nets[entry.key];
    if (other == null) continue;
    _compareBits(
      '$where: net ${entry.key}',
      labelsA.of(entry.value.bits),
      labelsR.of(other.bits),
      note,
    );
    if (entry.value.hideName != other.hideName) {
      note('$where: net ${entry.key} hide_name differs');
    }
    _compareSrc(
      '$where: net ${entry.key}',
      entry.value.attributes['src'],
      other.attributes['src'],
      options,
      note,
    );
  }

  _compareKeys('$where cells', a.cells.keys, r.cells.keys, options, note);
  for (final entry in a.cells.entries) {
    final other = r.cells[entry.key];
    if (other == null) continue;
    final cell = entry.value;
    final cellWhere = '$where: cell ${cell.name}';
    if (cell.type != other.type) {
      note('$cellWhere: type ${cell.type} vs ${other.type}');
    }
    _compareKeys(
      '$cellWhere pins',
      cell.connections.keys,
      other.connections.keys,
      options,
      note,
    );
    for (final pin in cell.connections.entries) {
      final counterpart = other.connections[pin.key];
      if (counterpart == null) continue;
      _compareBits(
        '$cellWhere pin ${pin.key}',
        labelsA.of(pin.value),
        labelsR.of(counterpart),
        note,
      );
    }
    final dirA = <String, PortDirection>{...cell.portDirections};
    final dirR = <String, PortDirection>{...other.portDirections};
    if (dirA.length != dirR.length ||
        dirA.entries.any((e) => dirR[e.key] != e.value)) {
      note('$cellWhere: port directions $dirA vs $dirR');
    }
    _compareSrc(
      cellWhere,
      cell.attributes['src'],
      other.attributes['src'],
      options,
      note,
    );
  }
}

void _compareKeys(
  String what,
  Iterable<String> a,
  Iterable<String> r,
  EquivalenceOptions options,
  void Function(String) note,
) {
  final setA = a.toSet();
  final setR = r.toSet();
  for (final key in setA.difference(setR).take(5)) {
    note('$what: $key only in the compared model');
  }
  for (final key in setR.difference(setA).take(5)) {
    note('$what: $key only in the reference');
  }
  if (options.compareOrder && setA.length == setR.length) {
    final listA = a.toList();
    final listR = r.toList();
    for (var i = 0; i < listA.length; i++) {
      if (listA[i] != listR[i]) {
        note('$what: order differs at $i (${listA[i]} vs ${listR[i]})');
        break;
      }
    }
  }
}

void _compareBits(
  String what,
  List<String> a,
  List<String> r,
  void Function(String) note,
) {
  if (a.length != r.length || a.join(',') != r.join(',')) {
    note('$what: bits $a vs $r');
  }
}

void _compareSrc(
  String what,
  String? a,
  String? r,
  EquivalenceOptions options,
  void Function(String) note,
) {
  if (options.src == SrcComparison.ignore) return;
  if (a == null || r == null) {
    if (a != r) note('$what: src $a vs $r');
    return;
  }
  final pa = _SrcParts.parse(a);
  final pr = _SrcParts.parse(r);
  final same = options.src == SrcComparison.exact
      ? pa.file == pr.file && pa.span == pr.span
      : pa.file == pr.file && pa.firstLine == pr.firstLine;
  if (!same) note('$what: src $a vs $r');
}

class _SrcParts {
  _SrcParts(this.file, this.span, this.firstLine);

  factory _SrcParts.parse(String src) {
    final colon = src.lastIndexOf(':');
    if (colon < 0) return _SrcParts(src, '', '');
    final path = src.substring(0, colon);
    final span = src.substring(colon + 1);
    final base = path.split(RegExp(r'[\\/]')).last;
    return _SrcParts(base, span, span.split('.').first);
  }

  final String file;
  final String span;
  final String firstLine;
}

/// Labels the bits of one module by the nets that contain them.
class _Labels {
  _Labels(Module module) {
    void add(String name, List<BitRef> bits) {
      for (var i = 0; i < bits.length; i++) {
        final bit = bits[i];
        if (bit is! NetBit) continue;
        final label = bits.length == 1 ? name : '$name[$i]';
        final known = _byId[bit.netId];
        if (known == null || label.compareTo(known) < 0) {
          _byId[bit.netId] = label;
        }
      }
    }

    for (final port in module.ports.values) {
      add(port.name, port.bits);
    }
    for (final net in module.nets.values) {
      add(net.name, net.bits);
    }
  }

  final Map<int, String> _byId = <int, String>{};

  List<String> of(List<BitRef> bits) => <String>[
    for (final bit in bits)
      switch (bit) {
        NetBit(:final netId) => _byId[netId] ?? 'anon#$netId',
        ConstantBit() => "'${bit.toJson()}",
      },
  ];
}
