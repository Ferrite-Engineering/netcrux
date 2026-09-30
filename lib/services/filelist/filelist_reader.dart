// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_io/crux_io.dart';
import 'package:meta/meta.dart';
import 'package:netcrux/domain/models/project/netcrux_project.dart';
import 'package:path/path.dart' as p;

/// Thrown when a `.f` filelist references itself (directly or
/// transitively through nested `-f` includes).
@immutable
class FilelistCycleException implements Exception {
  /// Creates a cycle exception. [cyclePath] is the chain that led
  /// back to a previously-visited filelist, leftmost-first.
  const FilelistCycleException(this.cyclePath);

  /// Filelist paths in the order they were entered, with the
  /// repeated entry at the tail.
  final List<String> cyclePath;

  @override
  String toString() => 'FilelistCycleException: ${cyclePath.join(' -> ')}';
}

/// Thrown when a `.f` line references a nested `-f` filelist that
/// cannot be found on disk.
@immutable
class FilelistNotFoundException implements Exception {
  /// Creates a not-found exception.
  const FilelistNotFoundException(this.referencedPath, this.parentPath);

  /// Path that the `.f` file tried to include.
  final String referencedPath;

  /// Path of the `.f` file that contained the offending `-f` line.
  final String parentPath;

  @override
  String toString() =>
      'FilelistNotFoundException: $referencedPath '
      '(referenced from $parentPath)';
}

/// Parsed contents of a Vivado-style `.f` filelist, kept as a
/// neutral intermediate before [FilelistReader.toProject] materializes
/// a [NetcruxProject].
@immutable
class FilelistContents {
  /// Creates a filelist-contents record.
  const FilelistContents({
    required this.sourceFiles,
    required this.defines,
    required this.includePaths,
  });

  /// HDL source paths in declaration order, resolved to absolute
  /// when possible.
  final List<String> sourceFiles;

  /// `+define+NAME[=VALUE]` records. Empty-value defines map to an
  /// empty string (matching [NetcruxProject.defines]).
  final Map<String, String> defines;

  /// `+incdir+PATH` directories, in declaration order.
  final List<String> includePaths;
}

/// Reads Vivado-style `.f` filelists.
///
/// Supported syntax (per Vivado UG973 / common simulator convention):
///
/// - **Source files**: any bare line that is not a flag is treated
///   as an HDL source path. Relative paths resolve against the
///   filelist's directory.
/// - **`+define+NAME` / `+define+NAME=VALUE`**: preprocessor define.
///   Multiple `+define+` segments may appear on one line.
/// - **`+incdir+PATH`**: include directory. Multiple `+incdir+`
///   segments may appear on one line.
/// - **`-f <other>.f`**: nested filelist, processed recursively.
///   Cycles are detected and reported as [FilelistCycleException].
/// - **Comments**: `// line comment` and `# line comment` strip the
///   rest of the line.
/// - **Environment-variable expansion**: `$VAR` and `${VAR}` expand
///   from the process environment (or from [environmentOverride]
///   for testing). Unset variables expand to the empty string —
///   matching Vivado's behaviour.
///
/// Out of scope (matches Vivado's behaviour but documented here so
/// users have an expectation): library-search paths (`-y <dir>`),
/// library-extension overrides (`+libext+`), and `--top`. Pro and
/// Enterprise overlays can extend the reader by composing it; the
/// open-core surface is intentionally small.
class FilelistReader {
  /// Creates a filelist reader. Tests inject [environmentOverride]
  /// to make environment-variable expansion deterministic.
  const FilelistReader({
    this.environmentOverride,
  });

  /// Replacement for [Platform.environment]. When `null`, the real
  /// process environment is used.
  final Map<String, String>? environmentOverride;

  Map<String, String> get _env => environmentOverride ?? Platform.environment;

  /// Reads the filelist at [path] and returns its parsed contents.
  /// Throws [FileSystemException] when the root file is missing,
  /// [FilelistCycleException] on a recursion cycle, and
  /// [FilelistNotFoundException] when a nested `-f` cannot be
  /// resolved.
  Future<FilelistContents> read(String path) async {
    final visited = <String>{};
    final stack = <String>[];
    return await _readInternal(path, visited: visited, stack: stack);
  }

  /// Convenience: read the filelist at [path] and materialise it as
  /// a [NetcruxProject] in one call. Equivalent to
  /// `toProject(await read(path))`.
  Future<NetcruxProject> readAsProject(String path) async {
    final contents = await read(path);
    return toProject(contents);
  }

  /// Materializes [contents] as a [NetcruxProject] with the
  /// current schema version. Source order, define order, and
  /// include order are preserved as-is — the reader has already
  /// resolved nested `-f` files so the caller doesn't need to.
  NetcruxProject toProject(FilelistContents contents) {
    return NetcruxProject.create(
      sourceFiles: contents.sourceFiles,
      defines: contents.defines,
      includePaths: contents.includePaths,
    );
  }

  Future<FilelistContents> _readInternal(
    String path, {
    required Set<String> visited,
    required List<String> stack,
  }) async {
    final resolved = _normalize(path);
    // The identity key only decides whether this filelist was entered
    // before; the stack, the file opened and every path read out of it keep
    // the spelling the user wrote.
    if (!visited.add(canonicalPathKey(resolved))) {
      throw FilelistCycleException(<String>[...stack, resolved]);
    }
    stack.add(resolved);
    final file = File(resolved);
    if (!file.existsSync()) {
      // For the root, we let FileSystemException propagate naturally
      // by attempting the read; this only fires from nested `-f`s.
      throw FilelistNotFoundException(
        path,
        stack.length > 1 ? stack[stack.length - 2] : path,
      );
    }
    final lines = await file.readAsLines();
    final dir = p.dirname(resolved);
    final sources = <String>[];
    final defines = <String, String>{};
    final includes = <String>[];

    for (final rawLine in lines) {
      final line = _stripComment(rawLine).trim();
      if (line.isEmpty) continue;
      final tokens = _tokenize(line);
      for (var i = 0; i < tokens.length; i++) {
        final token = _expandEnv(tokens[i]);
        if (token.isEmpty) continue;
        if (token == '-f') {
          // Next token is the nested filelist path.
          if (i + 1 >= tokens.length) continue;
          final nested = _expandEnv(tokens[i + 1]);
          final nestedAbs = _resolveRelative(dir, nested);
          final nestedContents = await _readInternal(
            nestedAbs,
            visited: visited,
            stack: stack,
          );
          sources.addAll(nestedContents.sourceFiles);
          for (final entry in nestedContents.defines.entries) {
            defines[entry.key] = entry.value;
          }
          includes.addAll(nestedContents.includePaths);
          i++; // consume the next token
          continue;
        }
        if (token.startsWith('+define+')) {
          _parseDefineSegments(token, defines);
          continue;
        }
        if (token.startsWith('+incdir+')) {
          _parseIncdirSegments(token, dir, includes);
          continue;
        }
        if (token.startsWith('-')) {
          // Unrecognized flag — skip silently so a stray Vivado knob
          // doesn't fail the import (`-sv`, `-svlog`, etc.). Future
          // additions wire here.
          continue;
        }
        // Bare token = source file path.
        sources.add(_resolveRelative(dir, token));
      }
    }

    stack.removeLast();
    return FilelistContents(
      sourceFiles: List<String>.unmodifiable(sources),
      defines: Map<String, String>.unmodifiable(defines),
      includePaths: List<String>.unmodifiable(includes),
    );
  }

  /// Absolute and normalized, with its case kept. `p.canonicalize` would
  /// also lowercase on Windows, and these strings become the project's
  /// source list, which the user sees and Yosys opens.
  String _normalize(String path) => p.normalize(p.absolute(path));

  String _resolveRelative(String baseDir, String token) {
    if (p.isAbsolute(token)) return _normalize(token);
    return _normalize(p.join(baseDir, token));
  }

  String _stripComment(String line) {
    final slashIdx = line.indexOf('//');
    final hashIdx = line.indexOf('#');
    // Either marker terminates the line. Pick the earliest one
    // (when both are present).
    int cut;
    if (slashIdx < 0 && hashIdx < 0) {
      cut = line.length;
    } else if (slashIdx < 0) {
      cut = hashIdx;
    } else if (hashIdx < 0) {
      cut = slashIdx;
    } else {
      cut = slashIdx < hashIdx ? slashIdx : hashIdx;
    }
    return line.substring(0, cut);
  }

  List<String> _tokenize(String line) {
    // Vivado uses simple whitespace tokenisation. We do the same —
    // no quoting support (paths with spaces are not addressable
    // through Vivado's filelist convention either).
    return line.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
  }

  String _expandEnv(String token) {
    // Replace `${VAR}` first to avoid `$VAR_X` ambiguities, then
    // bare `$VAR` (alphanumeric / underscore).
    return token
        .replaceAllMapped(
          RegExp(r'\$\{([A-Za-z_][A-Za-z0-9_]*)\}'),
          (m) => _env[m.group(1)!] ?? '',
        )
        .replaceAllMapped(
          RegExp(r'\$([A-Za-z_][A-Za-z0-9_]*)'),
          (m) => _env[m.group(1)!] ?? '',
        );
  }

  void _parseDefineSegments(String token, Map<String, String> defines) {
    // Token looks like `+define+NAME` or
    // `+define+NAME=VALUE+define+OTHER=VAL`. We strip the leading
    // `+define+`, split on subsequent `+define+` markers, and
    // accept bare `+` separators (some toolchains chain via `+`).
    final body = token.substring('+define+'.length);
    final segments = body.split('+define+');
    for (final segment in segments) {
      if (segment.isEmpty) continue;
      // Stop at the next `+...+` flag — e.g. `WIDTH=32+incdir+inc`.
      // We split only on the documented `+define+` boundary above;
      // any trailing `+...` is the simulator's problem.
      final eq = segment.indexOf('=');
      if (eq < 0) {
        defines[segment] = '';
      } else {
        defines[segment.substring(0, eq)] = segment.substring(eq + 1);
      }
    }
  }

  void _parseIncdirSegments(
    String token,
    String baseDir,
    List<String> includes,
  ) {
    final body = token.substring('+incdir+'.length);
    final segments = body.split('+incdir+');
    for (final segment in segments) {
      if (segment.isEmpty) continue;
      includes.add(_resolveRelative(baseDir, segment));
    }
  }
}
