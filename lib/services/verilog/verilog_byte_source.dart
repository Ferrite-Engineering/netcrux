// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:netcrux/services/yosys/chunked_yosys_json_reader.dart';

/// Thrown when a Verilog file cannot be opened or read, or a gzip stream in
/// it is damaged. The message is for Diagnostics; the file is [path].
class VerilogSourceException implements Exception {
  /// Creates the exception.
  const VerilogSourceException(this.path, this.message);

  /// The file that failed.
  final String path;

  /// What went wrong, in English.
  final String message;

  @override
  String toString() => 'VerilogSourceException: $path: $message';
}

/// Opens the Verilog file at [path] as a byte source: a gzip-compressed file
/// (one that starts with the gzip magic number, whatever its name) is
/// inflated as it is read, a block at a time, so the decompressed text is
/// never held in memory. A plain file is read straight from disk.
///
/// The caller closes the source. Throws [VerilogSourceException] when the
/// file cannot be opened.
ByteChunkSource openVerilogSource(String path) {
  final RandomAccessFile file;
  try {
    file = File(path).openSync();
  } on FileSystemException catch (e) {
    throw VerilogSourceException(
      path,
      'cannot be opened: ${e.osError?.message ?? e.message}',
    );
  }
  try {
    final head = file.readSync(2);
    file.setPositionSync(0);
    if (head.length == 2 && head[0] == 0x1f && head[1] == 0x8b) {
      return _GzipFileSource(path, file);
    }
    return _PlainFileSource(path, file);
  } on FileSystemException catch (e) {
    file.closeSync();
    throw VerilogSourceException(
      path,
      'cannot be read: ${e.osError?.message ?? e.message}',
    );
  }
}

final class _PlainFileSource implements ByteChunkSource {
  _PlainFileSource(this._path, this._file);

  final String _path;
  final RandomAccessFile _file;

  @override
  int read(Uint8List into) {
    try {
      return _file.readIntoSync(into);
    } on FileSystemException catch (e) {
      throw VerilogSourceException(
        _path,
        'cannot be read: ${e.osError?.message ?? e.message}',
      );
    }
  }

  @override
  void close() => _file.closeSync();
}

/// The inflated bytes of a gzip file. The decoder is driven synchronously (a
/// block of compressed bytes goes in and its output is queued before `add`
/// returns), which is what lets a synchronous reader pull from it on a worker
/// isolate without the whole file in memory.
final class _GzipFileSource implements ByteChunkSource {
  _GzipFileSource(this._path, this._file) {
    _sink = gzip.decoder.startChunkedConversion(_QueueSink(_inflated));
  }

  final String _path;
  final RandomAccessFile _file;
  final Uint8List _compressed = Uint8List(1 << 16);
  final Queue<Uint8List> _inflated = Queue<Uint8List>();
  late final ByteConversionSink _sink;
  int _offset = 0;
  bool _finished = false;

  @override
  int read(Uint8List into) {
    try {
      while (_inflated.isEmpty && !_finished) {
        final n = _file.readIntoSync(_compressed);
        if (n == 0) {
          _finished = true;
          _sink.close();
        } else {
          _sink.add(Uint8List.sublistView(_compressed, 0, n));
        }
      }
    } on FileSystemException catch (e) {
      throw VerilogSourceException(
        _path,
        'cannot be read: ${e.osError?.message ?? e.message}',
      );
    } on FormatException catch (e) {
      throw VerilogSourceException(
        _path,
        'is not valid gzip data: ${e.message}',
      );
    }
    var written = 0;
    while (written < into.length && _inflated.isNotEmpty) {
      final chunk = _inflated.first;
      final take = (chunk.length - _offset).clamp(0, into.length - written);
      into.setRange(written, written + take, chunk, _offset);
      written += take;
      _offset += take;
      if (_offset == chunk.length) {
        _inflated.removeFirst();
        _offset = 0;
      }
    }
    return written;
  }

  @override
  void close() => _file.closeSync();
}

/// Collects a decoder's output blocks, each copied so the decoder is free to
/// reuse its own.
final class _QueueSink implements Sink<List<int>> {
  _QueueSink(this._queue);

  final Queue<Uint8List> _queue;

  @override
  void add(List<int> data) => _queue.add(Uint8List.fromList(data));

  @override
  void close() {}
}
