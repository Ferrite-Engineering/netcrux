// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:netcrux/domain/enums/netcrux_source_language.dart';
import 'package:netcrux/domain/models/project/netcrux_project.dart';

/// Thrown when a `.netcrux` file is structurally invalid — missing
/// the `version` field, root that's not a JSON object, etc.
@immutable
class NetcruxProjectFormatException implements Exception {
  /// Creates a format exception.
  const NetcruxProjectFormatException(this.message);

  /// One-line human-readable summary used in the snackbar.
  final String message;

  @override
  String toString() => 'NetcruxProjectFormatException: $message';
}

/// Thrown when the file carries a `version` integer that this build
/// does not know how to read.
@immutable
class NetcruxProjectVersionException implements Exception {
  /// Creates a version exception.
  const NetcruxProjectVersionException(this.version);

  /// The unknown version integer the file declared.
  final int version;

  @override
  String toString() => 'NetcruxProjectVersionException: version=$version';
}

/// Thrown when a `.netcrux-project` file carries an `extraYosysCommands`
/// entry that is not on the [kNetcruxSafeYosysCommands] allow-list.
///
/// A project file is untrusted input, and its extra commands run
/// automatically the moment the design is elaborated, so a command outside
/// the allow-list is refused rather than executed. [command] names the
/// offending command so the snackbar can tell the user exactly what was
/// rejected.
@immutable
class NetcruxProjectUnsafeCommandException implements Exception {
  /// Creates the exception for the rejected [command].
  const NetcruxProjectUnsafeCommandException(this.command);

  /// The offending token — the command name that is not allow-listed, or
  /// the whole entry when it smuggles a statement separator or quote.
  final String command;

  /// Human-readable, command-naming summary used in the snackbar.
  String get message =>
      'This project asks to run the custom Yosys command "$command", which '
      'is not one NetCrux runs automatically. The commands in a project file '
      'execute as soon as its design is elaborated, so only known-safe '
      'elaboration and optimization passes are allowed.';

  @override
  String toString() => 'NetcruxProjectUnsafeCommandException: $message';
}

/// Yosys script commands a `.netcrux-project` file may carry in its
/// `extraYosysCommands` field without an explicit trust decision.
///
/// A `.netcrux-project` is untrusted input — it is a registered document
/// type, so one arrives by download, by clone, or from a file someone
/// sent — and its `extraYosysCommands` are concatenated verbatim into the
/// `yosys -p` script that runs automatically when the design is
/// elaborated. Yosys's own script language includes commands that reach
/// out of the netlist and into the machine: `exec` and `shell` run
/// arbitrary programs, `tcl` / `script` / `plugin` execute code, and the
/// `read_*` / `write_*` / `tee` / `trace` / `setenv` families touch the
/// filesystem and environment. An unfiltered field is code execution on
/// open.
///
/// This is an **allow-list, and it fails closed**: a command that is not
/// named here is refused. A block-list of the unsafe commands would leak,
/// because Yosys gains commands between releases and a future
/// code-executing pass would slip past an old block-list. Membership is
/// therefore limited to pure, in-memory RTLIL transformations and
/// read-only inspection passes — a command belongs here only if it cannot
/// read or write a file, spawn a subprocess, execute a script, or load a
/// plugin. When in doubt, leave it off: an off-list command is still
/// reachable for a project the user has explicitly chosen to trust (see
/// [NetcruxProjectFileReader.allowUnsafeCommands]).
///
/// Only the command *name* (the first whitespace-delimited token of each
/// entry) is matched, so options are allowed through — every command here
/// is safe under any of its options, and any argument that could smuggle a
/// second statement (`;`, a newline, or a `"` that breaks the runner's
/// quoting) is rejected before the name is even looked up.
const Set<String> kNetcruxSafeYosysCommands = <String>{
  // Hierarchy & process lowering.
  'hierarchy', 'proc', 'proc_arst', 'proc_clean', 'proc_dff', 'proc_dlatch',
  'proc_init', 'proc_memwr', 'proc_mux', 'proc_prune', 'proc_rmdead',
  'proc_rom', 'flatten', 'uniquify', 'blackbox',
  // Optimization.
  'opt', 'opt_clean', 'opt_expr', 'opt_dff', 'opt_ffinv', 'opt_lut',
  'opt_lut_ins', 'opt_mem', 'opt_mem_feedback', 'opt_mem_priority',
  'opt_mem_widen', 'opt_merge', 'opt_muxtree', 'opt_reduce', 'opt_share',
  'opt_demorgan', 'opt_balance_tree', 'opt_hier', 'clean', 'clean_zerowidth',
  'peepopt', 'wreduce', 'onehot',
  // Memory (self-contained passes; the file-reading `memory_bram -rules`
  // and liberty-reading `memory_libmap` variants are deliberately absent).
  'memory', 'memory_bmux2rom', 'memory_collect', 'memory_dff', 'memory_map',
  'memory_memx', 'memory_narrow', 'memory_nordff', 'memory_share',
  'memory_unpack',
  // Finite state machines.
  'fsm', 'fsm_detect', 'fsm_expand', 'fsm_extract', 'fsm_info', 'fsm_map',
  'fsm_opt', 'fsm_recode',
  // Coarse-cell & mux transforms.
  'alumacc', 'booth', 'arith_tree', 'share', 'simplemap', 'pmuxtree',
  'muxpack', 'muxcover', 'pmux2shiftx', 'bmuxmap', 'bwmuxmap', 'demuxmap',
  'lut2mux', 'lut2bmux', 'maccmap', 'splitnets', 'splitcells', 'deminout',
  'rmports', 'tribuf', 'extract_fa', 'extract_reduce',
  // Flip-flop legalization.
  'dffunmap', 'dfflegalize', 'dffinit', 'zinit', 'async2sync', 'clk2fflogic',
  'formalff',
  // Attributes & naming (in-memory only).
  'autoname', 'rename', 'setattr', 'setparam', 'attrmap', 'attrmvcp',
  'paramap', 'chparam', 'setundef',
  // Read-only inspection & selection.
  'stat', 'check', 'check_mem', 'ls', 'ltp', 'scc', 'torder', 'printattrs',
  'portlist', 'select', 'cd',
};

/// Reads and writes `.netcrux-project` files.
///
/// The reader is forward-compatible: unknown fields are ignored,
/// missing optional fields fall back to documented defaults
/// (matching [NetcruxProject.empty]). The writer always emits the
/// current schema version and a stable field ordering — important
/// for diff-friendliness and reproducibility.
class NetcruxProjectFileReader {
  /// Const constructor. The reader is stateless apart from
  /// [allowUnsafeCommands].
  const NetcruxProjectFileReader({this.allowUnsafeCommands = false});

  /// When `false` (the default, and every shipping call), [fromJson]
  /// filters `extraYosysCommands` against [kNetcruxSafeYosysCommands] and
  /// throws [NetcruxProjectUnsafeCommandException] for anything off-list.
  ///
  /// When `true`, the field is honored whole — the seam a future
  /// workspace-trust decision flips for a project the user has explicitly
  /// trusted on this machine (the unit of trust being the project's own
  /// version-control root). It is `false` at every call site today so
  /// opening a file is fail-closed; nothing sets it to `true` outside
  /// tests.
  final bool allowUnsafeCommands;

  /// Loads a project from the file at [path]. Throws
  /// [NetcruxProjectFormatException] or
  /// [NetcruxProjectVersionException] on bad input; [FileSystemException]
  /// on I/O failure.
  Future<NetcruxProject> read(String path) async {
    final file = File(path);
    final text = await file.readAsString();
    return parse(text);
  }

  /// Parses [json] (a `.netcrux-project` JSON document) into a
  /// project. Exposed separately from [read] for unit tests and for
  /// the in-memory roundtrip helpers.
  NetcruxProject parse(String json) {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException catch (e) {
      throw NetcruxProjectFormatException('invalid JSON: ${e.message}');
    }
    if (decoded is! Map<String, Object?>) {
      throw const NetcruxProjectFormatException(
        'root must be a JSON object',
      );
    }
    return fromJson(decoded);
  }

  /// Converts a decoded JSON map to a project. Forward-compatible:
  /// unknown keys silently ignored; unknown version rejected.
  NetcruxProject fromJson(Map<String, Object?> json) {
    final version = json['version'];
    if (version is! int) {
      throw const NetcruxProjectFormatException(
        'missing or non-integer "version"',
      );
    }
    if (version != kNetcruxProjectVersion) {
      throw NetcruxProjectVersionException(version);
    }
    final extraYosysCommands = _readStringList(json['extraYosysCommands']);
    if (!allowUnsafeCommands) {
      _rejectUnsafeCommands(extraYosysCommands);
    }
    return NetcruxProject(
      version: version,
      sourceFiles: _readStringList(json['sourceFiles']),
      topModule: (json['topModule'] as String?) ?? '',
      defines: _readStringMap(json['defines']),
      includePaths: _readStringList(json['includePaths']),
      extraYosysCommands: extraYosysCommands,
      lowerToStructural: (json['lowerToStructural'] as bool?) ?? false,
      sourceFileLanguages: _readLanguageMap(json['sourceFileLanguages']),
    );
  }

  /// Refuses any `extraYosysCommands` entry that is not a known-safe pass.
  ///
  /// Each list entry is one Yosys statement. An entry is rejected up front
  /// if it embeds a statement separator (`;`, newline) or a double quote:
  /// the runner joins the list with `; ` and wraps paths in `"…"`, so those
  /// characters would let a vetted-looking first token carry an unvetted
  /// second command or break out of the quoting. Otherwise the entry's
  /// command name — its first whitespace-delimited token — must appear in
  /// [kNetcruxSafeYosysCommands].
  static void _rejectUnsafeCommands(List<String> commands) {
    for (final raw in commands) {
      if (raw.contains(';') ||
          raw.contains('\n') ||
          raw.contains('\r') ||
          raw.contains('"')) {
        throw NetcruxProjectUnsafeCommandException(raw.trim());
      }
      final name = _commandName(raw);
      if (!kNetcruxSafeYosysCommands.contains(name)) {
        throw NetcruxProjectUnsafeCommandException(
          name.isEmpty ? raw.trim() : name,
        );
      }
    }
  }

  /// The command name of a Yosys statement: its first whitespace-delimited
  /// token, with surrounding whitespace ignored. `''` for a blank entry.
  static String _commandName(String command) {
    final trimmed = command.trim();
    if (trimmed.isEmpty) return '';
    return trimmed.split(RegExp(r'\s+')).first;
  }

  /// Decodes the per-source-file language overrides map. Unknown
  /// language names are silently dropped (forward-compatibility — a
  /// future schema bump may add `vhdl-2019` or similar; older readers
  /// fall back to auto-detection for those entries).
  Map<String, NetcruxSourceLanguage> _readLanguageMap(Object? value) {
    if (value is! Map) return const <String, NetcruxSourceLanguage>{};
    final out = <String, NetcruxSourceLanguage>{};
    for (final entry in value.entries) {
      final key = entry.key;
      final v = entry.value;
      if (key is! String || v is! String) continue;
      final lang = _languageFromString(v);
      if (lang != null) out[key] = lang;
    }
    return Map<String, NetcruxSourceLanguage>.unmodifiable(out);
  }

  static NetcruxSourceLanguage? _languageFromString(String s) {
    switch (s) {
      case 'auto':
        return NetcruxSourceLanguage.auto;
      case 'verilog':
        return NetcruxSourceLanguage.verilog;
      case 'systemverilog':
        return NetcruxSourceLanguage.systemVerilog;
      case 'vhdl':
        return NetcruxSourceLanguage.vhdl;
      default:
        return null;
    }
  }

  List<String> _readStringList(Object? value) {
    if (value is! List) return const <String>[];
    return List<String>.unmodifiable(
      value.whereType<String>(),
    );
  }

  Map<String, String> _readStringMap(Object? value) {
    if (value is! Map) return const <String, String>{};
    final out = <String, String>{};
    for (final entry in value.entries) {
      final key = entry.key;
      final v = entry.value;
      if (key is String && v is String) {
        out[key] = v;
      }
    }
    return Map<String, String>.unmodifiable(out);
  }
}

/// Writes `.netcrux-project` files. Pretty-printed two-space indent
/// so projects diff cleanly in code review.
class NetcruxProjectFileWriter {
  /// Const constructor — the writer is stateless.
  const NetcruxProjectFileWriter();

  /// Serialises [project] to disk at [path]. Overwrites atomically
  /// via a temp-file-and-rename dance so a half-written file never
  /// replaces a known-good one.
  Future<void> write(String path, NetcruxProject project) async {
    final tempPath = '$path.tmp';
    final tempFile = File(tempPath);
    await tempFile.writeAsString(serialise(project));
    await tempFile.rename(path);
  }

  /// Serialises [project] to a pretty-printed JSON string.
  String serialise(NetcruxProject project) {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(toJson(project));
  }

  /// Returns the on-disk JSON shape for [project]. Kept stable
  /// across releases — adding a field is non-breaking, removing or
  /// renaming is.
  Map<String, Object?> toJson(NetcruxProject project) => <String, Object?>{
    'version': project.version,
    'sourceFiles': List<String>.from(project.sourceFiles),
    'topModule': project.topModule,
    'defines': Map<String, String>.from(project.defines),
    'includePaths': List<String>.from(project.includePaths),
    'extraYosysCommands': List<String>.from(project.extraYosysCommands),
    'lowerToStructural': project.lowerToStructural,
    if (project.sourceFileLanguages.isNotEmpty)
      'sourceFileLanguages': <String, String>{
        for (final entry in project.sourceFileLanguages.entries)
          entry.key: _languageToString(entry.value),
      },
  };

  static String _languageToString(NetcruxSourceLanguage lang) {
    switch (lang) {
      case NetcruxSourceLanguage.auto:
        return 'auto';
      case NetcruxSourceLanguage.verilog:
        return 'verilog';
      case NetcruxSourceLanguage.systemVerilog:
        return 'systemverilog';
      case NetcruxSourceLanguage.vhdl:
        return 'vhdl';
    }
  }
}
