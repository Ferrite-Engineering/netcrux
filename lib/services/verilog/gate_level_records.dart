// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:typed_data';

/// A growable list of 32-bit integers in one typed buffer.
final class IntList {
  /// Creates an empty list with room for [capacity] values.
  IntList([int capacity = 8]) : _data = Int32List(capacity < 4 ? 4 : capacity);

  Int32List _data;

  /// How many values the list holds.
  int length = 0;

  /// Appends [value].
  void add(int value) {
    if (length == _data.length) _grow(length + 1);
    _data[length++] = value;
  }

  /// The value at [index].
  int operator [](int index) => _data[index];

  /// Replaces the value at [index].
  void operator []=(int index, int value) => _data[index] = value;

  /// Appends `source[from, to)`.
  void addRange(IntList source, int from, int to) {
    final n = to - from;
    if (n <= 0) return;
    if (length + n > _data.length) _grow(length + n);
    _data.setRange(length, length + n, source._data, from);
    length += n;
  }

  /// Empties the list, keeping its buffer.
  void clear() => length = 0;

  /// Empties the list and drops its buffer.
  void release() {
    length = 0;
    _data = Int32List(4);
  }

  void _grow(int needed) {
    var size = _data.length * 2;
    while (size < needed) {
      size *= 2;
    }
    _data = Int32List(size)..setRange(0, length, _data);
  }
}

/// Provisional bit ids 0 to 3 stand for the constants `0`, `1`, `x` and `z`.
abstract final class ConstId {
  /// Logic 0.
  static const int zero = 0;

  /// Logic 1.
  static const int one = 1;

  /// Unknown.
  static const int unknown = 2;

  /// High impedance.
  static const int highZ = 3;

  /// The first provisional id a net bit can have.
  static const int firstNet = 4;
}

/// What one module of the source contains, in the compact form the parser
/// fills while it reads and the builder turns into model objects once every
/// file has been read and every cell type can be resolved.
///
/// Bits are provisional ids: a net of width `w` declared with `start` owns
/// `start` to `start + w - 1`, least significant first. Assignments merge
/// ids in a union-find, so what a cell or port connects is only final when
/// the module is complete.
final class ModuleRecord {
  /// Creates a record for the module named [nameId] in file [fileIndex].
  ModuleRecord(
    this.nameId,
    this.fileIndex, {
    required this.line,
    required this.column,
  });

  /// The module name's id in the reader's interner.
  final int nameId;

  /// Index of the source file in the reader's file list.
  final int fileIndex;

  /// Where the `module` keyword starts, and where `endmodule` ends.
  final int line;

  /// See [line].
  final int column;

  /// Whether the module was written `(* blackbox *) module ...`: its ports
  /// are its interface and whatever else it holds is not part of the design.
  bool isBlackBox = false;

  /// The line `endmodule` ends on.
  int endLine = 0;

  /// One past the last column of `endmodule`.
  int endColumn = 0;

  /// Net indices of the ports, in port order; filled when the module ends.
  final IntList portNets = IntList();

  /// Header port names of a non-ANSI module (interner ids), in order.
  final IntList headerPorts = IntList();

  // ---- nets, one entry per declared net --------------------------------

  /// Interner id of the net's name.
  final IntList netName = IntList(16);

  /// First provisional id of the net.
  final IntList netStart = IntList(16);

  /// Width in bits.
  final IntList netWidth = IntList(16);

  /// Declared left and right bounds of the range (equal for a scalar).
  final IntList netLeft = IntList(16);

  /// See [netLeft].
  final IntList netRight = IntList(16);

  /// Direction code: 0 none, 1 input, 2 output, 3 inout.
  final IntList netDirection = IntList(16);

  /// Where the declaring identifier is: line, column, one past its end.
  final IntList netLine = IntList(16);

  /// See [netLine].
  final IntList netColumn = IntList(16);

  /// See [netLine].
  final IntList netEndColumn = IntList(16);

  /// 1 for a net created implicitly by a connection to an undeclared name.
  final IntList netImplicit = IntList(16);

  /// Next unused provisional id.
  int idCount = ConstId.firstNet;

  /// Union-find parents over provisional ids.
  Int32List parent = Int32List(64);

  // ---- cells, one entry per instance ------------------------------------

  /// Instance names.
  final List<String> cellNames = <String>[];

  /// Interner id of the instantiated type.
  final IntList cellType = IntList(16);

  /// Where the instance's source span starts and ends (exclusive column).
  final IntList cellLine = IntList(16);

  /// See [cellLine].
  final IntList cellColumn = IntList(16);

  /// See [cellLine].
  final IntList cellEndLine = IntList(16);

  /// See [cellLine].
  final IntList cellEndColumn = IntList(16);

  /// Index into the connection lists of the instance's first connection;
  /// one extra entry closes the last instance once the module is read.
  final IntList cellConnStart = IntList(16);

  // ---- connections, flat ------------------------------------------------

  /// Interner id of the pin name, or `-(position + 1)` for a positional
  /// connection.
  final IntList connPin = IntList(64);

  /// Index into [bits] of the connection's first bit.
  final IntList connBitStart = IntList(64);

  /// Number of bits connected; zero for an empty connection `.A()`.
  final IntList connBitLength = IntList(64);

  /// Provisional ids of every connection's bits, least significant first.
  final IntList bits = IntList(128);

  /// Drops the instances and connections, for a black-box module, whose
  /// body is not part of the design.
  void discardCells() {
    cellNames.clear();
    for (final list in <IntList>[
      cellType,
      cellLine,
      cellColumn,
      cellEndLine,
      cellEndColumn,
      cellConnStart,
      connPin,
      connBitStart,
      connBitLength,
      bits,
    ]) {
      list.release();
    }
  }

  /// Frees everything the record holds, once its module has been built.
  void dispose() {
    parent = Int32List(0);
    cellNames.clear();
    for (final list in <IntList>[
      portNets,
      headerPorts,
      netName,
      netStart,
      netWidth,
      netLeft,
      netRight,
      netDirection,
      netLine,
      netColumn,
      netEndColumn,
      netImplicit,
      cellType,
      cellLine,
      cellColumn,
      cellEndLine,
      cellEndColumn,
      cellConnStart,
      connPin,
      connBitStart,
      connBitLength,
      bits,
    ]) {
      list.release();
    }
  }
}
