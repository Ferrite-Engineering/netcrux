// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:netcrux/services/liberty/liberty_library.dart';

/// Reads the cell interfaces out of a Liberty (`.lib`) file: each cell's
/// name and its ports, with directions and bus widths. Nothing else.
///
/// A standard-cell Liberty file runs to hundreds of megabytes, nearly all
/// of it timing and power tables. The reader is a single forward pass over
/// the bytes, read through a fixed buffer, and never builds a syntax tree:
/// it parses statements only inside the groups it needs (`library`, `cell`,
/// `type`, `pin`, `pg_pin`, `bus`, `bundle`) and steps over every other
/// group by counting braces, which is where it spends almost all its time.
/// Memory stays at the buffer plus the cells found.
///
/// What it understands:
///
/// - `pin(A)` and `pin(A, B)` with `direction : input | output | inout`;
///   `internal` pins are left out, and a pin with no direction is `inout`.
/// - `pg_pin(VDD)` as an `inout` port, so RTL that wires power and ground
///   still connects.
/// - `bus(D)` with `bus_type`, resolved through a `type(NAME)` group (in
///   the library or the cell) to a vector `[bit_from:bit_to]`. The `pin`
///   groups inside a bus belong to it. With no usable type the range comes
///   from those pins' indices.
/// - `bundle(Q)` with `members(Q0, Q1)`: each member is a scalar port.
/// - `/* */` and `//` comments, quoted strings, backslash line
///   continuations, simple (`name : value ;`) and complex (`name(args);`)
///   attributes, with or without the closing semicolon.
/// - A gzip-compressed file (`.lib.gz`, `.liberty.gz`), inflated as it is
///   read through the same buffer: the decompressed text is never held,
///   so a compressed library costs the same memory as a plain one.
///
/// Runs synchronously; callers keep it off the UI isolate (see
/// `LibertyStubService`).
class LibertyParser {
  LibertyParser._(this._lexer, this._path);

  /// Parses the Liberty file at [path], plain or gzip-compressed.
  ///
  /// A file that starts with the gzip magic number is inflated as a stream,
  /// whatever its name; one that does not is read as text, so a plain file
  /// named `.gz` still parses. Line numbers in a problem report refer to the
  /// decompressed text.
  ///
  /// Throws [LibertyParseException] for a file that cannot be opened or
  /// is not well-formed Liberty.
  static LibertyLibrary parseFile(String path, {int bufferSize = 1 << 20}) {
    final RandomAccessFile file;
    try {
      file = File(path).openSync();
    } on FileSystemException catch (e) {
      throw LibertyParseException(
        path,
        'cannot be opened: ${e.osError?.message ?? e.message}',
      );
    }
    try {
      final source = _isGzip(file) ? _GzipSource(file) : _FileSource(file);
      final lexer = _Lexer(path, Uint8List(bufferSize), 0, source);
      return LibertyParser._(lexer, path)._parse();
    } on FileSystemException catch (e) {
      throw LibertyParseException(
        path,
        'cannot be read: ${e.osError?.message ?? e.message}',
      );
    } on FormatException catch (e) {
      throw LibertyParseException(
        path,
        'is not valid gzip data: ${e.message}',
      );
    } finally {
      file.closeSync();
    }
  }

  /// Parses Liberty [text] held in memory, reporting problems against
  /// [path]. For tests and small inputs.
  static LibertyLibrary parseString(String text, {String path = '<string>'}) {
    final bytes = Uint8List.fromList(utf8.encode(text));
    return LibertyParser._(
      _Lexer(path, bytes, bytes.length, null),
      path,
    )._parse();
  }

  final _Lexer _lexer;
  final String _path;
  final List<String> _warnings = <String>[];

  LibertyLibrary _parse() {
    final cells = <LibertyCell>[];
    final seen = <String>{};
    var sawLibrary = false;
    while (true) {
      final token = _lexer.next();
      if (token.kind == _Kind.eof) break;
      final statement = _statement(token);
      if (statement is! _Group) continue;
      if (statement.name == 'library') {
        sawLibrary = true;
        for (final cell in _library()) {
          if (seen.add(cell.name)) {
            cells.add(cell);
          } else {
            _warnings.add(
              'Cell "${cell.name}" is declared more than once in $_path; '
              'the first declaration is used.',
            );
          }
        }
      } else {
        _lexer.skipGroupBody(statement.name, statement.line);
      }
    }
    if (!sawLibrary) {
      throw LibertyParseException(
        _path,
        'no library(...) group found; is this a Liberty file?',
      );
    }
    return LibertyLibrary(path: _path, cells: cells, warnings: _warnings);
  }

  /// Reads a `library` body (its `{` already consumed) and returns its
  /// cells with every bus resolved against the library's types.
  List<LibertyCell> _library() {
    final types = <String, _BusType>{};
    final raw = <_RawCell>[];
    _body('library', (group) {
      switch (group.name) {
        case 'cell':
          raw.add(_cell(group));
        case 'type':
          final type = _type();
          if (group.args.isNotEmpty) types[group.args.first] = type;
        default:
          _lexer.skipGroupBody(group.name, group.line);
      }
    });
    return <LibertyCell>[for (final cell in raw) _resolve(cell, types)];
  }

  _RawCell _cell(_Group group) {
    final cell = _RawCell(
      group.args.isEmpty ? '' : group.args.first,
      group.line,
    );
    _body('cell', (child) {
      switch (child.name) {
        case 'pin':
          final pin = _pin('pin');
          for (final name in child.args) {
            cell.addScalar(name, pin.direction);
          }
        case 'pg_pin':
          _lexer.skipGroupBody(child.name, child.line);
          for (final name in child.args) {
            cell.addScalar(name, 'inout');
          }
        case 'bus':
          final bus = _bus();
          for (final name in child.args) {
            cell.addBus(name, bus);
          }
        case 'bundle':
          final bundle = _bundle();
          for (final member in bundle.members) {
            cell.addScalar(
              member,
              bundle.memberDirections[member] ?? bundle.direction,
            );
          }
        case 'type':
          final type = _type();
          if (child.args.isNotEmpty) cell.types[child.args.first] = type;
        default:
          _lexer.skipGroupBody(child.name, child.line);
      }
    });
    if (cell.name.isEmpty) {
      throw LibertyParseException(
        _path,
        'cell group without a name',
        line: group.line,
      );
    }
    return cell;
  }

  /// Reads a `pin` body. Only `direction` matters.
  _Pin _pin(String what) {
    String? direction;
    _body(
      what,
      (group) => _lexer.skipGroupBody(group.name, group.line),
      onSimple: (name, value) {
        if (name == 'direction') direction = value.toLowerCase();
      },
    );
    return _Pin(direction);
  }

  _Bus _bus() {
    final bus = _Bus();
    _body(
      'bus',
      (group) {
        if (group.name == 'pin') {
          final pin = _pin('pin');
          bus.pinNames.addAll(group.args);
          bus.pinDirection ??= pin.direction;
        } else {
          _lexer.skipGroupBody(group.name, group.line);
        }
      },
      onSimple: (name, value) {
        if (name == 'bus_type') bus.typeName = value;
        if (name == 'direction') bus.direction = value.toLowerCase();
      },
    );
    return bus;
  }

  _Bundle _bundle() {
    final bundle = _Bundle();
    _body(
      'bundle',
      (group) {
        if (group.name == 'pin') {
          final pin = _pin('pin');
          for (final name in group.args) {
            if (pin.direction != null) {
              bundle.memberDirections[name] = pin.direction!;
            }
          }
        } else {
          _lexer.skipGroupBody(group.name, group.line);
        }
      },
      onSimple: (name, value) {
        if (name == 'direction') bundle.direction = value.toLowerCase();
      },
      onComplex: (name, args) {
        if (name == 'members') bundle.members.addAll(args);
      },
    );
    return bundle;
  }

  _BusType _type() {
    final type = _BusType();
    _body(
      'type',
      (group) => _lexer.skipGroupBody(group.name, group.line),
      onSimple: (name, value) {
        switch (name) {
          case 'bit_from':
            type.from = int.tryParse(value);
          case 'bit_to':
            type.to = int.tryParse(value);
          case 'bit_width':
            type.width = int.tryParse(value);
          case 'downto':
            type.downto = value.toLowerCase() == 'true';
        }
      },
    );
    return type;
  }

  /// Parses statements up to the closing `}` of the group named [what],
  /// whose `{` has been consumed. Nested groups go to [onGroup], which
  /// must consume them (parse or skip); attributes go to [onSimple] and
  /// [onComplex].
  void _body(
    String what,
    void Function(_Group group) onGroup, {
    void Function(String name, String value)? onSimple,
    void Function(String name, List<String> args)? onComplex,
  }) {
    final start = _lexer.line;
    while (true) {
      final token = _lexer.next();
      if (token.kind == _Kind.rbrace) return;
      if (token.kind == _Kind.eof) {
        throw LibertyParseException(
          _path,
          'the $what group that starts on line $start is never closed',
          line: _lexer.line,
        );
      }
      final statement = _statement(token);
      switch (statement) {
        case _Group():
          onGroup(statement);
        case _Simple():
          onSimple?.call(statement.name, statement.value);
        case _Complex():
          onComplex?.call(statement.name, statement.args);
        case null:
          break;
      }
    }
  }

  /// Parses one statement starting at [first]. Returns `null` for a stray
  /// semicolon. A returned [_Group] has had its `{` consumed and its body
  /// not yet read.
  _Statement? _statement(_Token first) {
    if (first.kind == _Kind.semicolon) return null;
    if (first.kind != _Kind.word) {
      throw LibertyParseException(
        _path,
        'expected an attribute or group name, found ${first.describe()}',
        line: first.line,
      );
    }
    final name = first.text;
    final next = _lexer.next();
    switch (next.kind) {
      case _Kind.colon:
        return _Simple(name, _simpleValue(name, first.line));
      case _Kind.lparen:
        final args = _args(name, first.line);
        final after = _lexer.next();
        if (after.kind == _Kind.lbrace) return _Group(name, args, first.line);
        if (after.kind != _Kind.semicolon) _lexer.pushBack(after);
        return _Complex(name, args);
      case _Kind.word ||
          _Kind.string ||
          _Kind.rparen ||
          _Kind.lbrace ||
          _Kind.rbrace ||
          _Kind.semicolon ||
          _Kind.comma ||
          _Kind.eof:
        throw LibertyParseException(
          _path,
          'expected ":" or "(" after "$name", found ${next.describe()}',
          line: next.line,
        );
    }
  }

  /// The value of a simple attribute: the tokens up to `;`, or up to the
  /// end of the line when the semicolon is left off.
  String _simpleValue(String name, int line) {
    final parts = <String>[];
    while (true) {
      final token = _lexer.next();
      switch (token.kind) {
        case _Kind.semicolon:
          return parts.join(' ');
        case _Kind.word ||
            _Kind.string ||
            _Kind.lparen ||
            _Kind.rparen ||
            _Kind.colon ||
            _Kind.comma:
          if (token.newlineBefore && parts.isNotEmpty) {
            _lexer.pushBack(token);
            return parts.join(' ');
          }
          parts.add(token.text);
        case _Kind.rbrace || _Kind.eof:
          _lexer.pushBack(token);
          return parts.join(' ');
        case _Kind.lbrace:
          throw LibertyParseException(
            _path,
            'unexpected ${token.describe()} in the value of "$name"',
            line: token.line,
          );
      }
    }
  }

  /// The arguments of a group or complex attribute, up to `)`. Commas and
  /// whitespace both separate them.
  List<String> _args(String name, int line) {
    final args = <String>[];
    while (true) {
      final token = _lexer.next();
      switch (token.kind) {
        case _Kind.rparen:
          return args;
        case _Kind.word || _Kind.string:
          args.add(token.text);
        case _Kind.comma || _Kind.colon:
          break;
        case _Kind.lparen ||
            _Kind.lbrace ||
            _Kind.rbrace ||
            _Kind.semicolon ||
            _Kind.eof:
          throw LibertyParseException(
            _path,
            'unexpected ${token.describe()} in the arguments of "$name" '
            '(opened on line $line)',
            line: token.line,
          );
      }
    }
  }

  LibertyCell _resolve(_RawCell raw, Map<String, _BusType> libraryTypes) {
    final ports = <LibertyPort>[];
    for (final port in raw.ports) {
      final direction = _direction(port.direction, raw.name, port.name);
      if (direction == null) continue;
      final bus = port.bus;
      if (bus == null) {
        ports.add(LibertyPort(name: port.name, direction: direction));
        continue;
      }
      final range = _range(bus, raw, libraryTypes);
      if (range == null) {
        _warnings.add(
          'Bus "${port.name}" of cell "${raw.name}" has no bus_type range '
          'NetCrux can resolve; it is declared as a single bit.',
        );
        ports.add(LibertyPort(name: port.name, direction: direction));
      } else {
        ports.add(
          LibertyPort(
            name: port.name,
            direction: direction,
            msb: range.$1,
            lsb: range.$2,
          ),
        );
      }
    }
    return LibertyCell(name: raw.name, ports: ports);
  }

  /// Maps a Liberty direction to a port direction; `null` drops the pin.
  LibertyPortDirection? _direction(String? value, String cell, String pin) {
    switch (value) {
      case 'input':
        return LibertyPortDirection.input;
      case 'output':
        return LibertyPortDirection.output;
      case 'inout' || null:
        return LibertyPortDirection.inout;
      case 'internal':
        return null;
      default:
        _warnings.add(
          'Pin "$pin" of cell "$cell" has the unknown direction "$value"; '
          'it is declared inout.',
        );
        return LibertyPortDirection.inout;
    }
  }

  /// The `[msb:lsb]` of [bus]: from its `bus_type` (cell types shadow
  /// library types), else from the indices of its member pins.
  (int, int)? _range(
    _Bus bus,
    _RawCell cell,
    Map<String, _BusType> libraryTypes,
  ) {
    final typeName = bus.typeName;
    final type = typeName == null
        ? null
        : cell.types[typeName] ?? libraryTypes[typeName];
    final fromType = type?.range;
    if (fromType != null) return fromType;
    int? low;
    int? high;
    for (final name in bus.pinNames) {
      final match = _indexPattern.firstMatch(name);
      if (match == null) continue;
      for (final group in <String?>[match.group(1), match.group(2)]) {
        if (group == null) continue;
        final index = int.parse(group);
        low = low == null || index < low ? index : low;
        high = high == null || index > high ? index : high;
      }
    }
    if (low == null || high == null) return null;
    return (high, low);
  }

  static final RegExp _indexPattern = RegExp(r'\[(\d+)(?::(\d+))?\]$');
}

// ---------------------------------------------------------------------------
// Parse-time records
// ---------------------------------------------------------------------------

sealed class _Statement {}

final class _Group extends _Statement {
  _Group(this.name, this.args, this.line);
  final String name;
  final List<String> args;
  final int line;
}

final class _Simple extends _Statement {
  _Simple(this.name, this.value);
  final String name;
  final String value;
}

final class _Complex extends _Statement {
  _Complex(this.name, this.args);
  final String name;
  final List<String> args;
}

class _Pin {
  _Pin(this.direction);
  final String? direction;
}

class _Bus {
  String? typeName;
  String? direction;
  String? pinDirection;
  final List<String> pinNames = <String>[];
}

class _Bundle {
  String? direction;
  final List<String> members = <String>[];
  final Map<String, String> memberDirections = <String, String>{};
}

class _BusType {
  int? from;
  int? to;
  int? width;
  bool downto = false;

  (int, int)? get range {
    if (from != null && to != null) return (from!, to!);
    final w = width;
    if (w == null || w < 1) return null;
    final start = from;
    if (start != null) {
      return downto ? (start, start - w + 1) : (start, start + w - 1);
    }
    return downto ? (w - 1, 0) : (0, w - 1);
  }
}

class _RawPort {
  _RawPort(this.name, this.direction, this.bus);
  final String name;
  final String? direction;
  final _Bus? bus;
}

class _RawCell {
  _RawCell(this.name, this.line);
  final String name;
  final int line;
  final List<_RawPort> ports = <_RawPort>[];
  final Set<String> _names = <String>{};
  final Map<String, _BusType> types = <String, _BusType>{};

  void addScalar(String name, String? direction) {
    if (_names.add(name)) ports.add(_RawPort(name, direction, null));
  }

  void addBus(String name, _Bus bus) {
    if (_names.add(name)) {
      ports.add(_RawPort(name, bus.direction ?? bus.pinDirection, bus));
    }
  }
}

// ---------------------------------------------------------------------------
// Lexer
// ---------------------------------------------------------------------------

enum _Kind {
  word,
  string,
  lparen,
  rparen,
  lbrace,
  rbrace,
  colon,
  semicolon,
  comma,
  eof,
}

class _Token {
  const _Token(this.kind, this.text, this.line, {this.newlineBefore = false});
  final _Kind kind;
  final String text;
  final int line;

  /// Whether a line break separates this token from the previous one (a
  /// backslash continuation does not count). Ends a simple attribute whose
  /// semicolon was left off.
  final bool newlineBefore;

  String describe() => switch (kind) {
    _Kind.word => '"$text"',
    _Kind.string => 'the string "$text"',
    _Kind.eof => 'the end of the file',
    _ => '"$text"',
  };
}

const int _lf = 0x0A;
const int _cr = 0x0D;
const int _quote = 0x22;
const int _lparenChar = 0x28;
const int _rparenChar = 0x29;
const int _star = 0x2A;
const int _commaChar = 0x2C;
const int _slash = 0x2F;
const int _colonChar = 0x3A;
const int _semicolonChar = 0x3B;
const int _lbracket = 0x5B;
const int _backslash = 0x5C;
const int _rbracket = 0x5D;
const int _lbraceChar = 0x7B;
const int _rbraceChar = 0x7D;

bool _isSpace(int c) => c == 0x20 || c == 0x09 || c == _lf || c == _cr;

bool _isDelimiter(int c) =>
    _isSpace(c) ||
    c == _quote ||
    c == _lparenChar ||
    c == _rparenChar ||
    c == _commaChar ||
    c == _colonChar ||
    c == _semicolonChar ||
    c == _lbraceChar ||
    c == _rbraceChar;

/// Where the lexer's bytes come from: it asks for the next block when its
/// buffer runs dry.
abstract interface class _ByteSource {
  /// Fills the start of [buffer] with the next bytes and returns how many,
  /// `0` at the end of the input.
  int readInto(Uint8List buffer);
}

/// The bytes of the file as they are on disk.
class _FileSource implements _ByteSource {
  _FileSource(this._file);

  final RandomAccessFile _file;

  @override
  int readInto(Uint8List buffer) => _file.readIntoSync(buffer);
}

/// Whether the open [file] starts with the gzip magic number, leaving its
/// position at the start.
bool _isGzip(RandomAccessFile file) {
  final head = file.readSync(2);
  file.setPositionSync(0);
  return head.length == 2 && head[0] == 0x1f && head[1] == 0x8b;
}

/// The inflated bytes of a gzip file, produced a block at a time.
///
/// The decoder is driven synchronously (a block of compressed bytes goes in
/// and its output is queued before `add` returns), which is what lets the
/// lexer, a synchronous reader, pull from it without an isolate of its own
/// or the whole file in memory. A truncated or corrupt stream surfaces as a
/// [FormatException] from [readInto].
class _GzipSource implements _ByteSource {
  _GzipSource(this._file) {
    _sink = gzip.decoder.startChunkedConversion(_QueueSink(_inflated));
  }

  final RandomAccessFile _file;
  final Uint8List _compressed = Uint8List(1 << 16);
  final Queue<Uint8List> _inflated = Queue<Uint8List>();
  late final ByteConversionSink _sink;
  int _offset = 0;
  bool _finished = false;

  @override
  int readInto(Uint8List buffer) {
    // Refill from disk until there is inflated output or the file is done.
    while (_inflated.isEmpty && !_finished) {
      final n = _file.readIntoSync(_compressed);
      if (n == 0) {
        _finished = true;
        _sink.close();
      } else {
        _sink.add(Uint8List.sublistView(_compressed, 0, n));
      }
    }
    var written = 0;
    while (written < buffer.length && _inflated.isNotEmpty) {
      final chunk = _inflated.first;
      final take = (chunk.length - _offset).clamp(0, buffer.length - written);
      buffer.setRange(written, written + take, chunk, _offset);
      written += take;
      _offset += take;
      if (_offset == chunk.length) {
        _inflated.removeFirst();
        _offset = 0;
      }
    }
    return written;
  }
}

/// Collects a decoder's output blocks, each copied so the decoder is free
/// to reuse its own.
class _QueueSink implements Sink<List<int>> {
  _QueueSink(this._queue);

  final Queue<Uint8List> _queue;

  @override
  void add(List<int> data) => _queue.add(Uint8List.fromList(data));

  @override
  void close() {}
}

/// A byte-level tokenizer reading through a fixed buffer, refilled from
/// [_source] when it runs dry (or holding all the input when [_source] is
/// `null`).
class _Lexer {
  _Lexer(this._path, this._buf, this._len, this._source);

  final String _path;
  final Uint8List _buf;
  final _ByteSource? _source;
  int _len;
  int _pos = 0;

  /// The current 1-based line.
  int line = 1;

  _Token? _pushed;

  void pushBack(_Token token) {
    assert(_pushed == null, 'one token of push-back');
    _pushed = token;
  }

  /// Refills the buffer. `false` at the end of the input.
  bool _fill() {
    final source = _source;
    if (source == null) return false;
    _len = source.readInto(_buf);
    _pos = 0;
    return _len > 0;
  }

  /// The next byte without consuming it, or -1 at the end.
  int _peek() {
    if (_pos >= _len && !_fill()) return -1;
    return _buf[_pos];
  }

  /// Consumes and returns the next byte, or -1 at the end.
  int _read() {
    if (_pos >= _len && !_fill()) return -1;
    return _buf[_pos++];
  }

  _Token next() {
    final pushed = _pushed;
    if (pushed != null) {
      _pushed = null;
      return pushed;
    }
    var newline = false;
    while (true) {
      final c = _peek();
      if (c == -1) return _Token(_Kind.eof, '', line, newlineBefore: newline);
      if (c == _lf) {
        _pos++;
        line++;
        newline = true;
      } else if (_isSpace(c)) {
        _pos++;
      } else if (c == _backslash) {
        // A backslash before the end of a line continues the line.
        _pos++;
        final n = _peek();
        if (n == _lf || n == _cr) {
          if (n == _cr) {
            _pos++;
            if (_peek() == _lf) _pos++;
          } else {
            _pos++;
          }
          line++;
          continue;
        }
        return _word(<int>[_backslash], newline);
      } else if (c == _slash) {
        _pos++;
        final n = _peek();
        if (n == _star) {
          _pos++;
          _skipBlockComment();
        } else if (n == _slash) {
          _pos++;
          _skipLineComment();
        } else {
          return _word(<int>[_slash], newline);
        }
      } else {
        break;
      }
    }
    final c = _read();
    final at = line;
    switch (c) {
      case _quote:
        return _Token(_Kind.string, _string(), at, newlineBefore: newline);
      case _lparenChar:
        return _Token(_Kind.lparen, '(', at, newlineBefore: newline);
      case _rparenChar:
        return _Token(_Kind.rparen, ')', at, newlineBefore: newline);
      case _lbraceChar:
        return _Token(_Kind.lbrace, '{', at, newlineBefore: newline);
      case _rbraceChar:
        return _Token(_Kind.rbrace, '}', at, newlineBefore: newline);
      case _colonChar:
        return _Token(_Kind.colon, ':', at, newlineBefore: newline);
      case _semicolonChar:
        return _Token(_Kind.semicolon, ';', at, newlineBefore: newline);
      case _commaChar:
        return _Token(_Kind.comma, ',', at, newlineBefore: newline);
      default:
        return _word(<int>[c], newline);
    }
  }

  _Token _word(List<int> bytes, bool newline) {
    final at = line;
    // A colon inside brackets is part of a bit range (`D[0:3]`), not the
    // separator of a simple attribute.
    var inBrackets = bytes.contains(_lbracket) && !bytes.contains(_rbracket);
    while (true) {
      final c = _peek();
      if (c == -1) break;
      if (_isDelimiter(c) && !(inBrackets && c == _colonChar)) break;
      _pos++;
      if (c == _slash) {
        // A comment can start right after a word: `A/* x */`. The peek may
        // refill the buffer, so the slash is consumed first and the comment
        // finished here rather than handed back.
        final n = _peek();
        if (n == _star) {
          _pos++;
          _skipBlockComment();
          break;
        }
        if (n == _slash) {
          _pos++;
          _skipLineComment();
          break;
        }
      }
      if (c == _lbracket) inBrackets = true;
      if (c == _rbracket) inBrackets = false;
      bytes.add(c);
    }
    return _Token(
      _Kind.word,
      utf8.decode(bytes, allowMalformed: true),
      at,
      newlineBefore: newline,
    );
  }

  /// Reads a string body after its opening quote. A backslash escapes the
  /// next byte, which makes a backslash-newline inside a string a
  /// continuation.
  String _string() {
    final start = line;
    final bytes = <int>[];
    while (true) {
      final c = _read();
      if (c == -1) {
        throw LibertyParseException(
          _path,
          'the string that starts on line $start is never closed',
          line: line,
        );
      }
      if (c == _quote) break;
      if (c == _backslash) {
        final n = _read();
        if (n == -1) continue;
        if (n == _lf) {
          line++;
          continue;
        }
        if (n == _cr) {
          if (_peek() == _lf) _pos++;
          line++;
          continue;
        }
        bytes.add(n);
        continue;
      }
      if (c == _lf) line++;
      bytes.add(c);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  void _skipBlockComment() {
    final start = line;
    var star = false;
    while (true) {
      final c = _read();
      if (c == -1) {
        throw LibertyParseException(
          _path,
          'the comment that starts on line $start is never closed',
          line: line,
        );
      }
      if (c == _lf) line++;
      if (star && c == _slash) return;
      star = c == _star;
    }
  }

  void _skipLineComment() {
    while (true) {
      final c = _peek();
      if (c == -1 || c == _lf) return;
      _pos++;
    }
  }

  /// Steps over the rest of a group whose `{` was consumed, through its
  /// matching `}`, without tokenizing: the hot path for timing and power
  /// tables. Strings and comments are honoured so a brace inside one does
  /// not count.
  void skipGroupBody(String what, int startLine) {
    // Groups are skipped straight after their `{`, never with a token
    // pushed back.
    assert(_pushed == null, 'no push-back across a skipped group');
    var depth = 1;
    outer:
    while (true) {
      if (_pos >= _len && !_fill()) {
        throw LibertyParseException(
          _path,
          'the $what group that starts on line $startLine is never closed',
          line: line,
        );
      }
      final buf = _buf;
      final len = _len;
      var pos = _pos;
      // Scan the buffered bytes in a local loop; leave it only for the
      // rare bytes that need more than a comparison.
      while (pos < len) {
        final c = buf[pos++];
        if (c == _lf) {
          line++;
        } else if (c == _lbraceChar) {
          depth++;
        } else if (c == _rbraceChar) {
          if (--depth == 0) {
            _pos = pos;
            return;
          }
        } else if (c == _quote) {
          _pos = pos;
          _string();
          continue outer;
        } else if (c == _slash) {
          _pos = pos;
          final n = _peek();
          if (n == _star) {
            _pos++;
            _skipBlockComment();
          } else if (n == _slash) {
            _pos++;
            _skipLineComment();
          }
          continue outer;
        }
      }
      _pos = pos;
    }
  }
}
