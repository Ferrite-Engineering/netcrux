// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:netcrux/domain/enums/netcrux_source_language.dart';

/// Schema version constants for `.netcrux` project files.
///
/// Bumped when the file format changes incompatibly. Unknown versions
/// are rejected at load with a snackbar (see [NetcruxProjectFileReader]).
const int kNetcruxProjectVersion = 1;

/// Filename extension (without the leading dot) for `.netcrux`
/// project files. Used for both the file picker filter and for
/// detecting project intent on the CLI.
const String kNetcruxProjectExtension = 'netcrux-project';

/// On-disk representation of a NetCrux **project**.
///
/// A project is a *durable, version-controllable* description of an
/// HDL design — its source files, top module, defines, include
/// paths, and the engine-tuning knobs (Yosys command extras, lower
/// vs. preserve-hierarchy mode) the elaboration backend needs. It
/// is the input to the elaboration pipeline.
///
/// Distinct from [`NetcruxSession`] — sessions are *ephemeral viewer
/// state* (camera, current scope, selection, expanded tree rows)
/// keyed off a project. A given project may be exercised by many
/// session snapshots over its lifetime; a project can also stand on
/// its own (open a project → fresh viewer state).
///
/// **Forward compatibility.** Unknown JSON fields are silently
/// ignored on read. Unknown [version] integers are rejected by
/// [NetcruxProjectFileReader.fromJson] with a
/// [NetcruxProjectVersionException]. Adding a new field to v1 is
/// always non-breaking — older readers ignore it, newer readers
/// populate it when present.
///
/// Pure data, no Flutter imports — lives under `lib/domain/models/`.
@immutable
class NetcruxProject {
  /// Creates a project. Caller is responsible for passing absolute
  /// (or project-root-relative) paths — the on-disk format accepts
  /// either; the elaboration pipeline normalises before use.
  const NetcruxProject({
    required this.version,
    required this.sourceFiles,
    required this.topModule,
    required this.defines,
    required this.includePaths,
    required this.extraYosysCommands,
    required this.lowerToStructural,
    this.sourceFileLanguages = const <String, NetcruxSourceLanguage>{},
  });

  /// Convenience constructor — produces a v1 project with the
  /// current schema version pre-filled and empty defaults for the
  /// optional fields. Used by the welcome screen / file-import
  /// flow when the user only supplies a source list.
  factory NetcruxProject.create({
    required List<String> sourceFiles,
    String topModule = '',
    Map<String, String> defines = const <String, String>{},
    List<String> includePaths = const <String>[],
    List<String> extraYosysCommands = const <String>[],
    bool lowerToStructural = false,
    Map<String, NetcruxSourceLanguage> sourceFileLanguages =
        const <String, NetcruxSourceLanguage>{},
  }) {
    return NetcruxProject(
      version: kNetcruxProjectVersion,
      sourceFiles: List<String>.unmodifiable(sourceFiles),
      topModule: topModule,
      defines: Map<String, String>.unmodifiable(defines),
      includePaths: List<String>.unmodifiable(includePaths),
      extraYosysCommands: List<String>.unmodifiable(extraYosysCommands),
      lowerToStructural: lowerToStructural,
      sourceFileLanguages: Map<String, NetcruxSourceLanguage>.unmodifiable(
        sourceFileLanguages,
      ),
    );
  }

  /// Schema version. Must equal [kNetcruxProjectVersion] for a file
  /// to load — older / newer versions surface as a snackbar.
  final int version;

  /// Ordered list of HDL source paths. Order matters because some
  /// tools (Verilator, Yosys) resolve `include` files relative to
  /// the order seen.
  final List<String> sourceFiles;

  /// Name of the top module, or empty when the elaboration backend
  /// should auto-detect (matches the `--top` knob on common
  /// simulators). Reader / writer round-trip the empty string
  /// rather than `null` so the JSON shape stays consistent.
  final String topModule;

  /// Preprocessor defines passed to the elaboration backend.
  /// `{'WIDTH': '32', 'FAST': ''}` becomes `+define+WIDTH=32`
  /// `+define+FAST` in a Vivado-style filelist. Empty-value entries
  /// are emitted as flag-only defines.
  final Map<String, String> defines;

  /// `+incdir+` directories. Order is preserved (the simulator
  /// resolves earlier entries first).
  final List<String> includePaths;

  /// Extra Yosys commands appended after `read_verilog ... hierarchy`
  /// but before `write_json`. Power users set this to e.g.
  /// `['proc', 'opt', 'memory']` to force lowering, or `['flatten']`
  /// to collapse the design.
  final List<String> extraYosysCommands;

  /// When `true`, the elaboration pipeline runs the full structural
  /// lowering passes (`proc; opt; memory; opt`) — closer to
  /// Vivado's *Synthesized Design* view. When `false`, only
  /// `hierarchy` runs and behavioural blocks survive as black-box
  /// cells — closer to *Elaborated Design*.
  final bool lowerToStructural;

  /// Per-source-file language overrides keyed by the absolute path
  /// (the same string that appears in [sourceFiles]). Paths absent
  /// from this map fall back to extension-based auto-detection;
  /// callers that need every path explicit map them to
  /// [NetcruxSourceLanguage.auto] (semantically equivalent to absent).
  ///
  /// Mirrors LintCrux's `LintProject.sourceFileLanguages` for schema
  /// portability — a future cross-suite "ProjectModel" promotion does
  /// not have to rename this field.
  final Map<String, NetcruxSourceLanguage> sourceFileLanguages;

  /// Returns the resolved language for [path]: the explicit override
  /// from [sourceFileLanguages] when present and not [auto], otherwise
  /// inferred from the file extension. Case-insensitive extension
  /// match; unknown extensions fall back to SystemVerilog (the
  /// superset Yosys's `read_verilog -sv` accepts).
  NetcruxSourceLanguage resolveLanguage(String path) {
    final explicit = sourceFileLanguages[path];
    if (explicit != null && explicit != NetcruxSourceLanguage.auto) {
      return explicit;
    }
    return inferLanguageFromExtension(path);
  }

  /// Whether this project is a pre-built Yosys JSON netlist rather than HDL
  /// to elaborate: exactly one "source", and it is a `.json` document.
  ///
  /// A netlist written by `yosys write_json` (or exported by NetCrux itself)
  /// is already elaborated, so the pipeline parses it directly and never
  /// probes for or runs Yosys. Carrying it as the single source keeps every
  /// consumer of [sourceFiles] — the status bar, the file watcher, session
  /// and workspace persistence — working unchanged for a netlist tab.
  bool get isPrebuiltNetlist =>
      sourceFiles.length == 1 && isNetlistJsonPath(sourceFiles.single);

  /// Whether [location] names a Yosys JSON netlist: a `.json` suffix,
  /// case-insensitive. A URL's query string and fragment are ignored, so
  /// `https://host/top.json?rev=3` qualifies.
  static bool isNetlistJsonPath(String location) {
    var end = location.length;
    final query = location.indexOf('?');
    if (query >= 0) end = query;
    final fragment = location.indexOf('#');
    if (fragment >= 0 && fragment < end) end = fragment;
    return location.substring(0, end).toLowerCase().endsWith('.json');
  }

  /// The short name to show for a source [location]: a file path's base
  /// name, or for a URL its last path segment — unless the URL carries a
  /// fragment, which is the name the browser upload attached to a `blob:`
  /// URL whose own path is an opaque id.
  static String locationLabel(String location) {
    final uri = Uri.tryParse(location);
    // A one-letter scheme is a Windows drive (`C:\rtl\top.v`), not a URL.
    if (uri != null && uri.scheme.length > 1) {
      if (uri.fragment.isNotEmpty) return Uri.decodeComponent(uri.fragment);
      final segments = uri.pathSegments.where((s) => s.isNotEmpty);
      if (segments.isNotEmpty && uri.scheme != 'blob') return segments.last;
    }
    final normalized = location.replaceAll(r'\', '/');
    return normalized.substring(normalized.lastIndexOf('/') + 1);
  }

  /// Pure extension → language helper. Public so tests and the
  /// elaboration backend can call it without instantiating a project.
  static NetcruxSourceLanguage inferLanguageFromExtension(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.vhd') || lower.endsWith('.vhdl')) {
      return NetcruxSourceLanguage.vhdl;
    }
    if (lower.endsWith('.sv') || lower.endsWith('.svh')) {
      return NetcruxSourceLanguage.systemVerilog;
    }
    if (lower.endsWith('.v') || lower.endsWith('.vh')) {
      return NetcruxSourceLanguage.verilog;
    }
    return NetcruxSourceLanguage.systemVerilog;
  }

  /// Empty (no source files) project — used as the welcome-screen
  /// scaffold and as the no-op return for [NetcruxProjectFileReader]
  /// errors that the UI can recover from.
  static const NetcruxProject empty = NetcruxProject(
    version: kNetcruxProjectVersion,
    sourceFiles: <String>[],
    topModule: '',
    defines: <String, String>{},
    includePaths: <String>[],
    extraYosysCommands: <String>[],
    lowerToStructural: false,
  );

  /// Returns a copy with selected fields replaced. Pass `null` to
  /// leave the existing value; pass an explicit empty collection to
  /// clear.
  NetcruxProject copyWith({
    int? version,
    List<String>? sourceFiles,
    String? topModule,
    Map<String, String>? defines,
    List<String>? includePaths,
    List<String>? extraYosysCommands,
    bool? lowerToStructural,
    Map<String, NetcruxSourceLanguage>? sourceFileLanguages,
  }) {
    return NetcruxProject(
      version: version ?? this.version,
      sourceFiles: sourceFiles == null
          ? this.sourceFiles
          : List<String>.unmodifiable(sourceFiles),
      topModule: topModule ?? this.topModule,
      defines: defines == null
          ? this.defines
          : Map<String, String>.unmodifiable(defines),
      includePaths: includePaths == null
          ? this.includePaths
          : List<String>.unmodifiable(includePaths),
      extraYosysCommands: extraYosysCommands == null
          ? this.extraYosysCommands
          : List<String>.unmodifiable(extraYosysCommands),
      lowerToStructural: lowerToStructural ?? this.lowerToStructural,
      sourceFileLanguages: sourceFileLanguages == null
          ? this.sourceFileLanguages
          : Map<String, NetcruxSourceLanguage>.unmodifiable(
              sourceFileLanguages,
            ),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! NetcruxProject) return false;
    if (other.version != version) return false;
    if (other.topModule != topModule) return false;
    if (other.lowerToStructural != lowerToStructural) return false;
    if (!_listEquals(other.sourceFiles, sourceFiles)) return false;
    if (!_listEquals(other.includePaths, includePaths)) return false;
    if (!_listEquals(other.extraYosysCommands, extraYosysCommands)) {
      return false;
    }
    if (!_mapEquals(other.defines, defines)) return false;
    if (!_languageMapEquals(
      other.sourceFileLanguages,
      sourceFileLanguages,
    )) {
      return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    version,
    topModule,
    lowerToStructural,
    Object.hashAll(sourceFiles),
    Object.hashAll(includePaths),
    Object.hashAll(extraYosysCommands),
    Object.hashAllUnordered(
      defines.entries.map((e) => Object.hash(e.key, e.value)),
    ),
    Object.hashAllUnordered(
      sourceFileLanguages.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool _mapEquals(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      final other = b[entry.key];
      if (other == null && !b.containsKey(entry.key)) return false;
      if (other != entry.value) return false;
    }
    return true;
  }

  static bool _languageMapEquals(
    Map<String, NetcruxSourceLanguage> a,
    Map<String, NetcruxSourceLanguage> b,
  ) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      final other = b[entry.key];
      if (other == null && !b.containsKey(entry.key)) return false;
      if (other != entry.value) return false;
    }
    return true;
  }
}
