// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:typed_data';

import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/services/verilog/cell_interface.dart';
import 'package:netcrux/services/verilog/verilog_byte_source.dart';
import 'package:netcrux/services/verilog/verilog_keywords.dart';
import 'package:netcrux/services/verilog/verilog_scanner.dart';
import 'package:netcrux/services/yosys/chunked_yosys_json_reader.dart';
import 'package:netcrux/services/yosys/streaming_yosys_json_reader.dart';

/// What [readCellModelFile] found in one cell model file.
class CellModelFile {
  /// Creates the result.
  CellModelFile({required this.cells, required this.warnings});

  /// The module interfaces, in file order.
  final List<CellInterface> cells;

  /// Things worth telling the user, such as a module declared twice.
  final List<String> warnings;
}

/// Reads the port declarations of every module in a Verilog cell model file
/// and nothing else.
///
/// A vendor's simulation models are full of what a netlist viewer does not
/// need and a structural reader cannot read: user-defined primitives,
/// `specify` blocks with timing, tasks, functions, `generate`, conditional
/// compilation. Only the module header (and, for a non-ANSI header, the
/// `input`/`output`/`inout` declarations in the body) is read; everything
/// else up to `endmodule` is stepped over token by token, so none of it
/// needs to be valid for the reader. Unknown compiler directives are skipped
/// to the end of their line.
///
/// A port whose range cannot be evaluated (`[WIDTH-1:0]`) is kept with an
/// unknown width. A module header with a parameter list is read; its
/// parameters are not.
///
/// Reads plain or gzip-compressed files as a stream. Throws
/// [VerilogSourceException] when the file cannot be read and
/// [NativeReaderFallback] when its tokens are malformed.
CellModelFile readCellModelFile(
  String path, {
  CancellationToken? cancellation,
  int bufferSize = VerilogScanner.defaultBufferSize,
  int maxTokenBytes = 64 * 1024,
}) {
  final source = openVerilogSource(path);
  try {
    return _HeaderReader(
      VerilogScanner(
        source,
        path: path,
        bufferSize: bufferSize,
        maxTokenBytes: maxTokenBytes,
        lenientDirectives: true,
        cancellation: cancellation,
      ),
    ).read();
  } finally {
    source.close();
  }
}

/// Reads cell model Verilog held in memory; for tests.
CellModelFile readCellModelText(String text, {String path = '<string>'}) {
  final bytes = Uint8List.fromList(utf8.encode(text));
  return _HeaderReader(
    VerilogScanner(
      MemoryChunkSource(bytes, maxChunk: bytes.length + 1),
      path: path,
      bufferSize: 1 << 17,
      lenientDirectives: true,
    ),
  ).read();
}

class _PortDecl {
  _PortDecl(
    this.name,
    this.direction, {
    required this.msb,
    required this.lsb,
    required this.unknown,
  });

  final String name;
  PortDirection direction;
  int? msb;
  int? lsb;
  bool unknown;
}

class _HeaderReader {
  _HeaderReader(this._s) {
    VerilogKeywords.seed(_names);
  }

  final VerilogScanner _s;
  final Interner _names = Interner();
  final List<CellInterface> _cells = <CellInterface>[];
  final List<String> _warnings = <String>[];
  final Set<String> _seen = <String>{};

  CellModelFile read() {
    _next();
    while (_s.kind != VerilogToken.eof) {
      if (_isKeyword(VerilogKeywords.module) ||
          _isKeyword(VerilogKeywords.macromodule)) {
        _module();
      } else if (_isKeyword(VerilogKeywords.primitive)) {
        _skipPast(VerilogKeywords.endprimitive);
      } else {
        _next();
      }
    }
    return CellModelFile(cells: _cells, warnings: _warnings);
  }

  void _next() => _s.next();

  /// The id of the current identifier, or -1 when it is not one.
  int _id() {
    if (_s.kind != VerilogToken.identifier) return -1;
    return _s.intern(_names);
  }

  bool _isKeyword(int keyword) =>
      _s.kind == VerilogToken.identifier &&
      !_s.escaped &&
      _s.intern(_names) == keyword;

  bool _isDirection() =>
      _s.kind == VerilogToken.identifier &&
      !_s.escaped &&
      switch (_s.intern(_names)) {
        VerilogKeywords.input ||
        VerilogKeywords.output ||
        VerilogKeywords.inout => true,
        _ => false,
      };

  PortDirection _direction() => switch (_s.intern(_names)) {
    VerilogKeywords.input => PortDirection.input,
    VerilogKeywords.output => PortDirection.output,
    _ => PortDirection.inout,
  };

  void _skipPast(int endKeyword) {
    while (_s.kind != VerilogToken.eof) {
      final done = _isKeyword(endKeyword);
      _next();
      if (done) return;
    }
  }

  void _module() {
    _next();
    final nameId = _id();
    if (nameId < 0) return;
    final name = _names.stringOf(nameId);
    _next();
    if (_s.isSymbol(0x23)) {
      // '#' parameter list: step over the balanced parentheses.
      _next();
      if (_s.isSymbol(0x28)) _skipBalanced();
    }
    final headerNames = <String>[];
    final decls = <String, _PortDecl>{};
    final order = <String>[];
    var ansi = false;
    if (_s.isSymbol(0x28)) {
      _next();
      if (_isDirection()) {
        ansi = true;
        _ansiPorts(decls, order);
      } else {
        _plainPorts(headerNames);
      }
    }
    // The ';' ends the header.
    while (!_s.isSymbol(0x3B) && _s.kind != VerilogToken.eof) {
      _next();
    }
    _next();
    if (!ansi) {
      _bodyDeclarations(decls);
      order.addAll(headerNames);
    } else {
      _skipPast(VerilogKeywords.endmodule);
    }
    if (!_seen.add(name)) {
      _warnings.add('Module "$name" is defined twice in ${_s.path}.');
      return;
    }
    final ports = <CellPort>[];
    for (final portName in order) {
      final decl = decls[portName];
      if (decl == null) {
        _warnings.add(
          'Port "$portName" of "$name" in ${_s.path} has no direction '
          'declaration; it is treated as inout.',
        );
        ports.add(CellPort(name: portName, direction: PortDirection.inout));
        continue;
      }
      ports.add(
        CellPort(
          name: portName,
          direction: decl.direction,
          msb: decl.msb,
          lsb: decl.lsb,
          rangeUnknown: decl.unknown,
        ),
      );
    }
    _cells.add(CellInterface(name: name, ports: ports));
  }

  void _skipBalanced() {
    var depth = 0;
    while (_s.kind != VerilogToken.eof) {
      if (_s.isSymbol(0x28)) depth++;
      if (_s.isSymbol(0x29)) {
        depth--;
        if (depth == 0) {
          _next();
          return;
        }
      }
      _next();
    }
  }

  /// Non-ANSI header: names separated by commas, up to the closing ')'.
  void _plainPorts(List<String> names) {
    while (_s.kind != VerilogToken.eof && !_s.isSymbol(0x29)) {
      final id = _id();
      if (id >= 0) names.add(_names.stringOf(id));
      _next();
    }
    if (_s.isSymbol(0x29)) _next();
  }

  /// ANSI header, positioned at the first direction keyword.
  void _ansiPorts(Map<String, _PortDecl> decls, List<String> order) {
    var direction = PortDirection.input;
    int? msb;
    int? lsb;
    var unknown = false;
    while (_s.kind != VerilogToken.eof && !_s.isSymbol(0x29)) {
      if (_isDirection()) {
        direction = _direction();
        msb = lsb = null;
        unknown = false;
        _next();
        continue;
      }
      if (_s.isSymbol(0x5B)) {
        (msb, lsb, unknown) = _range();
        continue;
      }
      final id = _id();
      if (id >= 0 && !_isTypeWord(id)) {
        final name = _names.stringOf(id);
        decls[name] = _PortDecl(
          name,
          direction,
          msb: msb,
          lsb: lsb,
          unknown: unknown,
        );
        order.add(name);
      }
      _next();
    }
    if (_s.isSymbol(0x29)) _next();
  }

  bool _isTypeWord(int id) =>
      !_s.escaped &&
      switch (id) {
        VerilogKeywords.wire ||
        VerilogKeywords.tri ||
        VerilogKeywords.reg ||
        VerilogKeywords.logic ||
        VerilogKeywords.signed ||
        VerilogKeywords.unsigned ||
        VerilogKeywords.variable => true,
        _ => false,
      };

  /// Reads `[a:b]` at the current '[' and moves past the ']'. The bounds
  /// are unknown unless the brackets hold exactly two integers.
  (int?, int?, bool) _range() {
    _next();
    final numbers = <int>[];
    var simple = true;
    var colons = 0;
    while (_s.kind != VerilogToken.eof && !_s.isSymbol(0x5D)) {
      if (_s.kind == VerilogToken.number) {
        final value = int.tryParse(_s.text);
        if (value == null) {
          simple = false;
        } else {
          numbers.add(value);
        }
      } else if (_s.isSymbol(0x3A)) {
        colons++;
      } else {
        simple = false;
      }
      _next();
    }
    if (_s.isSymbol(0x5D)) _next();
    if (simple && numbers.length == 2 && colons == 1) {
      return (numbers[0], numbers[1], false);
    }
    return (null, null, true);
  }

  /// Non-ANSI body: the `input`/`output`/`inout` statements until
  /// `endmodule`, stepping over blocks that may contain look-alikes.
  void _bodyDeclarations(Map<String, _PortDecl> decls) {
    while (_s.kind != VerilogToken.eof) {
      if (_isKeyword(VerilogKeywords.endmodule)) {
        _next();
        return;
      }
      if (_isKeyword(VerilogKeywords.function)) {
        _skipPast(VerilogKeywords.endfunction);
      } else if (_isKeyword(VerilogKeywords.task)) {
        _skipPast(VerilogKeywords.endtask);
      } else if (_isKeyword(VerilogKeywords.specify)) {
        _skipPast(VerilogKeywords.endspecify);
      } else if (_isKeyword(VerilogKeywords.table)) {
        _skipPast(VerilogKeywords.endtable);
      } else if (_isKeyword(VerilogKeywords.generate)) {
        _skipPast(VerilogKeywords.endgenerate);
      } else if (_isDirection()) {
        _directionStatement(decls);
      } else {
        _next();
      }
    }
  }

  void _directionStatement(Map<String, _PortDecl> decls) {
    final direction = _direction();
    int? msb;
    int? lsb;
    var unknown = false;
    _next();
    while (_s.kind != VerilogToken.eof && !_s.isSymbol(0x3B)) {
      if (_s.isSymbol(0x5B)) {
        (msb, lsb, unknown) = _range();
        continue;
      }
      final id = _id();
      if (id >= 0 && !_isTypeWord(id)) {
        final name = _names.stringOf(id);
        decls[name] = _PortDecl(
          name,
          direction,
          msb: msb,
          lsb: lsb,
          unknown: unknown,
        );
      }
      _next();
    }
    if (_s.isSymbol(0x3B)) _next();
  }
}
