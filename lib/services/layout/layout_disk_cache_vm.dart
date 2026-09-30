// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:netcrux/services/layout/elk_layout_service.dart'
    show LayoutDiskCache;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// VM / desktop disk-backed layout cache, rooted at the OS app-support
/// directory. Selected by the conditional import in
/// `elk_layout_service_provider.dart` whenever `dart.library.io` is available.
LayoutDiskCache createDefaultLayoutDiskCache() =>
    FileLayoutDiskCache(getApplicationSupportDirectory);

/// Persists solved layouts as gzipped JSON under
/// `<appSupport>/layout-cache/<key>.json.gz`, FIFO-pruned to [maxEntries] so
/// the corpus stays bounded (a single dense-core layout is ~1 MB gzipped).
///
/// Every operation is **best-effort**: a read degrades to a cache miss and a
/// write to a no-op on any I/O error, so a broken or read-only cache
/// directory never breaks the schematic — it just falls back to re-solving.
class FileLayoutDiskCache implements LayoutDiskCache {
  /// Creates a cache rooted under [baseDirectory] (resolved lazily on first
  /// use, then memoised).
  FileLayoutDiskCache(this.baseDirectory, {this.maxEntries = 64});

  /// Resolves the OS directory the `layout-cache/` subfolder lives under.
  final Future<Directory> Function() baseDirectory;

  /// Maximum number of cached layout files retained; the oldest are pruned.
  final int maxEntries;

  Future<Directory?>? _dir;

  Future<Directory?> _resolve() => _dir ??= _create();

  Future<Directory?> _create() async {
    try {
      final base = await baseDirectory();
      final dir = Directory(p.join(base.path, 'layout-cache'));
      await dir.create(recursive: true);
      return dir;
    } on Object {
      return null;
    }
  }

  @override
  Future<String?> read(String key) async {
    final dir = await _resolve();
    if (dir == null) return null;
    final file = File(p.join(dir.path, '$key.json.gz'));
    try {
      if (!file.existsSync()) return null;
      return utf8.decode(gzip.decode(await file.readAsBytes()));
    } on Object {
      return null;
    }
  }

  @override
  Future<void> write(String key, String value) async {
    final dir = await _resolve();
    if (dir == null) return;
    try {
      final bytes = gzip.encode(utf8.encode(value));
      // Write to a temp sibling then atomically rename, so a crash or a
      // concurrent reader never sees a half-written cache file.
      final tmp = File(p.join(dir.path, '$key.json.gz.tmp'));
      await tmp.writeAsBytes(bytes, flush: true);
      await tmp.rename(p.join(dir.path, '$key.json.gz'));
      _prune(dir);
    } on Object {
      // Best-effort cache — a failed write just means a future miss.
    }
  }

  void _prune(Directory dir) {
    try {
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json.gz'))
          .toList();
      if (files.length <= maxEntries) return;
      files.sort(
        (a, b) => a.statSync().modified.compareTo(b.statSync().modified),
      );
      for (final file in files.take(files.length - maxEntries)) {
        try {
          file.deleteSync();
        } on Object {
          // Ignore — another run may have already pruned it.
        }
      }
    } on Object {
      // Pruning is best-effort.
    }
  }
}
