// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';
import 'package:netcrux/services/liberty/liberty_library.dart';
import 'package:netcrux/services/liberty/liberty_parser.dart';
import 'package:netcrux/services/liberty/liberty_stub_writer.dart';
import 'package:path/path.dart' as p;

/// The black-box stub file for a project's cell libraries, ready to hand
/// to Yosys as one more Verilog source.
@immutable
class LibertyStubs {
  /// Creates the result.
  LibertyStubs({
    required this.stubPath,
    required this.cellCount,
    required List<String> warnings,
  }) : warnings = List<String>.unmodifiable(warnings);

  /// The generated Verilog file.
  final String stubPath;

  /// How many cell modules it declares.
  final int cellCount;

  /// Things to tell the user, such as a cell defined in two libraries.
  final List<String> warnings;
}

/// Turns a project's Liberty files into one Verilog file of
/// `(* blackbox *)` cell stubs, and keeps the result on disk so it is
/// computed once per library version.
///
/// Each Liberty file's cell interfaces are cached as JSON under
/// `<base>/liberty-cache/`, keyed by the file's absolute path, size and
/// modification time: re-elaborating after a source edit reads a few
/// hundred kilobytes of JSON instead of re-parsing a library of hundreds of
/// megabytes, and adding a second library leaves the first one cached. The
/// merged stub file sits beside them, named for the set of libraries it was
/// made from. The cache is pruned to the newest [maxCacheFiles] files, and
/// a cache that cannot be read or written only costs a re-parse.
///
/// Parsing runs on a background isolate.
class LibertyStubService {
  /// Creates a service caching under [cacheBaseDirectory] (resolved lazily,
  /// then memoised).
  LibertyStubService({
    required this.cacheBaseDirectory,
    this.maxCacheFiles = 64,
  });

  /// The directory the `liberty-cache/` folder is created in.
  final Future<Directory> Function() cacheBaseDirectory;

  /// How many cache files are kept; the oldest are removed.
  final int maxCacheFiles;

  /// Bumped when the parser or writer changes what it produces, so stale
  /// cache entries are never read.
  static const int formatVersion = 1;

  Future<Directory>? _dir;

  Future<Directory> _cacheDir() => _dir ??= () async {
    Directory base;
    try {
      base = await cacheBaseDirectory();
    } on Object {
      base = Directory.systemTemp;
    }
    final dir = Directory(p.join(base.path, 'liberty-cache'));
    await dir.create(recursive: true);
    return dir;
  }();

  /// Returns the stub file for [libertyFiles], in order (the first library
  /// to define a cell wins).
  ///
  /// Throws [LibertyParseException] naming the file when a library is
  /// missing, unreadable or not valid Liberty.
  Future<LibertyStubs> stubsFor(List<String> libertyFiles) async {
    final dir = await _cacheDir();
    final keys = <String>[];
    for (final path in libertyFiles) {
      keys.add(await _fileKey(path));
    }
    final libraries = List<LibertyLibrary?>.filled(libertyFiles.length, null);
    final misses = <int>[];
    for (var i = 0; i < libertyFiles.length; i++) {
      final cached = await _readCached(dir, keys[i]);
      if (cached == null) {
        misses.add(i);
      } else {
        libraries[i] = cached;
      }
    }
    if (misses.isNotEmpty) {
      final paths = <String>[for (final i in misses) libertyFiles[i]];
      final parsed = await Isolate.run(() => _parseAll(paths));
      for (var j = 0; j < misses.length; j++) {
        final result = parsed[j];
        if (result is LibertyParseException) throw result;
        final library = result as LibertyLibrary;
        libraries[misses[j]] = library;
        await _writeCached(dir, keys[misses[j]], library);
      }
    }
    final text = writeLibertyStubs(libraries.cast<LibertyLibrary>());
    final stub = File(
      p.join(dir.path, 'stubs-${_digest(keys.join('\n'))}.v'),
    );
    if (!stub.existsSync()) {
      await _writeAtomically(stub, text.verilog);
    }
    _prune(
      dir,
      keep: <String>{
        stub.path,
        for (final key in keys) p.join(dir.path, 'lib-$key.json'),
      },
    );
    return LibertyStubs(
      stubPath: stub.path,
      cellCount: text.cellCount,
      warnings: text.warnings,
    );
  }

  /// Parses every path, returning a [LibertyLibrary] or the
  /// [LibertyParseException] for each, so one bad file reports itself
  /// rather than as an opaque isolate error.
  static List<Object> _parseAll(List<String> paths) => <Object>[
    for (final path in paths) _parseOne(path),
  ];

  static Object _parseOne(String path) {
    try {
      return LibertyParser.parseFile(path);
    } on LibertyParseException catch (e) {
      return e;
    }
  }

  /// The cache key of one Liberty file: its absolute path, size and
  /// modification time, and the cache format.
  static Future<String> _fileKey(String path) async {
    final absolute = p.normalize(p.absolute(path));
    final FileStat stat;
    try {
      // Async stat: this runs from the elaboration provider on the UI
      // isolate.
      // ignore: avoid_slow_async_io
      stat = await File(absolute).stat();
    } on FileSystemException catch (e) {
      throw LibertyParseException(path, e.message);
    }
    if (stat.type == FileSystemEntityType.notFound) {
      throw LibertyParseException(path, 'file not found');
    }
    if (stat.type != FileSystemEntityType.file) {
      throw LibertyParseException(path, 'not a file');
    }
    return _digest(
      'v$formatVersion\n$absolute\n${stat.size}\n'
      '${stat.modified.microsecondsSinceEpoch}',
    );
  }

  static String _digest(String text) =>
      sha256.convert(utf8.encode(text)).toString().substring(0, 32);

  static Future<LibertyLibrary?> _readCached(Directory dir, String key) async {
    final file = File(p.join(dir.path, 'lib-$key.json'));
    try {
      if (!file.existsSync()) return null;
      final json = jsonDecode(await file.readAsString());
      return LibertyLibrary.fromJson(json as Map<String, Object?>);
    } on Object {
      return null;
    }
  }

  static Future<void> _writeCached(
    Directory dir,
    String key,
    LibertyLibrary library,
  ) async {
    try {
      await _writeAtomically(
        File(p.join(dir.path, 'lib-$key.json')),
        jsonEncode(library.toJson()),
      );
    } on Object {
      // Best effort: a failed write is a re-parse next time.
    }
  }

  /// Writes through a temporary sibling and renames, so a concurrent
  /// elaboration never reads half a file.
  static Future<void> _writeAtomically(File file, String contents) async {
    final tmp = File(
      '${file.path}.$pid-${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    await tmp.writeAsString(contents, flush: true);
    await tmp.rename(file.path);
  }

  /// Removes the oldest cache files beyond [maxCacheFiles], never one in
  /// [keep]: the files the elaboration about to run reads.
  void _prune(Directory dir, {required Set<String> keep}) {
    try {
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => !f.path.endsWith('.tmp') && !keep.contains(f.path))
          .toList();
      final budget = maxCacheFiles - keep.length;
      if (files.length <= budget) return;
      final stamped = <(File, DateTime)>[
        for (final f in files) (f, f.statSync().modified),
      ]..sort((a, b) => a.$2.compareTo(b.$2));
      for (final (file, _) in stamped.take(
        files.length - (budget < 0 ? 0 : budget),
      )) {
        try {
          file.deleteSync();
        } on Object {
          // Another elaboration may have pruned it already.
        }
      }
    } on Object {
      // Pruning is best effort.
    }
  }
}
