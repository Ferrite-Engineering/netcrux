// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:typed_data';

import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/services/verilog/cell_interface.dart';
import 'package:netcrux/services/verilog/gate_level_parser.dart';
import 'package:netcrux/services/verilog/gate_level_records.dart';
import 'package:netcrux/services/verilog/verilog_scanner.dart';
import 'package:netcrux/services/yosys/streaming_yosys_json_reader.dart';

/// The `creator` string of a model the native reader built.
const String kNativeReaderCreator = 'NetCrux native gate-level reader';

/// The attribute value Yosys writes for a set boolean attribute.
const String _setAttribute = '00000000000000000000000000000001';

/// What building the model reported besides the model.
class GateLevelBuildReport {
  /// Creates a report.
  GateLevelBuildReport({
    required this.warnings,
    required this.modules,
    required this.cells,
    required this.nets,
    required this.topModule,
  });

  /// Warnings for Diagnostics: `path:line: Warning: text` lines (path-less
  /// ones without the prefix).
  final List<String> warnings;

  /// Modules in the model: source modules and black-box stubs.
  final int modules;

  /// Cells in all modules.
  final int cells;

  /// Declared nets in all modules.
  final int nets;

  /// The name of the module chosen as top.
  final String topModule;
}

/// Turns what [GateLevelParser] read into a [NetlistModel] shaped like the
/// one the Yosys route builds from `write_json`.
///
/// The model is the same data: modules, ports, cells and nets in name order,
/// pins in name order within a cell, bits numbered from 2 in the order Yosys
/// meets them (ports, then cells, then nets), aliased nets sharing bits,
/// supply nets and tie-offs as constant bits, unconnected pins as empty
/// lists, `src` attributes of the form `file:line.col-line.col`, and the
/// `top` attribute on the top module. Cell types that nothing in the source
/// defines get a black-box stub module when a Liberty library or cell model
/// declares them, and none otherwise (the inference of their pin directions
/// is `inferBlackBoxPorts`, which the caller runs).
///
/// Throws [NativeReaderFallback] for an inconsistency only visible once the
/// whole design is read: no module, a missing top, recursive instantiation,
/// an instance named twice, a pin connected twice.
class GateLevelModelBuilder {
  /// Creates a builder over [design] and the cell [interfaces].
  GateLevelModelBuilder(
    this.design,
    this.interfaces, {
    this.cancellation,
    this.maxWarnings = 200,
  });

  /// What was read.
  final GateLevelDesign design;

  /// Cell interfaces from Liberty libraries and cell model files.
  final CellInterfaces interfaces;

  /// Checked while building.
  final CancellationToken? cancellation;

  /// How many warnings are kept; the rest are counted.
  final int maxWarnings;

  final List<String> _warnings = <String>[];
  int _droppedWarnings = 0;

  Interner get _names => design.names;

  // Type definitions, by interner id.
  final Map<int, _Def?> _defs = <int, _Def?>{};
  final Map<int, _Def> _stubsUsed = <int, _Def>{};

  int _cellCount = 0;
  int _netCount = 0;

  /// Builds the model with [topName] as the top module, or the one
  /// the hierarchy implies when it is empty.
  (NetlistModel, GateLevelBuildReport) build({String topName = ''}) {
    if (design.modules.isEmpty) {
      throw NativeReaderFallback(
        NativeReaderStop.inconsistent,
        'no module is defined in the source files',
        path: design.files.isEmpty ? '' : design.files.first,
      );
    }
    final top = _chooseTop(topName);
    final reachable = _reachable(top);
    // A module's definition is read from its record, which is released once
    // the module is built, so every definition is taken first.
    for (final record in design.modules) {
      _defFor(record.nameId);
    }
    _rankPins(reachable);
    final modules = <(String, Module)>[];
    for (final record in reachable) {
      modules.add((
        _names.stringOf(record.nameId),
        _buildModule(record, isTop: identical(record, top)),
      ));
      record.dispose();
    }
    for (final def in _stubsUsed.values) {
      modules.add((def.name, _stubModule(def)));
    }
    modules.sort((a, b) => a.$1.compareTo(b.$1));
    final map = <String, Module>{
      for (final (name, module) in modules) name: module,
    };
    if (_droppedWarnings > 0) {
      _warnings.add(
        'Warning: $_droppedWarnings more warnings from the native '
        'gate-level reader are not shown.',
      );
    }
    return (
      NetlistModel(creator: kNativeReaderCreator, modules: map),
      GateLevelBuildReport(
        warnings: _warnings,
        modules: map.length,
        cells: _cellCount,
        nets: _netCount,
        topModule: _names.stringOf(top.nameId),
      ),
    );
  }

  void _warn(String path, int line, String text) {
    if (_warnings.length >= maxWarnings) {
      _droppedWarnings++;
      return;
    }
    _warnings.add(
      line > 0 ? '$path:$line: Warning: $text' : 'Warning: $text',
    );
  }

  // ---- hierarchy ---------------------------------------------------------

  _Def? _defFor(int typeId) {
    if (_defs.containsKey(typeId)) return _defs[typeId];
    final record = design.byName[typeId];
    _Def? def;
    if (record != null) {
      def = _Def.fromRecord(record, _names);
    } else {
      final interface = interfaces[_names.stringOf(typeId)];
      if (interface != null) def = _Def.fromInterface(interface, _names);
    }
    _defs[typeId] = def;
    return def;
  }

  ModuleRecord _chooseTop(String topName) {
    if (topName.isNotEmpty) {
      final id = _names.internString(topName);
      final record = design.byName[id];
      if (record == null) {
        throw NativeReaderFallback(
          NativeReaderStop.inconsistent,
          'the top module "$topName" is not defined in the source files',
          path: design.files.first,
        );
      }
      return record;
    }
    final instantiated = <int>{};
    for (final record in design.modules) {
      final types = record.cellType;
      for (var i = 0; i < types.length; i++) {
        final t = types[i];
        if (design.byName.containsKey(t)) instantiated.add(t);
      }
    }
    final height = <int, int>{};
    final onPath = <int>{};
    int heightOf(ModuleRecord record, int depth) {
      final known = height[record.nameId];
      if (known != null) return known;
      if (depth > 4096) {
        throw NativeReaderFallback(
          NativeReaderStop.unsupported,
          'a module hierarchy more than 4096 levels deep',
          path: design.files[record.fileIndex],
          line: record.line,
        );
      }
      if (!onPath.add(record.nameId)) {
        throw NativeReaderFallback(
          NativeReaderStop.inconsistent,
          'module "${_names.stringOf(record.nameId)}" instantiates itself',
          path: design.files[record.fileIndex],
          line: record.line,
        );
      }
      var best = 0;
      final types = record.cellType;
      final seen = <int>{};
      for (var i = 0; i < types.length; i++) {
        final t = types[i];
        if (!seen.add(t)) continue;
        final child = design.byName[t];
        final score = child != null
            ? heightOf(child, depth + 1) + 1
            : (interfaces[_names.stringOf(t)] != null ? 1 : 0);
        if (score > best) best = score;
      }
      onPath.remove(record.nameId);
      height[record.nameId] = best;
      return best;
    }

    ModuleRecord? best;
    var bestScore = -1;
    for (final record in design.modules) {
      if (instantiated.contains(record.nameId)) continue;
      final score = heightOf(record, 0);
      if (score >= bestScore) {
        best = record;
        bestScore = score;
      }
    }
    if (best == null) {
      throw NativeReaderFallback(
        NativeReaderStop.inconsistent,
        'every module is instantiated by another; no top module',
        path: design.files.first,
      );
    }
    return best;
  }

  /// The source modules reachable from [top], in definition order.
  List<ModuleRecord> _reachable(ModuleRecord top) {
    final visited = <int>{top.nameId};
    final stack = <ModuleRecord>[top];
    final onPath = <int>{};
    // Iterative walk; instantiation cycles are caught by the height pass
    // for an inferred top and here for a named one.
    final order = <ModuleRecord>[];
    while (stack.isNotEmpty) {
      final record = stack.removeLast();
      order.add(record);
      final types = record.cellType;
      final seen = <int>{};
      for (var i = 0; i < types.length; i++) {
        final t = types[i];
        if (!seen.add(t)) continue;
        final child = design.byName[t];
        if (child != null) {
          if (identical(child, record)) {
            throw NativeReaderFallback(
              NativeReaderStop.inconsistent,
              'module "${_names.stringOf(record.nameId)}" instantiates itself',
              path: design.files[record.fileIndex],
              line: record.line,
            );
          }
          if (visited.add(child.nameId)) stack.add(child);
        }
      }
    }
    onPath.clear();
    _checkAcyclic(order);
    final inOrder = <ModuleRecord>[
      for (final record in design.modules)
        if (visited.contains(record.nameId)) record,
    ];
    return inOrder;
  }

  void _checkAcyclic(List<ModuleRecord> reachable) {
    // 0 unvisited, 1 on the current path, 2 done.
    final state = <int, int>{};
    for (final root in reachable) {
      if (state[root.nameId] == 2) continue;
      final stack = <(ModuleRecord, int)>[(root, 0)];
      state[root.nameId] = 1;
      while (stack.isNotEmpty) {
        final (record, index) = stack.removeLast();
        final types = record.cellType;
        var i = index;
        var descended = false;
        while (i < types.length) {
          final child = design.byName[types[i++]];
          if (child == null) continue;
          final s = state[child.nameId] ?? 0;
          if (s == 1) {
            throw NativeReaderFallback(
              NativeReaderStop.inconsistent,
              'module "${_names.stringOf(child.nameId)}" instantiates itself',
              path: design.files[child.fileIndex],
              line: child.line,
            );
          }
          if (s == 0) {
            state[child.nameId] = 1;
            stack
              ..add((record, i))
              ..add((child, 0));
            descended = true;
            break;
          }
        }
        if (!descended) state[record.nameId] = 2;
      }
    }
  }

  // ---- pin order ----------------------------------------------------------

  /// `_rank[id]` is the position of pin name `id` in string order among the
  /// pin names the named connections use, or -1.
  Int32List _rank = Int32List(0);

  void _rankPins(List<ModuleRecord> modules) {
    final seen = Uint8List(_names.length);
    final ids = <int>[];
    for (final record in modules) {
      final pins = record.connPin;
      for (var i = 0; i < pins.length; i++) {
        final pin = pins[i];
        if (pin >= 0 && seen[pin] == 0) {
          seen[pin] = 1;
          ids.add(pin);
        }
      }
    }
    ids.sort((a, b) => _names.stringOf(a).compareTo(_names.stringOf(b)));
    final rank = Int32List(_names.length)..fillRange(0, _names.length, -1);
    for (var i = 0; i < ids.length; i++) {
      rank[ids[i]] = i;
    }
    _rank = rank;
  }

  bool _pinLess(int a, int b) {
    if (a < _rank.length && b < _rank.length) {
      final ra = _rank[a];
      final rb = _rank[b];
      if (ra >= 0 && rb >= 0) return ra < rb;
    }
    return _names.stringOf(a).compareTo(_names.stringOf(b)) < 0;
  }

  // ---- one module ---------------------------------------------------------

  Module _buildModule(ModuleRecord m, {required bool isTop}) {
    final path = design.files[m.fileIndex];
    final moduleName = _names.stringOf(m.nameId);
    final b = _ModuleBuild(m);

    // Ports first: they number the first bits.
    final ports = <String, Port>{};
    for (var i = 0; i < m.portNets.length; i++) {
      final net = m.portNets[i];
      final name = _names.stringOf(m.netName[net]);
      final start = m.netStart[net];
      final width = m.netWidth[net];
      ports[name] = Port(
        name: name,
        direction: _direction(m.netDirection[net]),
        bits: b.bitsOf(start, width),
      );
    }

    if (m.isBlackBox) return _blackBoxModule(m, ports, b, path, moduleName);

    // Cells, in name order.
    final cellCount = m.cellNames.length;
    final order = _sortedOrder(m.cellNames);
    for (var i = 1; i < cellCount; i++) {
      if (m.cellNames[order[i]] == m.cellNames[order[i - 1]]) {
        throw NativeReaderFallback(
          NativeReaderStop.inconsistent,
          'the instance name "${m.cellNames[order[i]]}" is used twice in '
          'module "$moduleName"',
          path: path,
          line: m.cellLine[order[i]],
        );
      }
    }
    m.cellConnStart.add(m.connPin.length);
    final cells = <String, Cell>{};
    final scratch = _CellScratch();
    for (var k = 0; k < cellCount; k++) {
      if ((k & 0xFFF) == 0 && (cancellation?.isCancelled ?? false)) {
        throw const _Cancelled();
      }
      final c = order[k];
      cells[m.cellNames[c]] = _buildCell(m, c, b, scratch, path);
    }

    // Nets, in name order.
    final netNames = <String>[
      for (var i = 0; i < m.netName.length; i++) _names.stringOf(m.netName[i]),
    ];
    final netOrder = _sortedOrder(netNames);
    final nets = <String, Net>{};
    for (final index in netOrder) {
      nets[netNames[index]] = Net(
        name: netNames[index],
        bits: b.bitsOf(m.netStart[index], m.netWidth[index]),
        attributes: <String, String>{
          'src':
              '$path:${m.netLine[index]}.${m.netColumn[index]}-'
              '${m.netLine[index]}.${m.netEndColumn[index]}',
        },
      );
    }
    _cellCount += cellCount;
    _netCount += nets.length;
    return Module(
      name: moduleName,
      attributes: <String, String>{
        if (isTop) 'top': _setAttribute,
        'src': '$path:${m.line}.${m.column}-${m.endLine}.${m.endColumn}',
      },
      ports: ports,
      cells: cells,
      nets: nets,
    );
  }

  /// A source module written `(* blackbox *)`: its ports and the nets of its
  /// ports, and nothing of its body.
  Module _blackBoxModule(
    ModuleRecord m,
    Map<String, Port> ports,
    _ModuleBuild b,
    String path,
    String moduleName,
  ) {
    final names = <String>[
      for (var i = 0; i < m.portNets.length; i++)
        _names.stringOf(m.netName[m.portNets[i]]),
    ];
    final nets = <String, Net>{};
    for (final index in _sortedOrder(names)) {
      final net = m.portNets[index];
      nets[names[index]] = Net(
        name: names[index],
        bits: b.bitsOf(m.netStart[net], m.netWidth[net]),
        attributes: <String, String>{
          'src':
              '$path:${m.netLine[net]}.${m.netColumn[net]}-'
              '${m.netLine[net]}.${m.netEndColumn[net]}',
        },
      );
    }
    _netCount += nets.length;
    return Module(
      name: moduleName,
      attributes: <String, String>{
        'blackbox': _setAttribute,
        'src': '$path:${m.line}.${m.column}-${m.endLine}.${m.endColumn}',
      },
      ports: ports,
      cells: const <String, Cell>{},
      nets: nets,
    );
  }

  static PortDirection _direction(int code) => switch (code) {
    DirectionCode.input => PortDirection.input,
    DirectionCode.output => PortDirection.output,
    _ => PortDirection.inout,
  };

  /// Indices of [names] in ascending string order.
  static List<int> _sortedOrder(List<String> names) {
    final n = names.length;
    final order = List<int>.generate(n, (i) => i);
    var sorted = true;
    for (var i = 1; i < n; i++) {
      if (names[i - 1].compareTo(names[i]) > 0) {
        sorted = false;
        break;
      }
    }
    if (!sorted) order.sort((a, b) => names[a].compareTo(names[b]));
    return order;
  }

  Cell _buildCell(
    ModuleRecord m,
    int c,
    _ModuleBuild b,
    _CellScratch scratch,
    String path,
  ) {
    final connStart = m.cellConnStart[c];
    final connEnd = m.cellConnStart[c + 1];
    final count = connEnd - connStart;
    final typeId = m.cellType[c];
    final def = _defFor(typeId);
    if (def != null && !def.isSource) _stubsUsed[typeId] = def;
    scratch.reserve(count);
    final pinIds = scratch.pinIds;
    final connIndex = scratch.connIndex;
    final line = m.cellLine[c];
    for (var k = 0; k < count; k++) {
      final ci = connStart + k;
      var pin = m.connPin[ci];
      if (pin < 0) {
        final position = -pin - 1;
        if (def != null) {
          if (position >= def.portIds.length) {
            throw NativeReaderFallback(
              NativeReaderStop.inconsistent,
              'the instance "${m.cellNames[c]}" of "${def.name}" has more '
              'positional connections than the module has ports',
              path: path,
              line: line,
            );
          }
          pin = def.portIds[position];
        } else {
          pin = _names.internString('\$${position + 1}');
        }
      }
      // Insertion sort by pin name; equal names are a duplicate.
      var j = k;
      while (j > 0 && _pinLess(pin, pinIds[j - 1])) {
        pinIds[j] = pinIds[j - 1];
        connIndex[j] = connIndex[j - 1];
        j--;
      }
      pinIds[j] = pin;
      connIndex[j] = ci;
    }
    for (var k = 1; k < count; k++) {
      if (pinIds[k] == pinIds[k - 1]) {
        throw NativeReaderFallback(
          NativeReaderStop.inconsistent,
          'the pin "${_names.stringOf(pinIds[k])}" of the instance '
          '"${m.cellNames[c]}" is connected twice',
          path: path,
          line: line,
        );
      }
    }
    final connections = <String, List<BitRef>>{};
    for (var k = 0; k < count; k++) {
      final ci = connIndex[k];
      final length = m.connBitLength[ci];
      final pinName = _names.stringOf(pinIds[k]);
      if (length == 0) {
        connections[pinName] = const <BitRef>[];
        continue;
      }
      final start = m.connBitStart[ci];
      if (def != null) {
        final expected = def.widthOf(pinIds[k]);
        if (expected != null && expected != length) {
          _warn(
            path,
            line,
            'pin $pinName of ${m.cellNames[c]} (${def.name}) is connected to '
            '$length bits but declared $expected wide',
          );
        }
      }
      connections[pinName] = b.connection(m.bits, start, length);
    }
    final directions = def == null
        ? const <String, PortDirection>{}
        : def.directionsFor(pinIds, count, _names);
    return Cell(
      name: m.cellNames[c],
      type: _names.stringOf(typeId),
      parameters: const <String, String>{},
      attributes: <String, String>{
        'src':
            '$path:$line.${m.cellColumn[c]}-'
            '${m.cellEndLine[c]}.${m.cellEndColumn[c]}',
      },
      portDirections: directions,
      connections: connections,
    );
  }

  // ---- stubs --------------------------------------------------------------

  Module _stubModule(_Def def) {
    var next = 2;
    final ports = <String, Port>{};
    final nets = <String, Net>{};
    for (var i = 0; i < def.portNames.length; i++) {
      final width = def.widths[i] ?? 1;
      final bits = <BitRef>[
        for (var k = 0; k < width; k++) NetBit(next + k),
      ];
      next += width;
      ports[def.portNames[i]] = Port(
        name: def.portNames[i],
        direction: def.directions[i],
        bits: bits,
      );
      nets[def.portNames[i]] = Net(
        name: def.portNames[i],
        bits: bits,
        attributes: const <String, String>{},
      );
    }
    return Module(
      name: def.name,
      attributes: const <String, String>{'blackbox': _setAttribute},
      ports: ports,
      cells: const <String, Cell>{},
      nets: nets,
    );
  }
}

/// Thrown when the cancellation token fires mid-build.
class _Cancelled implements Exception {
  const _Cancelled();
}

/// Whether a [Object] thrown by the builder is its cancellation.
bool isGateLevelCancellation(Object error) => error is _Cancelled;

/// Reusable per-cell sort buffers.
class _CellScratch {
  Int32List pinIds = Int32List(32);
  Int32List connIndex = Int32List(32);

  void reserve(int n) {
    if (n <= pinIds.length) return;
    var size = pinIds.length;
    while (size < n) {
      size *= 2;
    }
    pinIds = Int32List(size);
    connIndex = Int32List(size);
  }
}

/// The dense numbering and shared bit objects of one module being built.
class _ModuleBuild {
  _ModuleBuild(this.m)
    : _dense = Int32List(m.idCount)..fillRange(0, m.idCount, -1);

  final ModuleRecord m;
  final Int32List _dense;
  int _next = 0;
  final List<BitRef?> _bitObjects = <BitRef?>[];
  final List<List<BitRef>?> _single = <List<BitRef>?>[];

  static const List<BitRef> _constants = <BitRef>[
    ConstantBit(ConstantBitValue.zero),
    ConstantBit(ConstantBitValue.one),
    ConstantBit(ConstantBitValue.x),
    ConstantBit(ConstantBitValue.z),
  ];

  static const List<List<BitRef>> _constantLists = <List<BitRef>>[
    <BitRef>[ConstantBit(ConstantBitValue.zero)],
    <BitRef>[ConstantBit(ConstantBitValue.one)],
    <BitRef>[ConstantBit(ConstantBitValue.x)],
    <BitRef>[ConstantBit(ConstantBitValue.z)],
  ];

  int _root(int id) {
    final parent = m.parent;
    var x = id;
    while (parent[x] != x) {
      parent[x] = parent[parent[x]];
      x = parent[x];
    }
    return x;
  }

  /// The dense index of the class of provisional bit [id], or a negative
  /// constant code `-1 - constId`.
  int _denseOf(int id) {
    final root = _root(id);
    if (root < ConstId.firstNet) return -1 - root;
    var d = _dense[root];
    if (d < 0) {
      d = _next++;
      _dense[root] = d;
      _bitObjects.add(NetBit(d + 2));
      _single.add(null);
    }
    return d;
  }

  BitRef _bit(int id) {
    final d = _denseOf(id);
    return d < 0 ? _constants[-1 - d] : _bitObjects[d]!;
  }

  List<BitRef> _one(int id) {
    final d = _denseOf(id);
    if (d < 0) return _constantLists[-1 - d];
    return _single[d] ??= List<BitRef>.unmodifiable(<BitRef>[_bitObjects[d]!]);
  }

  /// The bits of the net with first id [start] and [width] bits.
  List<BitRef> bitsOf(int start, int width) {
    if (width == 1) return _one(start);
    return <BitRef>[for (var k = 0; k < width; k++) _bit(start + k)];
  }

  /// A cell pin's bits from `bits[from, from + length)`.
  List<BitRef> connection(IntList bits, int from, int length) {
    if (length == 1) return _one(bits[from]);
    return <BitRef>[for (var k = 0; k < length; k++) _bit(bits[from + k])];
  }
}

/// A cell type's interface as the builder uses it: from a module of the
/// source or from a Liberty or cell model interface.
class _Def {
  _Def._(
    this.name,
    this.portNames,
    this.directions,
    this.widths,
    this.portIds, {
    required this.isSource,
  });

  factory _Def.fromRecord(ModuleRecord record, Interner names) {
    final portNames = <String>[];
    final directions = <PortDirection>[];
    final widths = <int?>[];
    final ids = Int32List(record.portNets.length);
    for (var i = 0; i < record.portNets.length; i++) {
      final net = record.portNets[i];
      final nameId = record.netName[net];
      portNames.add(names.stringOf(nameId));
      ids[i] = nameId;
      directions.add(
        GateLevelModelBuilder._direction(record.netDirection[net]),
      );
      widths.add(record.netWidth[net]);
    }
    return _Def._(
      names.stringOf(record.nameId),
      portNames,
      directions,
      widths,
      ids,
      isSource: true,
    );
  }

  factory _Def.fromInterface(CellInterface interface, Interner names) {
    final ids = Int32List(interface.ports.length);
    for (var i = 0; i < interface.ports.length; i++) {
      ids[i] = names.internString(interface.ports[i].name);
    }
    return _Def._(
      interface.name,
      <String>[for (final p in interface.ports) p.name],
      <PortDirection>[for (final p in interface.ports) p.direction],
      <int?>[for (final p in interface.ports) p.width],
      ids,
      isSource: false,
    );
  }

  final String name;
  final List<String> portNames;
  final List<PortDirection> directions;
  final List<int?> widths;

  /// Interner ids of [portNames].
  final Int32List portIds;

  final bool isSource;

  Map<int, int>? _indexById;

  int _indexOf(int pinId) {
    final map = _indexById ??= <int, int>{
      for (var i = 0; i < portIds.length; i++) portIds[i]: i,
    };
    return map[pinId] ?? -1;
  }

  /// The declared width of pin [pinId], or `null` when it is not declared
  /// or its width is not known.
  int? widthOf(int pinId) {
    final i = _indexOf(pinId);
    return i < 0 ? null : widths[i];
  }

  final List<_DirectionSet> _sets = <_DirectionSet>[];

  /// The `port_directions` of an instance that connects the first [count]
  /// pins in [pinIds] (sorted): declared pins have their declared direction;
  /// a pin the definition does not declare gets `output`, as Yosys gives it.
  /// Instances that connect the same pins share one map.
  Map<String, PortDirection> directionsFor(
    Int32List pinIds,
    int count,
    Interner names,
  ) {
    for (final set in _sets) {
      if (set.matches(pinIds, count)) return set.map;
    }
    final map = <String, PortDirection>{};
    for (var k = 0; k < count; k++) {
      final i = _indexOf(pinIds[k]);
      map[names.stringOf(pinIds[k])] = i < 0
          ? PortDirection.output
          : directions[i];
    }
    final shared = Map<String, PortDirection>.unmodifiable(map);
    if (_sets.length < 64) {
      _sets.add(
        _DirectionSet(Int32List.fromList(pinIds.sublist(0, count)), shared),
      );
    }
    return shared;
  }
}

class _DirectionSet {
  _DirectionSet(this.pins, this.map);

  final Int32List pins;
  final Map<String, PortDirection> map;

  bool matches(Int32List ids, int count) {
    if (pins.length != count) return false;
    for (var i = 0; i < count; i++) {
      if (pins[i] != ids[i]) return false;
    }
    return true;
  }
}
