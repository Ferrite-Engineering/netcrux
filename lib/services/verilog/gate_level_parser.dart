// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:typed_data';

import 'package:netcrux/services/verilog/gate_level_records.dart';
import 'package:netcrux/services/verilog/verilog_byte_source.dart';
import 'package:netcrux/services/verilog/verilog_keywords.dart';
import 'package:netcrux/services/verilog/verilog_scanner.dart';
import 'package:netcrux/services/yosys/chunked_yosys_json_reader.dart';
import 'package:netcrux/services/yosys/streaming_yosys_json_reader.dart';

/// The most bits one net, or one connection, may have. A larger one is not
/// a netlist this reader will hold; the Yosys route decides what to do.
const int kMaxNetlistBits = 1 << 20;

/// Direction codes in [ModuleRecord.netDirection].
abstract final class DirectionCode {
  /// Not a port.
  static const int none = 0;

  /// `input`.
  static const int input = 1;

  /// `output`.
  static const int output = 2;

  /// `inout`.
  static const int inout = 3;
}

/// Everything read from the source files, ready to be turned into a model.
class GateLevelDesign {
  /// Creates an empty design.
  GateLevelDesign() {
    VerilogKeywords.seed(names);
  }

  /// Every identifier read, keywords first.
  final Interner names = Interner();

  /// The files read, in order; [ModuleRecord.fileIndex] indexes this.
  final List<String> files = <String>[];

  /// The modules, in the order they were defined.
  final List<ModuleRecord> modules = <ModuleRecord>[];

  /// The modules by name id.
  final Map<int, ModuleRecord> byName = <int, ModuleRecord>{};
}

/// Parses structural (gate-level) Verilog into [ModuleRecord]s.
///
/// What it reads: `module`/`endmodule` with ANSI or non-ANSI port lists,
/// `input`/`output`/`inout` and `wire`/`tri`/`supply0`/`supply1`
/// declarations with constant ranges, cell and module instances with named
/// or positional connections, and `assign` between nets, bits, part
/// selects, concatenations, replications and sized constants. Everything
/// else is a [NativeReaderFallback]: the reader never guesses.
///
/// The record of a module is complete when its `endmodule` is read; the
/// positional connections of an instance of a module defined later are
/// resolved by the builder, after every file has been read.
class GateLevelParser {
  /// Creates a parser. [bufferSize] and [maxTokenBytes] size the scanner.
  GateLevelParser({
    this.cancellation,
    this.bufferSize = VerilogScanner.defaultBufferSize,
    this.maxTokenBytes = 64 * 1024,
  });

  /// Checked while scanning.
  final CancellationToken? cancellation;

  /// The scanner's read buffer size.
  final int bufferSize;

  /// The scanner's longest token.
  final int maxTokenBytes;

  /// What has been read so far.
  final GateLevelDesign design = GateLevelDesign();

  late VerilogScanner _s;
  late ModuleRecord _m;
  late int _fileIndex;
  late String _path;
  int _serial = 0;
  Int32List _netOf = Int32List(1024);
  Int32List _netStamp = Int32List(1024);
  int _depth = 0;
  final IntList _scratchLeft = IntList(32);
  final IntList _scratchRight = IntList(32);

  Interner get _names => design.names;

  /// Reads the Verilog file at [path], plain or gzip-compressed.
  void parseFile(String path) {
    final source = openVerilogSource(path);
    try {
      parseSource(source, path);
    } finally {
      source.close();
    }
  }

  /// Reads Verilog from [source], naming it [path] in reports.
  void parseSource(ByteChunkSource source, String path) {
    _path = path;
    _fileIndex = design.files.length;
    design.files.add(path);
    _s = VerilogScanner(
      source,
      path: path,
      bufferSize: bufferSize,
      maxTokenBytes: maxTokenBytes,
      cancellation: cancellation,
    );
    _s.next();
    while (_s.kind != VerilogToken.eof) {
      if (_keyword() == VerilogKeywords.module) {
        _module();
      } else if (_s.kind == VerilogToken.identifier && _keyword() >= 0) {
        _unsupported(_keywordMessage(_s.text));
      } else {
        _syntax('expected `module`');
      }
    }
  }

  // ---- diagnostics -------------------------------------------------------

  Never _unsupported(String what, {int? line}) => throw NativeReaderFallback(
    NativeReaderStop.unsupported,
    what,
    path: _path,
    line: line ?? _s.line,
  );

  /// The phrase for a Verilog keyword the reader does not read, for
  /// "the reader uses ...".
  static String _keywordMessage(String word) => switch (word) {
    'always' ||
    'always_comb' ||
    'always_ff' ||
    'always_latch' ||
    'initial' ||
    'final' => 'an `$word` block',
    'parameter' || 'localparam' || 'defparam' => '`$word` declarations',
    'generate' ||
    'genvar' ||
    'function' ||
    'task' ||
    'specify' ||
    'primitive' ||
    'table' => 'a `$word` construct',
    _ => 'the `$word` keyword',
  };

  Never _inconsistent(String what, {int? line}) => throw NativeReaderFallback(
    NativeReaderStop.inconsistent,
    what,
    path: _path,
    line: line ?? _s.line,
  );

  Never _syntax(String expected) {
    final found = switch (_s.kind) {
      VerilogToken.eof => 'the end of the file',
      VerilogToken.symbol => "'${String.fromCharCode(_s.symbol)}'",
      _ => "'${_clip(_s.text)}'",
    };
    throw NativeReaderFallback(
      NativeReaderStop.malformed,
      '$expected, found $found',
      path: _path,
      line: _s.line,
    );
  }

  static String _clip(String text) =>
      text.length <= 40 ? text : '${text.substring(0, 40)}...';

  // ---- token helpers -----------------------------------------------------

  /// The keyword id of the current token, or -1 when it is not a keyword.
  int _keyword() {
    if (_s.kind != VerilogToken.identifier || _s.escaped) return -1;
    final id = _s.intern(_names);
    return id < VerilogKeywords.count ? id : -1;
  }

  bool _sym(int char) => _s.kind == VerilogToken.symbol && _s.symbol == char;

  void _expectSymbol(int char) {
    if (!_sym(char)) _syntax("expected '${String.fromCharCode(char)}'");
  }

  String _tokenString() => _s.nonAscii || _s.kind != VerilogToken.identifier
      ? _s.text
      : String.fromCharCodes(_s.buffer, _s.tokenStart, _s.tokenEnd);

  // ---- modules -----------------------------------------------------------

  void _module() {
    final startLine = _s.line;
    final startColumn = _s.column;
    final blackBox = _s.precededByBlackBox;
    if (_s.precededByWhiteBox) _unsupported('a `whitebox` module');
    _s.next();
    if (_s.kind != VerilogToken.identifier || _keyword() >= 0) {
      _syntax('expected a module name');
    }
    final nameId = _s.intern(_names);
    if (design.byName.containsKey(nameId)) {
      _inconsistent(
        'module "${_names.stringOf(nameId)}" is defined more than once',
      );
    }
    final record = ModuleRecord(
      nameId,
      _fileIndex,
      line: startLine,
      column: startColumn,
    )..isBlackBox = blackBox;
    _m = record;
    design.modules.add(record);
    design.byName[nameId] = record;
    _serial++;
    _s.next();
    if (_sym(0x23)) _unsupported('a module parameter list');
    var ansi = false;
    if (_sym(0x28)) {
      _s.next();
      if (_sym(0x29)) {
        _s.next();
      } else if (_directionCode() != 0) {
        ansi = true;
        _ansiPorts();
      } else {
        _plainPorts();
      }
    }
    _expectSymbol(0x3B);
    _s.next();
    _body();
    if (blackBox) record.discardCells();
    // `endmodule` is the current token.
    record
      ..endLine = _s.endLine
      ..endColumn = _s.endColumn;
    _s.next();
    if (!ansi) _resolveHeaderPorts();
  }

  /// The direction code of the current token if it is a direction keyword.
  int _directionCode() => switch (_keyword()) {
    VerilogKeywords.input => DirectionCode.input,
    VerilogKeywords.output => DirectionCode.output,
    VerilogKeywords.inout => DirectionCode.inout,
    _ => DirectionCode.none,
  };

  void _plainPorts() {
    while (true) {
      if (_s.kind != VerilogToken.identifier ||
          (!_s.escaped && _keyword() >= 0)) {
        _syntax('expected a port name');
      }
      _m.headerPorts.add(_s.intern(_names));
      _s.next();
      if (_sym(0x2C)) {
        _s.next();
        continue;
      }
      _expectSymbol(0x29);
      _s.next();
      return;
    }
  }

  void _ansiPorts() {
    while (true) {
      final direction = _directionCode();
      if (direction == DirectionCode.none) _syntax('expected a direction');
      _s.next();
      _netType();
      final (left, right) = _optionalRange();
      while (true) {
        if (_s.kind != VerilogToken.identifier ||
            (!_s.escaped && _keyword() >= 0)) {
          _syntax('expected a port name');
        }
        final id = _s.intern(_names);
        final line = _s.line;
        final column = _s.column;
        final endColumn = _s.endColumn;
        _s.next();
        if (_sym(0x3D) || _sym(0x5B)) {
          _unsupported('a port default value or array');
        }
        final net = _declare(
          id,
          left,
          right,
          direction,
          line: line,
          column: column,
          endColumn: endColumn,
        );
        _m.portNets.add(net);
        if (_sym(0x2C)) {
          _s.next();
          if (_directionCode() != DirectionCode.none) break;
          continue;
        }
        _expectSymbol(0x29);
        _s.next();
        return;
      }
    }
  }

  /// Steps over `wire`/`tri`, rejecting the other net and variable types.
  void _netType() {
    final keyword = _keyword();
    switch (keyword) {
      case VerilogKeywords.wire || VerilogKeywords.tri:
        _s.next();
      case VerilogKeywords.reg ||
          VerilogKeywords.logic ||
          VerilogKeywords.variable ||
          VerilogKeywords.signed ||
          VerilogKeywords.unsigned:
        _unsupported(_keywordMessage(_s.text));
      default:
        if (keyword >= 0) _unsupported(_keywordMessage(_s.text));
    }
    final next = _keyword();
    if (next == VerilogKeywords.signed || next == VerilogKeywords.unsigned) {
      _unsupported(_keywordMessage(_s.text));
    }
  }

  void _resolveHeaderPorts() {
    final header = _m.headerPorts;
    for (var i = 0; i < header.length; i++) {
      final net = _lookup(header[i]);
      if (net < 0 || _m.netDirection[net] == DirectionCode.none) {
        _inconsistent(
          'port "${_names.stringOf(header[i])}" of module '
          '"${_names.stringOf(_m.nameId)}" has no direction declaration',
          line: _m.line,
        );
      }
      _m.portNets.add(net);
    }
  }

  // ---- module body -------------------------------------------------------

  void _body() {
    while (true) {
      if (_s.kind == VerilogToken.eof) {
        _syntax('expected `endmodule`');
      }
      if (_s.kind != VerilogToken.identifier) {
        _syntax('expected a declaration or an instance');
      }
      final keyword = _keyword();
      switch (keyword) {
        case -1:
          _instances();
        case VerilogKeywords.endmodule:
          return;
        case VerilogKeywords.input ||
            VerilogKeywords.output ||
            VerilogKeywords.inout:
          _portDeclaration();
        case VerilogKeywords.wire || VerilogKeywords.tri:
          _wireDeclaration();
        case VerilogKeywords.supply0 || VerilogKeywords.supply1:
          _supplyDeclaration(keyword == VerilogKeywords.supply1);
        case VerilogKeywords.assign:
          _assign();
        default:
          _unsupported(_keywordMessage(_s.text));
      }
    }
  }

  // ---- nets --------------------------------------------------------------

  int _lookup(int nameId) =>
      nameId < _netStamp.length && _netStamp[nameId] == _serial
      ? _netOf[nameId]
      : -1;

  /// Declares a net, or merges the declaration into one already made.
  int _declare(
    int nameId,
    int left,
    int right,
    int direction, {
    required int line,
    required int column,
    required int endColumn,
    bool implicit = false,
  }) {
    final width = (left - right).abs() + 1;
    if (width > kMaxNetlistBits) {
      _unsupported('a net wider than $kMaxNetlistBits bits', line: line);
    }
    final existing = _lookup(nameId);
    if (existing >= 0) {
      if (_m.netWidth[existing] != width) {
        _inconsistent(
          'net "${_names.stringOf(nameId)}" is declared twice with '
          'different widths',
          line: line,
        );
      }
      if (direction != DirectionCode.none) {
        if (_m.netDirection[existing] != DirectionCode.none) {
          _inconsistent(
            'port "${_names.stringOf(nameId)}" is declared twice',
            line: line,
          );
        }
        _m.netDirection[existing] = direction;
      }
      if (_m.netImplicit[existing] == 1 && !implicit) {
        _m
          ..netImplicit[existing] = 0
          ..netLine[existing] = line
          ..netColumn[existing] = column
          ..netEndColumn[existing] = endColumn;
      }
      return existing;
    }
    final index = _m.netName.length;
    if (_m.idCount + width > (1 << 30)) {
      _unsupported('a design with more than 2^30 bits in one module');
    }
    final start = _m.idCount;
    _m
      ..netName.add(nameId)
      ..netStart.add(start)
      ..netWidth.add(width)
      ..netLeft.add(left)
      ..netRight.add(right)
      ..netDirection.add(direction)
      ..netLine.add(line)
      ..netColumn.add(column)
      ..netEndColumn.add(endColumn)
      ..netImplicit.add(implicit ? 1 : 0);
    _allocateIds(width);
    _bind(nameId, index);
    return index;
  }

  void _bind(int nameId, int net) {
    if (nameId >= _netStamp.length) {
      var size = _netStamp.length * 2;
      while (size <= nameId) {
        size *= 2;
      }
      _netStamp = Int32List(size)..setRange(0, _netStamp.length, _netStamp);
      _netOf = Int32List(size)..setRange(0, _netOf.length, _netOf);
    }
    _netStamp[nameId] = _serial;
    _netOf[nameId] = net;
  }

  void _allocateIds(int width) {
    final need = _m.idCount + width;
    if (need > _m.parent.length) {
      var size = _m.parent.isEmpty ? 64 : _m.parent.length;
      while (size < need) {
        size *= 2;
      }
      _m.parent = Int32List(size)..setRange(0, _m.parent.length, _m.parent);
    }
    final parent = _m.parent;
    for (var i = _m.idCount; i < need; i++) {
      parent[i] = i;
    }
    // The constants are their own roots.
    for (var c = 0; c < ConstId.firstNet && c < need; c++) {
      parent[c] = c;
    }
    _m.idCount = need;
  }

  int _find(int id) {
    final parent = _m.parent;
    var x = id;
    while (parent[x] != x) {
      parent[x] = parent[parent[x]];
      x = parent[x];
    }
    return x;
  }

  void _union(int a, int b, int line) {
    final ra = _find(a);
    final rb = _find(b);
    if (ra == rb) return;
    if (ra < ConstId.firstNet && rb < ConstId.firstNet) {
      _inconsistent('a net is tied to two different constants', line: line);
    }
    final parent = _m.parent;
    if (rb < ConstId.firstNet) {
      parent[ra] = rb;
    } else if (ra < ConstId.firstNet) {
      parent[rb] = ra;
    } else if (ra < rb) {
      parent[rb] = ra;
    } else {
      parent[ra] = rb;
    }
  }

  /// Reads `[a:b]` if the current token is '[', else a scalar `(0, 0)`.
  (int, int) _optionalRange() {
    if (!_sym(0x5B)) return (0, 0);
    _s.next();
    final left = _integer('a range bound');
    _s.next();
    _expectSymbol(0x3A);
    _s.next();
    final right = _integer('a range bound');
    _s.next();
    _expectSymbol(0x5D);
    _s.next();
    return (left, right);
  }

  /// The value of the current token as a plain decimal integer.
  int _integer(String what) {
    if (_s.kind != VerilogToken.number) {
      if (_s.kind == VerilogToken.identifier) {
        _unsupported('$what that is not a constant number');
      }
      _syntax('expected $what');
    }
    final buf = _s.buffer;
    var value = 0;
    for (var i = _s.tokenStart; i < _s.tokenEnd; i++) {
      final c = buf[i];
      if (c == 0x5F) continue;
      if (c < 0x30 || c > 0x39) {
        _unsupported('$what that is not a plain number');
      }
      value = value * 10 + (c - 0x30);
      if (value > (1 << 40)) _unsupported('$what that is out of range');
    }
    return value;
  }

  void _portDeclaration() {
    final direction = _directionCode();
    _s.next();
    _netType();
    final (left, right) = _optionalRange();
    _declarationNames(left, right, direction);
  }

  void _wireDeclaration() {
    _s.next();
    final keyword = _keyword();
    if (keyword >= 0) _unsupported(_keywordMessage(_s.text));
    if (_sym(0x28) || _sym(0x23)) _unsupported('a net strength or delay');
    final (left, right) = _optionalRange();
    _declarationNames(left, right, DirectionCode.none);
  }

  void _declarationNames(int left, int right, int direction) {
    while (true) {
      if (_s.kind != VerilogToken.identifier ||
          (!_s.escaped && _keyword() >= 0)) {
        _syntax('expected a net name');
      }
      final id = _s.intern(_names);
      final line = _s.line;
      final column = _s.column;
      final endColumn = _s.endColumn;
      _s.next();
      if (_sym(0x3D)) _unsupported('a net declaration with an assignment');
      if (_sym(0x5B)) _unsupported('an array declaration');
      _declare(
        id,
        left,
        right,
        direction,
        line: line,
        column: column,
        endColumn: endColumn,
      );
      if (_sym(0x2C)) {
        _s.next();
        continue;
      }
      _expectSymbol(0x3B);
      _s.next();
      return;
    }
  }

  void _supplyDeclaration(bool one) {
    _s.next();
    if (_sym(0x5B)) _unsupported('a supply net with a range');
    var quirkLine = 0;
    var quirkColumn = 0;
    var first = true;
    while (true) {
      if (_s.kind != VerilogToken.identifier ||
          (!_s.escaped && _keyword() >= 0)) {
        _syntax('expected a net name');
      }
      final id = _s.intern(_names);
      _s.next();
      if (first) {
        // Yosys records a supply net at the token after the first name.
        quirkLine = _s.line;
        quirkColumn = _s.column;
        first = false;
      }
      if (_sym(0x3D)) _unsupported('a net declaration with an assignment');
      final net = _declare(
        id,
        0,
        0,
        DirectionCode.none,
        line: quirkLine,
        column: quirkColumn,
        endColumn: quirkColumn,
      );
      _union(
        _m.netStart[net],
        one ? ConstId.one : ConstId.zero,
        quirkLine,
      );
      if (_sym(0x2C)) {
        _s.next();
        continue;
      }
      _expectSymbol(0x3B);
      _s.next();
      return;
    }
  }

  // ---- assign ------------------------------------------------------------

  void _assign() {
    final line = _s.line;
    _s.next();
    if (_sym(0x23) || _sym(0x28)) {
      _unsupported('an assignment strength or delay');
    }
    while (true) {
      _scratchLeft.clear();
      _scratchRight.clear();
      _expression(_scratchLeft, implicit: false);
      if (!_sym(0x3D)) {
        if (_s.kind == VerilogToken.symbol) {
          _unsupported('an expression in an assignment', line: line);
        }
        _syntax("expected '='");
      }
      _s.next();
      _expression(_scratchRight, implicit: false);
      if (_scratchLeft.length != _scratchRight.length) {
        _inconsistent(
          'an assignment between widths ${_scratchLeft.length} and '
          '${_scratchRight.length}',
          line: line,
        );
      }
      for (var i = 0; i < _scratchLeft.length; i++) {
        _union(_scratchLeft[i], _scratchRight[i], line);
      }
      if (_sym(0x2C)) {
        _s.next();
        continue;
      }
      if (!_sym(0x3B)) {
        if (_s.kind == VerilogToken.symbol) {
          _unsupported('an expression in an assignment', line: line);
        }
        _syntax("expected ';'");
      }
      _s.next();
      return;
    }
  }

  // ---- instances ---------------------------------------------------------

  void _instances() {
    final typeId = _s.intern(_names);
    _s.next();
    if (_sym(0x23)) {
      _unsupported('an instance parameter override or delay');
    }
    while (true) {
      if (_s.kind != VerilogToken.identifier) {
        if (_sym(0x28)) _unsupported('an instance without a name');
        _syntax('expected an instance name');
      }
      if (!_s.escaped && _keyword() >= 0) _syntax('expected an instance name');
      final line = _s.line;
      final column = _s.column;
      final name = _tokenString();
      _s.next();
      if (_sym(0x5B)) _unsupported('an array of instances');
      _expectSymbol(0x28);
      _s.next();
      final m = _m;
      m.cellConnStart.add(m.connPin.length);
      _connections();
      // `_connections` leaves the closing ')' as the current token.
      m
        ..cellNames.add(name)
        ..cellType.add(typeId)
        ..cellLine.add(line)
        ..cellColumn.add(column)
        ..cellEndLine.add(_s.endLine)
        ..cellEndColumn.add(_s.endColumn);
      _s.next();
      if (_sym(0x2C)) {
        _s.next();
        continue;
      }
      _expectSymbol(0x3B);
      _s.next();
      return;
    }
  }

  void _connections() {
    final m = _m;
    if (_sym(0x29)) return;
    var named = false;
    var positional = false;
    var position = 0;
    while (true) {
      if (_sym(0x2E)) {
        if (positional) {
          _unsupported('named and positional connections in one instance');
        }
        named = true;
        _s.next();
        if (_s.kind != VerilogToken.identifier) {
          if (_sym(0x2A)) _unsupported('a wildcard port connection');
          _syntax('expected a pin name');
        }
        final pin = _s.intern(_names);
        _s.next();
        if (!_sym(0x28)) _unsupported('an implicit named port connection');
        _s.next();
        final first = m.bits.length;
        m
          ..connPin.add(pin)
          ..connBitStart.add(first);
        if (!_sym(0x29)) _expression(m.bits, implicit: true);
        m.connBitLength.add(m.bits.length - first);
        if (!_sym(0x29)) {
          if (_s.kind == VerilogToken.symbol) {
            _unsupported('an expression in a port connection');
          }
          _syntax("expected ')'");
        }
        _s.next();
      } else {
        if (named) {
          _unsupported('named and positional connections in one instance');
        }
        positional = true;
        final first = m.bits.length;
        m
          ..connPin.add(-(position + 1))
          ..connBitStart.add(first);
        position++;
        if (!_sym(0x2C) && !_sym(0x29)) _expression(m.bits, implicit: true);
        m.connBitLength.add(m.bits.length - first);
      }
      if (_sym(0x2C)) {
        _s.next();
        continue;
      }
      if (_sym(0x29)) return;
      if (_s.kind == VerilogToken.symbol) {
        _unsupported('an expression in a port connection');
      }
      _syntax("expected ',' or ')'");
    }
  }

  // ---- expressions -------------------------------------------------------

  /// Appends the bits (least significant first) of the expression at the
  /// current token to [out]; leaves the token after it current.
  void _expression(IntList out, {required bool implicit}) {
    final before = out.length;
    _element(out, implicit: implicit);
    if (out.length - before > kMaxNetlistBits) {
      _unsupported('a connection wider than $kMaxNetlistBits bits');
    }
  }

  void _element(IntList out, {required bool implicit}) {
    switch (_s.kind) {
      case VerilogToken.identifier:
        if (!_s.escaped && _keyword() >= 0) {
          _unsupported('an expression');
        }
        _netReference(out, implicit: implicit);
      case VerilogToken.number:
        _numberElement(out, implicit: implicit);
      case VerilogToken.symbol when _s.symbol == 0x7B:
        _concat(out, implicit: implicit);
      default:
        _unsupported('an expression');
    }
  }

  void _concat(IntList out, {required bool implicit}) {
    if (++_depth > 64) {
      _depth = 0;
      _unsupported('concatenations nested more than 64 deep');
    }
    _s.next();
    final local = IntList(16);
    final starts = <int>[];
    while (true) {
      starts.add(local.length);
      _element(local, implicit: implicit);
      if (_sym(0x2C)) {
        _s.next();
        continue;
      }
      if (_sym(0x7D)) break;
      if (_s.kind == VerilogToken.symbol) _unsupported('an expression');
      _syntax("expected ',' or '}'");
    }
    _s.next();
    starts.add(local.length);
    for (var k = starts.length - 2; k >= 0; k--) {
      out.addRange(local, starts[k], starts[k + 1]);
    }
    _depth--;
  }

  void _numberElement(IntList out, {required bool implicit}) {
    final buf = _s.buffer;
    var apostrophe = -1;
    for (var i = _s.tokenStart; i < _s.tokenEnd; i++) {
      if (buf[i] == 0x27) {
        apostrophe = i;
        break;
      }
    }
    if (apostrophe < 0) {
      // A plain decimal: a replication count when a '{' follows.
      final count = _integer('a replication count');
      _s.next();
      if (!_sym(0x7B)) _unsupported('an unsized constant');
      if (count > kMaxNetlistBits) {
        _unsupported('a replication of more than $kMaxNetlistBits');
      }
      if (++_depth > 64) {
        _depth = 0;
        _unsupported('concatenations nested more than 64 deep');
      }
      _s.next();
      final local = IntList(16);
      final starts = <int>[];
      while (true) {
        starts.add(local.length);
        _element(local, implicit: implicit);
        if (_sym(0x2C)) {
          _s.next();
          continue;
        }
        if (_sym(0x7D)) break;
        if (_s.kind == VerilogToken.symbol) _unsupported('an expression');
        _syntax("expected ',' or '}'");
      }
      _s.next();
      starts.add(local.length);
      if (local.length * count > kMaxNetlistBits) {
        _unsupported('a replication of more than $kMaxNetlistBits bits');
      }
      for (var r = 0; r < count; r++) {
        for (var k = starts.length - 2; k >= 0; k--) {
          out.addRange(local, starts[k], starts[k + 1]);
        }
      }
      _depth--;
      return;
    }
    _constant(out, apostrophe);
    _s.next();
  }

  /// Appends the bits of the sized constant under the current token, whose
  /// apostrophe is at [apostrophe].
  void _constant(IntList out, int apostrophe) {
    final buf = _s.buffer;
    final start = _s.tokenStart;
    final end = _s.tokenEnd;
    if (apostrophe == start) _unsupported('an unsized constant');
    var size = 0;
    for (var i = start; i < apostrophe; i++) {
      final c = buf[i];
      if (c == 0x5F) continue;
      if (c < 0x30 || c > 0x39) _syntax('expected a constant');
      size = size * 10 + (c - 0x30);
      if (size > kMaxNetlistBits) _unsupported('a constant that wide');
    }
    if (size == 0) _syntax('expected a constant of at least 1 bit');
    var i = apostrophe + 1;
    if (i < end && (buf[i] == 0x73 || buf[i] == 0x53)) i++;
    if (i >= end) _syntax('expected a constant base');
    final base = buf[i++] | 0x20;
    final bitsPerDigit = switch (base) {
      0x62 => 1,
      0x6F => 3,
      0x68 => 4,
      0x64 => 0,
      _ => -1,
    };
    if (bitsPerDigit < 0) _syntax('expected a constant base');
    if (i >= end) _syntax('expected constant digits');
    final bits = IntList(32);
    if (bitsPerDigit == 0) {
      _decimalBits(i, end, size, bits);
    } else {
      var lastDigitSpecial = -1;
      for (var k = end - 1; k >= i; k--) {
        final c = buf[k];
        if (c == 0x5F) continue;
        final code = _digitCode(c, bitsPerDigit);
        if (code < 0) _syntax('expected valid constant digits');
        if (code >= 0x10) {
          for (var b = 0; b < bitsPerDigit; b++) {
            bits.add(code == 0x10 ? ConstId.unknown : ConstId.highZ);
          }
        } else {
          for (var b = 0; b < bitsPerDigit; b++) {
            bits.add((code >> b) & 1);
          }
        }
        lastDigitSpecial = code;
        if (bits.length > size + 4) break;
      }
      // Pad on the left: x or z extends, anything else zero-fills.
      final pad = lastDigitSpecial == 0x10
          ? ConstId.unknown
          : lastDigitSpecial == 0x11
          ? ConstId.highZ
          : ConstId.zero;
      while (bits.length < size) {
        bits.add(pad);
      }
    }
    while (bits.length < size) {
      bits.add(ConstId.zero);
    }
    out.addRange(bits, 0, size);
  }

  /// 0 to 15 for a digit value, 0x10 for x, 0x11 for z or '?', -1 if
  /// invalid for a base with [bitsPerDigit] bits.
  static int _digitCode(int c, int bitsPerDigit) {
    int value;
    if (c >= 0x30 && c <= 0x39) {
      value = c - 0x30;
    } else if (c >= 0x61 && c <= 0x66) {
      value = c - 0x61 + 10;
    } else if (c >= 0x41 && c <= 0x46) {
      value = c - 0x41 + 10;
    } else if (c == 0x78 || c == 0x58) {
      return 0x10;
    } else if (c == 0x7A || c == 0x5A || c == 0x3F) {
      return 0x11;
    } else {
      return -1;
    }
    return value >= (1 << bitsPerDigit) ? -1 : value;
  }

  void _decimalBits(int from, int end, int size, IntList bits) {
    final buf = _s.buffer;
    var value = 0;
    var digits = 0;
    for (var k = from; k < end; k++) {
      final c = buf[k];
      if (c == 0x5F) continue;
      if (c == 0x78 || c == 0x58 || c == 0x7A || c == 0x5A || c == 0x3F) {
        // A lone x or z fills the width.
        if (digits != 0) _unsupported('a decimal constant mixing x or z');
        for (var j = k + 1; j < end; j++) {
          if (buf[j] != 0x5F) {
            _unsupported('a decimal constant mixing x or z');
          }
        }
        final special = (c == 0x78 || c == 0x58)
            ? ConstId.unknown
            : ConstId.highZ;
        for (var b = 0; b < size; b++) {
          bits.add(special);
        }
        return;
      }
      if (c < 0x30 || c > 0x39) _syntax('expected valid constant digits');
      digits++;
      if (digits > 18) _unsupported('a decimal constant that wide');
      value = value * 10 + (c - 0x30);
    }
    if (value == 0) {
      bits.add(ConstId.zero);
      return;
    }
    while (value > 0) {
      bits.add(value & 1);
      value >>= 1;
    }
  }

  void _netReference(IntList out, {required bool implicit}) {
    final id = _s.intern(_names);
    final line = _s.line;
    final column = _s.column;
    final endColumn = _s.endColumn;
    _s.next();
    var net = _lookup(id);
    if (net < 0) {
      if (!implicit || _sym(0x5B)) {
        _inconsistent(
          'the net "${_names.stringOf(id)}" is not declared',
          line: line,
        );
      }
      net = _declare(
        id,
        0,
        0,
        DirectionCode.none,
        line: line,
        column: column,
        endColumn: endColumn,
        implicit: true,
      );
    }
    final start = _m.netStart[net];
    final width = _m.netWidth[net];
    if (!_sym(0x5B)) {
      for (var k = 0; k < width; k++) {
        out.add(start + k);
      }
      return;
    }
    _s.next();
    final first = _integer('a bit index');
    _s.next();
    final declLeft = _m.netLeft[net];
    final declRight = _m.netRight[net];
    int offsetOf(int index) {
      final offset = declLeft >= declRight
          ? index - declRight
          : declRight - index;
      if (offset < 0 || offset >= width) {
        _inconsistent(
          'a select outside "${_names.stringOf(id)}"',
          line: line,
        );
      }
      return offset;
    }

    if (_sym(0x5D)) {
      _s.next();
      out.add(start + offsetOf(first));
      return;
    }
    if (!_sym(0x3A)) {
      if (_s.kind == VerilogToken.symbol) {
        _unsupported('an indexed part select');
      }
      _syntax("expected ']' or ':'");
    }
    _s.next();
    final second = _integer('a bit index');
    _s.next();
    _expectSymbol(0x5D);
    _s.next();
    final count = (first - second).abs() + 1;
    final down = first >= second;
    if (count > 1 && down != (declLeft >= declRight)) {
      _inconsistent(
        'a part select of "${_names.stringOf(id)}" in the wrong direction',
        line: line,
      );
    }
    for (var k = 0; k < count; k++) {
      final index = down ? second + k : second - k;
      out.add(start + offsetOf(index));
    }
  }
}
