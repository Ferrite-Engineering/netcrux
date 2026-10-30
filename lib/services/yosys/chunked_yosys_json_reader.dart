// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:netcrux/domain/models/netlist/module.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/services/yosys/streaming_yosys_json_reader.dart';

/// Where a [ChunkedYosysJsonReader] gets its bytes: [read] fills a prefix of
/// the buffer it is given and returns how many bytes it wrote, `0` at the end
/// of the document.
abstract interface class ByteChunkSource {
  /// Fills a prefix of [into]; returns the count, or `0` at the end.
  int read(Uint8List into);

  /// Releases what the source holds open.
  void close();
}

/// A [ByteChunkSource] over a file, read with a `RandomAccessFile` so only the
/// chunk in hand is ever in memory, however large the file is.
final class FileChunkSource implements ByteChunkSource {
  /// Opens [path] for reading. Throws [FileSystemException] when it cannot be.
  FileChunkSource(String path) : _file = File(path).openSync();

  final RandomAccessFile _file;

  @override
  int read(Uint8List into) => _file.readIntoSync(into);

  @override
  void close() => _file.closeSync();
}

/// A [ByteChunkSource] over bytes already in memory, handed out
/// [maxChunk] at a time. For tests: a small [maxChunk] puts a chunk boundary
/// in the middle of every token.
final class MemoryChunkSource implements ByteChunkSource {
  /// Creates a source over [bytes].
  MemoryChunkSource(this._bytes, {required this.maxChunk});

  final Uint8List _bytes;

  /// The most bytes one [read] returns.
  final int maxChunk;

  int _at = 0;

  @override
  int read(Uint8List into) {
    final n = [
      into.length,
      maxChunk,
      _bytes.length - _at,
    ].reduce((a, b) => a < b ? a : b);
    into.setRange(0, n, _bytes, _at);
    _at += n;
    return n;
  }

  @override
  void close() {}
}

/// Reads `yosys write_json` output from a byte source in bounded chunks,
/// into a [NetlistModel], without ever holding the document, or a whole
/// module, as one string or one buffer.
///
/// The scanner walks the document's structure by hand down to the members of
/// a module's `ports`, `cells`, `netnames` and `memories` maps. Each member
/// (one cell, one net) is copied into a reusable buffer, decoded and turned
/// into its model object at once, then dropped. Memory is therefore the chunk
/// buffer, the largest single member, and the model being built, whatever the
/// size of the file and of its largest module. [StreamingYosysJsonReader.parse]
/// slices a whole module out of a string; a flat module of millions of cells
/// is one slice of gigabytes there, and is not here.
///
/// The produced [NetlistModel] equals the one
/// [StreamingYosysJsonReader.parse] builds from the same text, and malformed
/// input fails with the same [YosysJsonParseException] type. The two are
/// cross-tested, with chunk sizes that split every token, in
/// `test/services/yosys/chunked_yosys_json_reader_test.dart`.
class ChunkedYosysJsonReader {
  /// Creates a reader over [source]. [chunkSize] is the size of the read
  /// buffer; the default suits a file, tests use small values.
  ChunkedYosysJsonReader(
    this._source, {
    int chunkSize = defaultChunkSize,
    this._cancellation,
  }) : _buf = Uint8List(chunkSize);

  /// The read buffer size [parseFile] uses: large enough that a read is a
  /// small share of the time, small enough to be a rounding error in memory.
  static const int defaultChunkSize = 4 * 1024 * 1024;

  /// Reads the file at [path] and parses it. Synchronous: it is meant to run
  /// on a worker isolate, as the rest of the parse does.
  ///
  /// Throws [YosysJsonParseException] for a document that is not a Yosys
  /// netlist, and [FileSystemException] when the file cannot be read.
  static NetlistModel parseFile(
    String path, {
    int chunkSize = defaultChunkSize,
    CancellationToken? cancellation,
  }) {
    final source = FileChunkSource(path);
    try {
      return ChunkedYosysJsonReader(
        source,
        chunkSize: chunkSize,
        cancellation: cancellation,
      ).parse();
    } finally {
      source.close();
    }
  }

  final ByteChunkSource _source;
  final Uint8List _buf;
  final CancellationToken? _cancellation;
  final _Capture _capture = _Capture();

  int _pos = 0;
  int _end = 0;

  /// Bytes of the document before the start of the current buffer.
  int _consumed = 0;
  bool _eof = false;

  /// Parses the whole document.
  NetlistModel parse() {
    try {
      return _parseDocument();
    } on _CancelledRead {
      return const NetlistModel(creator: '', modules: <String, Module>{});
    } on YosysJsonParseException {
      rethrow;
    } on Object catch (e) {
      // The member decoders can throw a raw FormatException (a bad escape in
      // a name) or TypeError; the caller sees one typed failure.
      throw YosysJsonParseException(
        'Yosys JSON could not be parsed: $e',
        cause: e,
      );
    }
  }

  NetlistModel _parseDocument() {
    var creator = '';
    Map<String, Module>? modules;
    _skipWhitespace();
    if (_peek() != _openBrace) {
      throw const YosysJsonParseException(
        'Yosys JSON is missing a `modules` object',
      );
    }
    _pos++;
    _forEachMember('the document', (key) {
      switch (key) {
        case 'creator':
          creator = _scalarText(_decodeValue());
        case 'modules':
          if (_peek() != _openBrace) {
            _skipValue();
            return;
          }
          _pos++;
          modules = _readModules();
        default:
          _skipValue();
      }
    });
    final found = modules;
    if (found == null) {
      throw const YosysJsonParseException(
        'Yosys JSON is missing a `modules` object',
      );
    }
    return NetlistModel(creator: creator, modules: found);
  }

  /// Reads the members of the `modules` object, whose `{` was just consumed.
  Map<String, Module> _readModules() {
    final into = <String, Module>{};
    _forEachMember('modules', (name) {
      if (_cancellation?.isCancelled ?? false) throw const _CancelledRead();
      if (_peek() != _openBrace) {
        throw const YosysJsonParseException(
          'Expected `{` after module name',
        );
      }
      _pos++;
      into[name] = _readModule(name);
    });
    return into;
  }

  Module _readModule(String name) {
    var attributes = const <String, String>{};
    final ports = <String, Port>{};
    final cells = <String, Cell>{};
    final nets = <String, Net>{};
    final memories = <String, Memory>{};
    final where = 'module ${_describe(name)}';
    try {
      _forEachMember('module "$name"', (key) {
        switch (key) {
          case 'attributes':
            final raw = _decodeValue();
            if (raw == null) return;
            if (raw is! Map<String, Object?>) {
              throw FormatException(
                '$where: "attributes" is ${_describe(raw)}, expected an object',
              );
            }
            // An otherwise empty module reads its attributes exactly as
            // the full document would.
            attributes = Module.fromJson(name, <String, Object?>{
              'attributes': raw,
            }).attributes;
          case 'ports':
            _readEntries(where, 'ports', 'port', (k, o) {
              ports[k] = Port.fromJson(k, o);
            });
          case 'cells':
            _readEntries(where, 'cells', 'cell', (k, o) {
              cells[k] = Cell.fromJson(k, o);
            });
          case 'netnames':
            _readEntries(where, 'netnames', 'net', (k, o) {
              nets[k] = Net.fromJson(k, o);
            });
          case 'memories':
            _readEntries(where, 'memories', 'memory', (k, o) {
              memories[k] = Memory.fromJson(k, o);
            });
          default:
            _skipValue();
        }
      });
    } on YosysJsonParseException {
      rethrow;
    } on _CancelledRead {
      rethrow;
    } on Object catch (e) {
      throw YosysJsonParseException(
        'Module "$name" has unexpected types: $e',
        cause: e,
      );
    }
    return Module(
      name: name,
      attributes: attributes,
      ports: ports,
      cells: cells,
      nets: nets,
      memories: memories,
    );
  }

  /// Reads the object `section` of a module entry by entry. Each member is
  /// decoded alone and handed to [onEntry]; one that is not an object, or a
  /// section that is neither an object nor `null`, is a [FormatException]
  /// worded as the full-document parser words it.
  void _readEntries(
    String where,
    String section,
    String noun,
    void Function(String key, Map<String, Object?> json) onEntry,
  ) {
    _skipWhitespace();
    if (_peek() != _openBrace) {
      final raw = _decodeValue();
      if (raw == null) return;
      throw FormatException(
        '$where: "$section" is ${_describe(raw)}, expected an object',
      );
    }
    _pos++;
    _forEachMember('$section of $where', (key) {
      final raw = _decodeValue();
      if (raw is! Map<String, Object?>) {
        throw FormatException(
          '$where: $noun ${_describe(key)}: "$section.$key" is '
          '${_describe(raw)}, expected an object',
        );
      }
      try {
        onEntry(key, raw);
      } on FormatException catch (e) {
        throw FormatException('$where: $noun ${_describe(key)}: ${e.message}');
      }
    });
  }

  /// Walks the members of the object whose `{` was just consumed, calling
  /// [onMember] with each key; the callback must consume the member's value.
  /// Returns after the closing `}`.
  void _forEachMember(String what, void Function(String key) onMember) {
    var sinceCheck = 0;
    while (true) {
      _skipWhitespace();
      final c = _peek();
      if (c < 0) {
        throw YosysJsonParseException('Yosys JSON ended inside $what');
      }
      if (c == _closeBrace) {
        _pos++;
        return;
      }
      if (c == _comma) {
        _pos++;
        continue;
      }
      if (c != _quote) {
        throw YosysJsonParseException(
          'Expected a member name in $what at byte ${_offset()}, '
          'got "${String.fromCharCode(c)}"',
        );
      }
      final key = _readString();
      _skipWhitespace();
      if (_peek() != _colon) {
        throw YosysJsonParseException('Expected colon after "$key" in $what');
      }
      _pos++;
      _skipWhitespace();
      onMember(key);
      if (++sinceCheck >= 4096) {
        sinceCheck = 0;
        if (_cancellation?.isCancelled ?? false) {
          throw const _CancelledRead();
        }
      }
    }
  }

  // ---- byte access ------------------------------------------------------

  int _offset() => _consumed + _pos;

  /// The byte at the cursor, refilling the buffer when it is spent; `-1` at
  /// the end of the document.
  int _peek() {
    if (_pos < _end || _fill()) return _buf[_pos];
    return -1;
  }

  bool _fill() {
    if (_eof) return false;
    _consumed += _end;
    _pos = 0;
    _end = _source.read(_buf);
    if (_end == 0) {
      _eof = true;
      return false;
    }
    return true;
  }

  void _skipWhitespace() {
    while (true) {
      if (_pos >= _end && !_fill()) return;
      final buf = _buf;
      var i = _pos;
      final end = _end;
      while (i < end) {
        final c = buf[i];
        if (c != _space && c != _tab && c != _newline && c != _carriageReturn) {
          _pos = i;
          return;
        }
        i++;
      }
      _pos = i;
    }
  }

  // ---- tokens -----------------------------------------------------------

  /// Reads the string at the cursor (which must be its opening quote) and
  /// returns its decoded text.
  String _readString() {
    _capture.clear();
    _captureString();
    return _decodeString(_capture.view());
  }

  static String _decodeString(Uint8List quoted) {
    // Between the quotes. A backslash needs the JSON decoder; plain text is
    // UTF-8 as it stands.
    var escaped = false;
    for (var i = 1; i < quoted.length - 1; i++) {
      if (quoted[i] == _backslash) {
        escaped = true;
        break;
      }
    }
    if (!escaped) {
      return utf8.decode(Uint8List.sublistView(quoted, 1, quoted.length - 1));
    }
    return jsonDecode(utf8.decode(quoted)) as String;
  }

  /// Copies the string at the cursor, quotes included, into the capture.
  void _captureString() {
    var escape = false;
    var first = true;
    while (true) {
      if (_pos >= _end && !_fill()) {
        throw const YosysJsonParseException('Unterminated string');
      }
      final buf = _buf;
      final start = _pos;
      var i = start;
      final end = _end;
      var done = false;
      if (first) {
        i++; // the opening quote
        first = false;
      }
      while (i < end) {
        final c = buf[i++];
        if (escape) {
          escape = false;
        } else if (c == _backslash) {
          escape = true;
        } else if (c == _quote) {
          done = true;
          break;
        }
      }
      _capture.add(buf, start, i);
      _pos = i;
      if (done) return;
    }
  }

  /// Copies the value at the cursor (an object, an array, a string or a
  /// scalar) into the capture.
  void _captureValue() {
    final c = _peek();
    if (c < 0) {
      throw const YosysJsonParseException('Yosys JSON ended mid-value');
    }
    if (c == _quote) {
      _captureString();
    } else if (c == _openBrace || c == _openBracket) {
      _captureStructure();
    } else {
      _captureScalar();
    }
  }

  /// Copies the object or array at the cursor, counting brackets outside
  /// strings. Mismatched bracket kinds are left for the JSON decoder to
  /// refuse.
  void _captureStructure() {
    var depth = 0;
    var inString = false;
    var escape = false;
    while (true) {
      if (_pos >= _end && !_fill()) {
        throw const YosysJsonParseException('Yosys JSON ended mid-value');
      }
      final buf = _buf;
      final start = _pos;
      var i = start;
      final end = _end;
      var done = false;
      while (i < end) {
        final c = buf[i++];
        if (inString) {
          if (escape) {
            escape = false;
          } else if (c == _backslash) {
            escape = true;
          } else if (c == _quote) {
            inString = false;
          }
        } else if (c == _quote) {
          inString = true;
        } else if (c == _openBrace || c == _openBracket) {
          depth++;
        } else if (c == _closeBrace || c == _closeBracket) {
          if (--depth == 0) {
            done = true;
            break;
          }
        }
      }
      _capture.add(buf, start, i);
      _pos = i;
      if (done) return;
    }
  }

  void _captureScalar() {
    while (true) {
      if (_pos >= _end && !_fill()) return;
      final buf = _buf;
      final start = _pos;
      var i = start;
      final end = _end;
      var done = false;
      while (i < end) {
        final c = buf[i];
        if (c == _comma ||
            c == _closeBrace ||
            c == _closeBracket ||
            c == _space ||
            c == _tab ||
            c == _newline ||
            c == _carriageReturn) {
          done = true;
          break;
        }
        i++;
      }
      _capture.add(buf, start, i);
      _pos = i;
      if (done) return;
    }
  }

  /// Reads and decodes the value at the cursor.
  Object? _decodeValue() {
    _capture.clear();
    _captureValue();
    final text = utf8.decode(_capture.view());
    try {
      return jsonDecode(text);
    } on FormatException catch (e) {
      throw YosysJsonParseException(
        'Yosys JSON has a malformed value: ${e.message}',
        cause: e,
      );
    }
  }

  /// Steps over the value at the cursor without keeping it.
  void _skipValue() {
    _capture.clear();
    _captureValue();
    // The capture is bounded by the largest skipped value, which is a
    // section Yosys writes small (module parameters, a version).
    _capture.clear();
  }

  static String _scalarText(Object? value) =>
      value == null ? '' : (value is String ? value : '$value');

  /// A value as the full-document parser quotes it in a message: short, and
  /// never more than a prefix of what a hostile file put there.
  static String _describe(Object? value) => switch (value) {
    null => 'null',
    final String s when s.length <= 64 => '"$s"',
    final String s => '"${s.substring(0, 64)}…" (${s.length} characters)',
    final num n => '$n',
    final bool b => '$b',
    final List<Object?> l => 'a list of ${l.length}',
    final Map<Object?, Object?> m => 'an object of ${m.length} keys',
    _ => 'a ${value.runtimeType}',
  };

  static const int _openBrace = 0x7B;
  static const int _closeBrace = 0x7D;
  static const int _openBracket = 0x5B;
  static const int _closeBracket = 0x5D;
  static const int _comma = 0x2C;
  static const int _colon = 0x3A;
  static const int _quote = 0x22;
  static const int _backslash = 0x5C;
  static const int _space = 0x20;
  static const int _tab = 0x09;
  static const int _newline = 0x0A;
  static const int _carriageReturn = 0x0D;
}

/// Thrown inside a member loop when the cancellation token fires; the
/// document-level read turns it into an empty result.
class _CancelledRead implements Exception {
  const _CancelledRead();
}

/// A reusable, growing byte buffer holding the value being captured.
class _Capture {
  Uint8List _bytes = Uint8List(4096);
  int _length = 0;

  void clear() {
    _length = 0;
    // A one-off huge member must not pin its buffer for the rest of the
    // read.
    if (_bytes.length > _retainLimit) _bytes = Uint8List(4096);
  }

  void add(Uint8List source, int start, int end) {
    final n = end - start;
    if (n <= 0) return;
    final needed = _length + n;
    if (needed > _bytes.length) {
      var size = _bytes.length * 2;
      while (size < needed) {
        size *= 2;
      }
      final grown = Uint8List(size)..setRange(0, _length, _bytes);
      _bytes = grown;
    }
    _bytes.setRange(_length, needed, source, start);
    _length = needed;
  }

  /// A view of the captured bytes; valid until the next [clear] or [add].
  Uint8List view() => Uint8List.sublistView(_bytes, 0, _length);

  static const int _retainLimit = 64 * 1024 * 1024;
}
