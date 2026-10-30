// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:typed_data';

import 'package:netcrux/services/yosys/chunked_yosys_json_reader.dart';
import 'package:netcrux/services/yosys/streaming_yosys_json_reader.dart';

/// Why the native gate-level reader stopped reading a file.
enum NativeReaderStop {
  /// The input uses a Verilog construct the reader does not handle (an
  /// `always` block, an expression, a parameter override). The file may be
  /// valid; the Yosys route reads it.
  unsupported,

  /// The input is not well-formed Verilog, or is truncated, or a token is
  /// absurdly long. The Yosys route reports it in its own words.
  malformed,

  /// The input is structurally what the reader handles but is inconsistent
  /// (a module defined twice, an instance named twice, a bit tied to both
  /// 0 and 1). The Yosys route decides what that means.
  inconsistent,
}

/// Thrown by the native gate-level reader when it cannot read its input
/// faithfully. It is a request to use the Yosys route, never a failure of
/// the design: [message] names the construct, and [path] and [line] say
/// where, for the Diagnostics line.
class NativeReaderFallback implements Exception {
  /// Creates the exception. [line] is 1-based, or `0` when there is none.
  const NativeReaderFallback(
    this.stop,
    this.message, {
    required this.path,
    this.line = 0,
  });

  /// The class of problem.
  final NativeReaderStop stop;

  /// What the reader met, in English, for example `always block`.
  final String message;

  /// The file the reader was in.
  final String path;

  /// The 1-based line, or `0`.
  final int line;

  @override
  String toString() =>
      'NativeReaderFallback(${stop.name}): $path:${line == 0 ? '' : line}: '
      '$message';
}

/// Token kinds a [VerilogScanner] produces.
abstract final class VerilogToken {
  /// The end of the input.
  static const int eof = 0;

  /// An identifier, plain or escaped (the escaped form's backslash and
  /// terminating white space are not part of the token).
  static const int identifier = 1;

  /// A number: an unsigned decimal integer or a sized or based constant.
  static const int number = 2;

  /// A one-character punctuation mark, in [VerilogScanner.symbol].
  static const int symbol = 3;

  /// A double-quoted string.
  static const int string = 4;

  /// A `$name` system identifier.
  static const int system = 5;
}

/// Interns identifier bytes: the same bytes always give the same small
/// integer, and the text is only turned into a [String] when asked for.
///
/// A netlist repeats the same cell type and pin names millions of times;
/// looking each one up in the read buffer, without allocating, is what keeps
/// the reader's memory to the model it builds.
final class Interner {
  /// Creates an empty interner.
  Interner() {
    _slots = Int32List(_slotCount);
  }

  static const int _initialIds = 1024;
  static const int _slotCount = 4096;

  late Int32List _slots;
  Int32List _hashes = Int32List(_initialIds);
  Int32List _offsets = Int32List(_initialIds);
  Int32List _lengths = Int32List(_initialIds);
  Uint8List _arena = Uint8List(1 << 16);
  int _arenaLength = 0;
  int _count = 0;
  final List<String?> _strings = <String?>[];

  /// How many distinct names have been interned.
  int get length => _count;

  /// The id of the bytes `buf[start, end)` whose hash is [hash], adding them
  /// when new.
  int intern(Uint8List buf, int start, int end, int hash) {
    final length = end - start;
    final mask = _slots.length - 1;
    var slot = hash & mask;
    while (true) {
      final entry = _slots[slot];
      if (entry == 0) break;
      final id = entry - 1;
      if (_hashes[id] == hash && _lengths[id] == length) {
        final offset = _offsets[id];
        var same = true;
        final arena = _arena;
        for (var k = 0; k < length; k++) {
          if (arena[offset + k] != buf[start + k]) {
            same = false;
            break;
          }
        }
        if (same) return id;
      }
      slot = (slot + 1) & mask;
    }
    final id = _count++;
    if (id >= _hashes.length) _growIds();
    _hashes[id] = hash;
    _offsets[id] = _arenaLength;
    _lengths[id] = length;
    if (_arenaLength + length > _arena.length) {
      var size = _arena.length * 2;
      while (size < _arenaLength + length) {
        size *= 2;
      }
      _arena = Uint8List(size)..setRange(0, _arenaLength, _arena);
    }
    _arena.setRange(_arenaLength, _arenaLength + length, buf, start);
    _arenaLength += length;
    _strings.add(null);
    _slots[slot] = id + 1;
    if (_count * 2 > _slots.length) _rehash();
    return id;
  }

  /// The id of [text], adding it when new.
  int internString(String text) {
    final bytes = Uint8List.fromList(utf8.encode(text));
    return intern(bytes, 0, bytes.length, hashBytes(bytes, 0, bytes.length));
  }

  /// The FNV-1a hash the scanner computes over `buf[start, end)`, reduced
  /// to 31 bits.
  static int hashBytes(Uint8List buf, int start, int end) {
    var h = _fnvOffset;
    for (var i = start; i < end; i++) {
      h = ((h ^ buf[i]) * _fnvPrime) & _hashMask;
    }
    return h;
  }

  /// The text of [id].
  String stringOf(int id) {
    final cached = _strings[id];
    if (cached != null) return cached;
    final offset = _offsets[id];
    final end = offset + _lengths[id];
    var ascii = true;
    for (var i = offset; i < end; i++) {
      if (_arena[i] >= 0x80) {
        ascii = false;
        break;
      }
    }
    final text = ascii
        ? String.fromCharCodes(Uint8List.sublistView(_arena, offset, end))
        : utf8.decode(
            Uint8List.sublistView(_arena, offset, end),
            allowMalformed: true,
          );
    _strings[id] = text;
    return text;
  }

  void _growIds() {
    final size = _hashes.length * 2;
    _hashes = Int32List(size)..setRange(0, _hashes.length, _hashes);
    _offsets = Int32List(size)..setRange(0, _offsets.length, _offsets);
    _lengths = Int32List(size)..setRange(0, _lengths.length, _lengths);
  }

  void _rehash() {
    final size = _slots.length * 2;
    final slots = Int32List(size);
    final mask = size - 1;
    for (var id = 0; id < _count; id++) {
      var slot = _hashes[id] & mask;
      while (slots[slot] != 0) {
        slot = (slot + 1) & mask;
      }
      slots[slot] = id + 1;
    }
    _slots = slots;
  }

  static const int _fnvOffset = 0x811c9dc5;
  static const int _fnvPrime = 0x01000193;
  static const int _hashMask = 0x7fffffff;
}

/// A byte-level tokenizer for structural Verilog, reading through a fixed
/// buffer refilled from a [ByteChunkSource].
///
/// It is a pull scanner with no per-token allocation: [next] advances to the
/// next token and the token's kind, bytes, hash and position are fields. The
/// bytes of the current token (`buffer[tokenStart, tokenEnd)`) stay valid
/// until the next call to [next]. Comments, attributes (`(* ... *)`), and the
/// directives `timescale, `celldefine, `endcelldefine, `resetall and
/// `default_nettype wire are skipped as white space; any other directive is
/// a [NativeReaderFallback] unless [lenientDirectives] is set.
///
/// Line and column are 1-based, columns in bytes, as Yosys counts them, and
/// the end column is one past the token's last byte.
final class VerilogScanner {
  /// Creates a scanner over [source], naming it [path] in problem reports.
  ///
  /// [bufferSize] is the read buffer, which must be larger than
  /// [maxTokenBytes], the longest identifier, number or string accepted.
  VerilogScanner(
    this._source, {
    required this.path,
    int bufferSize = defaultBufferSize,
    this.maxTokenBytes = 64 * 1024,
    this.lenientDirectives = false,
    this.cancellation,
  }) : _buf = Uint8List(bufferSize) {
    if (bufferSize <= maxTokenBytes) {
      throw ArgumentError('bufferSize must exceed maxTokenBytes');
    }
  }

  /// The read buffer size used for files.
  static const int defaultBufferSize = 4 * 1024 * 1024;

  final ByteChunkSource _source;

  /// The file's path, for problem reports.
  final String path;

  /// The longest token accepted, in bytes.
  final int maxTokenBytes;

  /// Whether an unknown compiler directive is skipped to the end of its line
  /// instead of being an unsupported construct. For reading only the headers
  /// of cell model files.
  final bool lenientDirectives;

  /// Checked now and then; when it fires the scan ends as if at the end of
  /// the input.
  final CancellationToken? cancellation;

  final Uint8List _buf;
  int _pos = 0;
  int _end = 0;
  int _base = 0;
  bool _eof = false;
  bool _grew = false;
  int _line = 1;
  int _lineStart = 0;
  int _sinceCancelCheck = 0;

  /// The read buffer; valid with [tokenStart] and [tokenEnd] until the next
  /// [next].
  Uint8List get buffer => _buf;

  /// The current token's kind, a [VerilogToken] constant.
  int kind = VerilogToken.eof;

  /// Start and end (exclusive) of the current token's bytes in [buffer].
  int tokenStart = 0;

  /// See [tokenStart].
  int tokenEnd = 0;

  /// The current token's 1-based line and column.
  int line = 1;

  /// See [line].
  int column = 1;

  /// The line and the column one past the current token's last byte.
  int endLine = 1;

  /// See [endLine].
  int endColumn = 1;

  /// For a [VerilogToken.symbol], the byte.
  int symbol = 0;

  /// Whether an identifier was written in the escaped form.
  bool escaped = false;

  /// The 31-bit hash of an identifier's bytes.
  int hash = 0;

  /// Whether the current token had a byte outside ASCII.
  bool nonAscii = false;

  /// Whether an attribute skipped just before the current token named
  /// `blackbox` or `whitebox`: `(* blackbox *) module ...` marks a module
  /// whose body is not part of the design.
  bool precededByBlackBox = false;

  /// See [precededByBlackBox].
  bool precededByWhiteBox = false;

  /// The id of the current identifier in [interner].
  int intern(Interner interner) =>
      interner.intern(_buf, tokenStart, tokenEnd, hash);

  /// The current token's text.
  String get text => utf8.decode(
    Uint8List.sublistView(_buf, tokenStart, tokenEnd),
    allowMalformed: true,
  );

  /// Whether the current token is the one-character symbol [char].
  bool isSymbol(int char) => kind == VerilogToken.symbol && symbol == char;

  /// Advances to the next token.
  void next() {
    precededByBlackBox = false;
    precededByWhiteBox = false;
    _skipTrivia();
    if (_pos >= _end) {
      kind = VerilogToken.eof;
      tokenStart = tokenEnd = _pos;
      line = endLine = _line;
      column = endColumn = _base + _pos - _lineStart + 1;
      return;
    }
    final c = _buf[_pos];
    tokenStart = _pos;
    line = _line;
    column = _base + _pos - _lineStart + 1;
    escaped = false;
    nonAscii = false;
    final cls = _classes[c];
    if ((cls & _idStart) != 0) {
      _scanIdentifier();
    } else if (c == 0x5C) {
      _scanEscaped();
    } else if ((cls & _digit) != 0 || c == 0x27) {
      _scanNumber();
    } else if (c == 0x22) {
      _scanString();
    } else if (c == 0x24) {
      _scanSystem();
    } else {
      kind = VerilogToken.symbol;
      symbol = c;
      _pos++;
      tokenEnd = _pos;
    }
    endLine = _line;
    endColumn = _base + tokenEnd - _lineStart + 1;
  }

  // ---- buffer management ------------------------------------------------

  Never _tooLong() => throw NativeReaderFallback(
    NativeReaderStop.malformed,
    'a token longer than $maxTokenBytes bytes',
    path: path,
    line: _line,
  );

  /// Reads more input after the buffered bytes, first moving the bytes from
  /// [keepFrom] on to the front. Returns how far they moved, which the
  /// caller subtracts from every index it holds; [_grew] says whether any
  /// new byte arrived (it does not at the end of the input).
  int _extend(int keepFrom) {
    _grew = false;
    var shift = 0;
    if (keepFrom > 0) {
      shift = keepFrom;
      _buf.setRange(0, _end - keepFrom, _buf, keepFrom);
      _base += shift;
      _end -= shift;
      _pos = _pos >= shift ? _pos - shift : 0;
      if (tokenStart >= shift) tokenStart -= shift;
    }
    if (_eof) return shift;
    if (_end >= _buf.length) _tooLong();
    final n = _source.read(Uint8List.sublistView(_buf, _end));
    if (n == 0) {
      _eof = true;
    } else {
      _end += n;
      _grew = true;
    }
    return shift;
  }

  /// Makes at least [n] bytes available from `_pos`, or all that remain.
  void _fillAtLeast(int n) {
    while (_end - _pos < n && !_eof) {
      if (_pos > 0) {
        _buf.setRange(0, _end - _pos, _buf, _pos);
        _base += _pos;
        _end -= _pos;
        _pos = 0;
      }
      if (_end >= _buf.length) return;
      final got = _source.read(Uint8List.sublistView(_buf, _end));
      if (got == 0) {
        _eof = true;
      } else {
        _end += got;
      }
    }
  }

  /// Discards the buffer and reads the next block. `false` at the end.
  bool _refill() {
    if (_eof) {
      _pos = _end;
      return false;
    }
    _base += _end;
    _end = 0;
    _pos = 0;
    final n = _source.read(_buf);
    if (n == 0) {
      _eof = true;
      return false;
    }
    _end = n;
    return true;
  }

  // ---- trivia -----------------------------------------------------------

  void _skipTrivia() {
    while (true) {
      _fillAtLeast(3);
      if (_pos >= _end) return;
      if (++_sinceCancelCheck >= 4096) {
        _sinceCancelCheck = 0;
        if (cancellation?.isCancelled ?? false) {
          _eof = true;
          _pos = _end;
          return;
        }
      }
      var i = _pos;
      final end = _end;
      final buf = _buf;
      // Positions before `safeEnd` have two bytes of look-ahead.
      final safeEnd = _eof ? end : end - 2;
      var special = false;
      while (i < safeEnd) {
        final c = buf[i];
        if (c == 0x20 || c == 0x09 || c == 0x0D) {
          i++;
        } else if (c == 0x0A) {
          i++;
          _line++;
          _lineStart = _base + i;
        } else if (c == 0x2F || c == 0x28 || c == 0x60) {
          special = true;
          break;
        } else {
          _pos = i;
          return;
        }
      }
      _pos = i;
      if (!special) {
        if (i >= end) {
          if (!_refill()) return;
        }
        continue;
      }
      final c = buf[i];
      final d = i + 1 < end ? buf[i + 1] : -1;
      if (c == 0x2F && d == 0x2F) {
        _skipLineComment();
      } else if (c == 0x2F && d == 0x2A) {
        _skipBlockComment();
      } else if (c == 0x28 && d == 0x2A) {
        final e = i + 2 < end ? buf[i + 2] : -1;
        if (e == 0x29) return; // '(*)' is not an attribute.
        _skipAttribute();
      } else if (c == 0x60) {
        _directive();
      } else {
        return;
      }
    }
  }

  void _skipLineComment() {
    var i = _pos + 2;
    while (true) {
      final end = _end;
      final buf = _buf;
      while (i < end) {
        if (buf[i] == 0x0A) {
          _pos = i;
          return;
        }
        i++;
      }
      if (!_refill()) return;
      i = 0;
    }
  }

  void _skipBlockComment() =>
      _skipDelimited(0x2F, 'an unterminated block comment');

  void _skipAttribute() =>
      _skipDelimited(0x29, 'an unterminated attribute', attribute: true);

  /// Skips a `/* */` or `(* *)` construct whose opener is at `_pos`; [close]
  /// is the byte after the closing `*`.
  void _skipDelimited(int close, String problem, {bool attribute = false}) {
    final startLine = _line;
    var i = _pos + 2;
    var star = false;
    // The word being read inside an attribute, to notice blackbox and
    // whitebox.
    var word = 0;
    var wordLength = 0;
    while (true) {
      final end = _end;
      final buf = _buf;
      while (i < end) {
        final c = buf[i++];
        if (attribute) {
          if ((_classes[c] & _idChar) != 0) {
            if (wordLength < 9) word = word * 131 + c;
            wordLength++;
          } else {
            if (wordLength == 8) {
              if (word == _blackboxWord) precededByBlackBox = true;
              if (word == _whiteboxWord) precededByWhiteBox = true;
            }
            word = 0;
            wordLength = 0;
          }
        }
        if (c == 0x0A) {
          _line++;
          _lineStart = _base + i;
          star = false;
        } else if (star && c == close) {
          _pos = i;
          return;
        } else {
          star = c == 0x2A;
        }
      }
      if (!_refill()) {
        throw NativeReaderFallback(
          NativeReaderStop.malformed,
          problem,
          path: path,
          line: startLine,
        );
      }
      i = 0;
    }
  }

  /// Handles the directive at the backtick under `_pos`.
  void _directive() {
    final startLine = _line;
    _fillAtLeast(256);
    final buf = _buf;
    var i = _pos + 1;
    final end = _end;
    final nameStart = i;
    while (i < end && (_classes[buf[i]] & _idChar) != 0) {
      i++;
    }
    final name = utf8.decode(
      Uint8List.sublistView(buf, nameStart, i),
      allowMalformed: true,
    );
    _pos = i;
    switch (name) {
      case 'timescale':
        _skipRestOfLine();
      case 'celldefine' || 'endcelldefine' || 'resetall':
        break;
      case 'default_nettype':
        var j = i;
        while (j < end && (buf[j] == 0x20 || buf[j] == 0x09)) {
          j++;
        }
        final wordStart = j;
        while (j < end && (_classes[buf[j]] & _idChar) != 0) {
          j++;
        }
        final word = utf8.decode(
          Uint8List.sublistView(buf, wordStart, j),
          allowMalformed: true,
        );
        if (word != 'wire') {
          throw NativeReaderFallback(
            NativeReaderStop.unsupported,
            'the directive `default_nettype $word',
            path: path,
            line: startLine,
          );
        }
        _pos = j;
      default:
        if (!lenientDirectives) {
          throw NativeReaderFallback(
            NativeReaderStop.unsupported,
            'the compiler directive `$name',
            path: path,
            line: startLine,
          );
        }
        _skipDirectiveLine();
    }
  }

  /// Skips to (not past) the end of the current line.
  void _skipRestOfLine() {
    var i = _pos;
    while (true) {
      final end = _end;
      final buf = _buf;
      while (i < end) {
        if (buf[i] == 0x0A) {
          _pos = i;
          return;
        }
        i++;
      }
      if (!_refill()) return;
      i = 0;
    }
  }

  /// Skips a directive's line, honouring backslash continuations.
  void _skipDirectiveLine() {
    var previous = 0;
    var i = _pos;
    while (true) {
      final end = _end;
      final buf = _buf;
      while (i < end) {
        final c = buf[i];
        if (c == 0x0A) {
          if (previous == 0x5C) {
            i++;
            _line++;
            _lineStart = _base + i;
            previous = 0;
            continue;
          }
          _pos = i;
          return;
        }
        if (c != 0x0D) previous = c;
        i++;
      }
      if (!_refill()) return;
      i = 0;
    }
  }

  // ---- tokens -----------------------------------------------------------

  void _scanIdentifier() {
    kind = VerilogToken.identifier;
    var i = tokenStart;
    var h = _fnvOffset;
    var hi = 0;
    while (true) {
      final end = _end;
      final buf = _buf;
      while (i < end) {
        final c = buf[i];
        if ((_classes[c] & _idChar) == 0) {
          _finishName(i, h, hi);
          return;
        }
        h = ((h ^ c) * _fnvPrime) & _hashMask;
        hi |= c;
        i++;
      }
      if (i - tokenStart > maxTokenBytes) _tooLong();
      final shift = _extend(tokenStart);
      i -= shift;
      if (!_grew) {
        _finishName(i, h, hi);
        return;
      }
    }
  }

  void _finishName(int i, int h, int hi) {
    tokenEnd = i;
    _pos = i;
    hash = h;
    nonAscii = hi >= 0x80;
  }

  void _scanEscaped() {
    kind = VerilogToken.identifier;
    escaped = true;
    tokenStart = _pos + 1;
    var i = tokenStart;
    var h = _fnvOffset;
    var hi = 0;
    while (true) {
      final end = _end;
      final buf = _buf;
      while (i < end) {
        final c = buf[i];
        if (c <= 0x20) {
          _finishName(i, h, hi);
          _checkEscapedNotEmpty();
          return;
        }
        h = ((h ^ c) * _fnvPrime) & _hashMask;
        hi |= c;
        i++;
      }
      if (i - tokenStart > maxTokenBytes) _tooLong();
      final shift = _extend(tokenStart);
      i -= shift;
      if (!_grew) {
        _finishName(i, h, hi);
        _checkEscapedNotEmpty();
        return;
      }
    }
  }

  void _checkEscapedNotEmpty() {
    if (tokenEnd == tokenStart) {
      throw NativeReaderFallback(
        NativeReaderStop.malformed,
        'an empty escaped identifier',
        path: path,
        line: _line,
      );
    }
  }

  void _scanSystem() {
    kind = VerilogToken.system;
    var i = tokenStart + 1;
    while (true) {
      final end = _end;
      final buf = _buf;
      while (i < end && (_classes[buf[i]] & _idChar) != 0) {
        i++;
      }
      if (i < end) break;
      if (i - tokenStart > maxTokenBytes) _tooLong();
      final shift = _extend(tokenStart);
      i -= shift;
      if (!_grew) break;
    }
    tokenEnd = i;
    _pos = i;
  }

  void _scanNumber() {
    kind = VerilogToken.number;
    var i = tokenStart;
    while (true) {
      final end = _end;
      final buf = _buf;
      while (i < end) {
        final c = buf[i];
        // Digits, based-number letters, '_', '?' and the apostrophe.
        if ((_classes[c] & _idChar) != 0 || c == 0x27 || c == 0x3F) {
          i++;
        } else {
          tokenEnd = i;
          _pos = i;
          return;
        }
      }
      if (i - tokenStart > maxTokenBytes) _tooLong();
      final shift = _extend(tokenStart);
      i -= shift;
      if (!_grew) {
        tokenEnd = i;
        _pos = i;
        return;
      }
    }
  }

  void _scanString() {
    kind = VerilogToken.string;
    final startLine = _line;
    var i = tokenStart + 1;
    var escape = false;
    while (true) {
      final end = _end;
      final buf = _buf;
      while (i < end) {
        final c = buf[i++];
        if (c == 0x0A) {
          _line++;
          _lineStart = _base + i;
        }
        if (escape) {
          escape = false;
        } else if (c == 0x5C) {
          escape = true;
        } else if (c == 0x22) {
          tokenEnd = i;
          _pos = i;
          return;
        }
      }
      if (i - tokenStart > maxTokenBytes) _tooLong();
      final shift = _extend(tokenStart);
      i -= shift;
      if (!_grew) {
        throw NativeReaderFallback(
          NativeReaderStop.malformed,
          'an unterminated string',
          path: path,
          line: startLine,
        );
      }
    }
  }

  static final int _blackboxWord = _wordHash('blackbox');
  static final int _whiteboxWord = _wordHash('whitebox');

  static int _wordHash(String text) {
    var h = 0;
    for (final c in text.codeUnits) {
      h = h * 131 + c;
    }
    return h;
  }

  static const int _idStart = 1;
  static const int _idChar = 2;
  static const int _digit = 4;

  static final Uint8List _classes = _buildClasses();

  static Uint8List _buildClasses() {
    final table = Uint8List(256);
    for (var c = 0x41; c <= 0x5A; c++) {
      table[c] = _idStart | _idChar;
    }
    for (var c = 0x61; c <= 0x7A; c++) {
      table[c] = _idStart | _idChar;
    }
    table[0x5F] = _idStart | _idChar;
    for (var c = 0x30; c <= 0x39; c++) {
      table[c] = _idChar | _digit;
    }
    table[0x24] = _idChar;
    return table;
  }

  static const int _fnvOffset = 0x811c9dc5;
  static const int _fnvPrime = 0x01000193;
  static const int _hashMask = 0x7fffffff;
}
