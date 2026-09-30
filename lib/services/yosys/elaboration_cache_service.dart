// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:netcrux/domain/models/elaboration_cache_key.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';

/// One cached elaboration: the fully-parsed immutable [model], the run's
/// [stderr] (so the Tab Diagnostics drawer shows the same warnings a
/// live run would), and an [approxBytes] size proxy (the raw
/// `write_json` length) driving the cache's byte budget.
class ElaborationCacheEntry {
  /// Creates an entry.
  const ElaborationCacheEntry({
    required this.model,
    required this.stderr,
    required this.approxBytes,
  });

  /// The parsed netlist. Immutable, so sharing the instance between the
  /// cache and live providers is safe — and means caching the CURRENT
  /// design costs no extra memory (same object).
  final NetlistModel model;

  /// Yosys stderr from the run that produced [model].
  final String stderr;

  /// Size proxy for the byte budget — the raw `write_json` document
  /// length that was parsed into [model].
  final int approxBytes;
}

/// In-memory LRU cache of parsed elaboration results keyed by
/// [ElaborationCacheKey] (path + size + mtime per source file, plus
/// yosys version / top module / defines / include paths / extra
/// commands). A re-open of the same source files with the same options
/// and yosys version returns the cached model without spawning yosys or
/// re-parsing — that is what makes a sub-50 ms
/// cache-hit round-trip reachable for large designs (a raw-JSON
/// cache would still pay the multi-second parse on every hit).
///
/// Bounded two ways: [maxEntries] (LRU count) and [maxTotalBytes] (sum
/// of entry [ElaborationCacheEntry.approxBytes]); either limit evicts in
/// least-recently-used order, but never the entry being stored — a
/// single oversized design still caches (its model is alive in the
/// provider anyway, so retaining it costs nothing extra).
///
/// Known, accepted fingerprint limitation: `include`d files reached via
/// [ElaborationCacheKey.includePaths] are not stat'ed individually —
/// editing only an included header does not change the key. The per-tab
/// source watcher shares the same blind spot; both resolve together if
/// include expansion ever lands.
///
/// The cache is strictly in-memory. A disk-backed layer that survives
/// app restarts would add little, since the in-memory bound already makes
/// "open the same project twice in a session" fast, which is the
/// workflow that motivated the cache.
class ElaborationCacheService {
  /// Creates a cache with the given bounds.
  ElaborationCacheService({
    this.maxEntries = 32,
    this.maxTotalBytes = 256 * 1024 * 1024,
  });

  /// Maximum number of entries retained.
  final int maxEntries;

  /// Maximum summed [ElaborationCacheEntry.approxBytes] retained.
  final int maxTotalBytes;

  /// `LinkedHashMap` preserves insertion order; the LRU eviction policy
  /// is implemented by removing and re-inserting on read.
  final Map<String, ElaborationCacheEntry> _store =
      <String, ElaborationCacheEntry>{};

  int _totalBytes = 0;

  /// Number of entries currently cached.
  int get length => _store.length;

  /// Summed [ElaborationCacheEntry.approxBytes] across the cache.
  int get totalBytes => _totalBytes;

  /// Returns the cached entry for [key], or `null` if there's no entry.
  /// Access counts as a "recent use" — the entry moves to the LRU tail.
  ElaborationCacheEntry? lookup(ElaborationCacheKey key) {
    final canonical = key.canonicalKey;
    final value = _store.remove(canonical);
    if (value == null) return null;
    _store[canonical] = value;
    return value;
  }

  /// Stores [entry] under [key], evicting least-recently-used entries
  /// while either bound is exceeded (the just-stored entry is exempt).
  void store(ElaborationCacheKey key, ElaborationCacheEntry entry) {
    final canonical = key.canonicalKey;
    final previous = _store.remove(canonical);
    if (previous != null) _totalBytes -= previous.approxBytes;
    _store[canonical] = entry;
    _totalBytes += entry.approxBytes;
    while (_store.length > 1 &&
        (_store.length > maxEntries || _totalBytes > maxTotalBytes)) {
      final oldest = _store.keys.first;
      final evicted = _store.remove(oldest);
      _totalBytes -= evicted!.approxBytes;
    }
  }

  /// Removes the entry for [key], if any.
  void invalidate(ElaborationCacheKey key) {
    final removed = _store.remove(key.canonicalKey);
    if (removed != null) _totalBytes -= removed.approxBytes;
  }

  /// Clears every entry. Used by tests; a user-facing "Clear Cache"
  /// action can route here when one lands.
  void clear() {
    _store.clear();
    _totalBytes = 0;
  }

  /// Builds an [ElaborationCacheKey] for the given inputs by stat'ing
  /// each source file on disk (async — this runs inside the elaboration
  /// provider's `build()` on the UI isolate, same convention as its
  /// size-estimate pass).
  ///
  /// Returns `null` if any source file does not exist — the caller
  /// shouldn't try to cache an invalid request. Stat failures other
  /// than "not found" also yield `null` (never cache what can't be
  /// fingerprinted).
  static Future<ElaborationCacheKey?> buildKey({
    required List<String> sourceFilePaths,
    required String yosysVersion,
    String? topModule,
    List<String> defines = const <String>[],
    List<String> includePaths = const <String>[],
    List<String> extraCommands = const <String>[],
  }) async {
    final files = <ElaborationCacheFile>[];
    for (final path in sourceFilePaths) {
      try {
        // Async stat by convention — see LoadedNetlist._estimateSize.
        // ignore: avoid_slow_async_io
        final stat = await File(path).stat();
        if (stat.type == FileSystemEntityType.notFound) return null;
        files.add(
          ElaborationCacheFile(
            path: path,
            sizeBytes: stat.size,
            modifiedMicroseconds: stat.modified.microsecondsSinceEpoch,
          ),
        );
      } on FileSystemException {
        return null;
      }
    }
    return ElaborationCacheKey(
      files: files,
      yosysVersion: yosysVersion,
      topModule: topModule,
      defines: defines,
      includePaths: includePaths,
      extraCommands: extraCommands,
    );
  }
}
