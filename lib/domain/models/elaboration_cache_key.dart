// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// Per-file fingerprint used to detect whether a cached elaboration is
/// still valid for a given source file: path + size + last-modified
/// microseconds. File contents are not hashed, so an edit that preserves
/// both size and mtime is not detected.
@immutable
class ElaborationCacheFile {
  /// Creates a fingerprint.
  const ElaborationCacheFile({
    required this.path,
    required this.sizeBytes,
    required this.modifiedMicroseconds,
  });

  /// Absolute or canonical path of the source file.
  final String path;

  /// Size of the file in bytes at the moment of fingerprinting.
  final int sizeBytes;

  /// `lastModifiedSync().microsecondsSinceEpoch` at the moment of
  /// fingerprinting. Detects edits down to the microsecond on POSIX
  /// hosts.
  final int modifiedMicroseconds;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ElaborationCacheFile &&
          other.path == path &&
          other.sizeBytes == sizeBytes &&
          other.modifiedMicroseconds == modifiedMicroseconds);

  @override
  int get hashCode => Object.hash(path, sizeBytes, modifiedMicroseconds);

  @override
  String toString() =>
      'ElaborationCacheFile($path, $sizeBytes bytes, $modifiedMicroseconds)';
}

/// Composite cache key for one elaboration. Covers everything that can
/// change the resulting Yosys JSON: the source files (with their
/// fingerprints), the requested top module, defines, include paths,
/// extra Yosys commands, and the yosys version banner.
@immutable
class ElaborationCacheKey {
  /// Creates a key. Lists are stored as immutable copies so callers
  /// cannot mutate the key after construction.
  ElaborationCacheKey({
    required List<ElaborationCacheFile> files,
    required this.yosysVersion,
    this.topModule,
    List<String> defines = const <String>[],
    List<String> includePaths = const <String>[],
    List<String> extraCommands = const <String>[],
  }) : files = List<ElaborationCacheFile>.unmodifiable(files),
       defines = List<String>.unmodifiable(defines),
       includePaths = List<String>.unmodifiable(includePaths),
       extraCommands = List<String>.unmodifiable(extraCommands);

  /// Per-file fingerprints. Order matters because Verilog elaboration
  /// can be order-sensitive (parameter overrides, defparam).
  final List<ElaborationCacheFile> files;

  /// Optional top module name passed to `hierarchy -top`.
  final String? topModule;

  /// Preprocessor defines, in the same order they were passed to the
  /// runner.
  final List<String> defines;

  /// Include search paths.
  final List<String> includePaths;

  /// Extra Yosys script commands inserted between `proc` and
  /// `write_json`.
  final List<String> extraCommands;

  /// The yosys `-V` banner. A new yosys version invalidates the cache.
  final String yosysVersion;

  /// A canonical string form suitable for use as a map key.
  String get canonicalKey {
    final buf = StringBuffer('yosys=$yosysVersion;');
    if (topModule != null) buf.write('top=$topModule;');
    buf
      ..write('def=[${defines.join(',')}];')
      ..write('inc=[${includePaths.join(',')}];')
      ..write('cmd=[${extraCommands.join(',')}];')
      ..write('files=[');
    for (final f in files) {
      buf.write('${f.path}@${f.modifiedMicroseconds}:${f.sizeBytes},');
    }
    buf.write(']');
    return buf.toString();
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ElaborationCacheKey) return false;
    return other.canonicalKey == canonicalKey;
  }

  @override
  int get hashCode => canonicalKey.hashCode;

  @override
  String toString() =>
      'ElaborationCacheKey(${canonicalKey.substring(0, canonicalKey.length.clamp(0, 80))}...)';
}
