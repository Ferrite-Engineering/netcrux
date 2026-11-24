// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// The design every headless `netcrux` command reads: what its `design`
/// arguments name, the files those name in turn, and the elaborated model.
///
/// A design is Verilog, SystemVerilog or VHDL sources (and `-f` filelists of
/// them), elaborated by Yosys with the request the app sends; one Yosys JSON
/// netlist, read by the app's own netlist reader; or one `.crux-project`
/// manifest, which names either. Every reader here is the app's.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crux_mcp/crux_mcp.dart';
import 'package:crux_project/crux_project.dart';
import 'package:crux_yosys/crux_yosys.dart';
import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/project/netcrux_project.dart';
import 'package:netcrux/services/file_open/crux_project_resolution.dart';
import 'package:netcrux/services/filelist/filelist_reader.dart';
import 'package:netcrux/services/links/netcrux_link_target.dart';
import 'package:netcrux/services/yosys/elaboration_request.dart';
import 'package:netcrux/services/yosys/elaboration_timeout_provider.dart';
import 'package:netcrux/services/yosys/isolate_netlist_parser.dart';
import 'package:netcrux/services/yosys/path_augmenting_process_runner.dart';
import 'package:netcrux/services/yosys/sv_frontend_gap.dart';
import 'package:path/path.dart' as p;

/// The `design.fingerprint.scheme` of every NetCrux document: SHA-256 over
/// one line per design file, in the order read (the netlist, or the sources
/// after every filelist is expanded): the SHA-256 of its bytes in hex, two
/// spaces, its base name and a newline (`sha256sum`'s format, without the
/// directory, so a design keeps its fingerprint when it moves); then
/// `top=<module>` and a newline, `<module>` empty when none was asked for;
/// then `define <NAME>=<value>` and a newline for each define, sorted by
/// name. Files a source pulls in with `include` are not covered.
const String kNetDesignFingerprintScheme = 'netcrux-design-sha256/1';

/// The engine a document names when Yosys elaborated the design.
const String kYosysEngineName = 'yosys';

/// A design argument refused before anything was elaborated: the command
/// writes a document with [outcome] and [diagnostic], and runs nothing more.
class NetDesignException implements Exception {
  /// A refusal ending in [outcome], said by [diagnostic], after [engines]
  /// ran.
  const NetDesignException(
    this.outcome,
    this.diagnostic, {
    this.engines = const <McpEngine>[],
  });

  /// How the command ends.
  final McpOutcome outcome;

  /// Why.
  final McpDiagnostic diagnostic;

  /// The engines that ran before the refusal.
  final List<McpEngine> engines;

  @override
  String toString() => diagnostic.message;
}

NetDesignException _usage(String code, String message, {String? fix}) =>
    NetDesignException(
      McpOutcome.usageError,
      McpDiagnostic.error(code, message, fix: fix),
    );

NetDesignException _input(String code, String message, {String? fix}) =>
    NetDesignException(
      McpOutcome.inputError,
      McpDiagnostic.error(code, message, fix: fix),
    );

/// What a `design` argument is, by its name.
enum NetDesignFileKind {
  /// A Yosys JSON netlist (`.json`).
  netlist,

  /// A `<design>.crux-project` manifest.
  manifest,

  /// A Vivado-style `.f` filelist.
  filelist,

  /// A Liberty cell library (`.lib`, `.liberty`).
  liberty,

  /// A NetCrux project, session or workspace file, which the command line
  /// does not read.
  netcruxFile,

  /// An HDL source: anything else.
  source,
}

/// The kind of [path], by its name alone.
NetDesignFileKind netDesignFileKind(String path) {
  final lower = path.toLowerCase();
  final base = p.basename(lower);
  if (lower.endsWith('.netcrux-project') ||
      lower.endsWith('.netcrux') ||
      lower.endsWith('.netcrux-workspace')) {
    return NetDesignFileKind.netcruxFile;
  }
  if (lower.endsWith('.$kCruxProjectExtension') || base == '.crux-project') {
    return NetDesignFileKind.manifest;
  }
  if (lower.endsWith('.$kFilelistExtension')) return NetDesignFileKind.filelist;
  if (NetcruxProject.isLibertyPath(path)) return NetDesignFileKind.liberty;
  if (NetcruxProject.isNetlistJsonPath(path)) return NetDesignFileKind.netlist;
  return NetDesignFileKind.source;
}

/// The design a command's arguments name, every file resolved, before
/// anything is elaborated.
@immutable
class NetDesignInput {
  const NetDesignInput._({
    required this.files,
    required this.citation,
    required this.linked,
    this.top,
    this.netlist,
    this.project,
  });

  /// The top module asked for: `--top`, or the one a manifest declares;
  /// null to take the one Yosys or the netlist marks.
  final String? top;

  /// The design's own files, in the order read: the netlist, or the
  /// sources once every filelist and manifest is expanded. The fingerprint
  /// covers these.
  final List<String> files;

  /// The file every location in the answer names.
  final String citation;

  /// Whether a NetCrux link can open [citation]: a design file a link may
  /// name. A manifest or a filelist names further files a link's
  /// confirmation never shows, so a location on one carries no link.
  final bool linked;

  /// The Yosys JSON netlist to read, when the design is one.
  final String? netlist;

  /// The sources to elaborate, when the design is HDL.
  final NetcruxProject? project;
}

/// The files the `design` arguments [design] name, after every manifest and
/// filelist is read, for the server to hold inside its root before the
/// command runs: every source, include directory, cell library and netlist,
/// and every filelist a `-f` line names (each confined before it is opened,
/// through [refuse]). A file that cannot be read is left to the command,
/// which says why.
///
/// Returns the first refusal message, or null when every file is inside.
Future<String?> checkNetDesignNamedFiles(
  List<String> design,
  String? Function(String path) refuse,
) async {
  for (final file in design) {
    final named = <String>[];
    switch (netDesignFileKind(file)) {
      case NetDesignFileKind.manifest:
        final CruxProjectManifest manifest;
        try {
          manifest = const CruxProjectParser().parseFile(file);
        } on Object {
          continue;
        }
        named.addAll(manifest.sources);
        final netlist = manifest.artifact(kNetlistArtifactKind);
        if (netlist != null) named.add(netlist);
      case NetDesignFileKind.filelist:
        final FilelistContents contents;
        try {
          contents = await FilelistReader(refuse: refuse).read(file);
        } on FilelistRefusedException catch (e) {
          return e.message;
        } on Object {
          continue;
        }
        named
          ..addAll(contents.sourceFiles)
          ..addAll(contents.includePaths)
          ..addAll(contents.libertyFiles)
          ..addAll(contents.cellModelFiles);
      case NetDesignFileKind.netlist ||
          NetDesignFileKind.liberty ||
          NetDesignFileKind.netcruxFile ||
          NetDesignFileKind.source:
        continue;
    }
    for (final path in named) {
      final refusal = refuse(path);
      if (refusal != null) return refusal;
    }
  }
  return null;
}

/// Resolves the `design` arguments [design] (absolute paths) and `--top`
/// [top] to the design to read. Throws a [NetDesignException] for an
/// argument the command cannot use; reads manifests and filelists, opens no
/// source.
Future<NetDesignInput> resolveNetDesign(
  List<String> design, {
  String? top,
}) async {
  if (design.isEmpty) {
    throw _usage('usage', 'give at least one design file');
  }
  final kinds = <String, NetDesignFileKind>{
    for (final f in design) f: netDesignFileKind(f),
  };
  for (final entry in kinds.entries) {
    if (entry.value == NetDesignFileKind.netcruxFile) {
      throw _usage(
        'design.unsupported',
        '`${entry.key}` is a NetCrux project, session or workspace file, '
            'which the command line does not read',
        fix:
            'give its sources, a Yosys JSON netlist, a .crux-project or a '
            '.f filelist',
      );
    }
  }
  for (final entry in kinds.entries) {
    if (FileSystemEntity.typeSync(entry.key) != FileSystemEntityType.file) {
      throw _input('input.not_found', '`${entry.key}` is not a file');
    }
  }
  final single = design.length == 1 ? kinds[design.single] : null;
  final alone = <NetDesignFileKind>{
    NetDesignFileKind.netlist,
    NetDesignFileKind.manifest,
  };
  if (single == null && kinds.values.any(alone.contains)) {
    throw _usage(
      'design.mixed',
      'a Yosys JSON netlist or a .crux-project is the whole design; give it '
          'alone',
    );
  }
  switch (single) {
    case NetDesignFileKind.netlist:
      return NetDesignInput._(
        files: List<String>.unmodifiable(design),
        citation: design.single,
        linked: isNetCruxLinkExtension(design.single),
        top: top,
        netlist: design.single,
      );
    case NetDesignFileKind.manifest:
      return _fromManifest(design.single, top);
    case NetDesignFileKind.filelist ||
        NetDesignFileKind.liberty ||
        NetDesignFileKind.source ||
        NetDesignFileKind.netcruxFile ||
        null:
      return await _fromSources(design, kinds, top);
  }
}

NetDesignInput _fromManifest(String manifest, String? top) {
  final resolution = const CruxProjectResolver().resolve(manifest);
  switch (resolution) {
    case ManifestNetlist(:final netlistPath):
      return NetDesignInput._(
        files: List<String>.unmodifiable(<String>[netlistPath]),
        citation: netlistPath,
        linked: isNetCruxLinkExtension(netlistPath),
        top: top,
        netlist: netlistPath,
      );
    case ManifestSources(:final sources, top: final declared):
      final liberty = sources.where(NetcruxProject.isLibertyPath).toList();
      if (liberty.isNotEmpty) throw _libertyRefusal(liberty.first);
      final chosen = top ?? declared;
      final project = NetcruxProject.create(
        sourceFiles: sources,
        topModule: chosen ?? '',
      );
      return NetDesignInput._(
        files: List<String>.unmodifiable(sources),
        citation: manifest,
        linked: false,
        top: chosen,
        project: project,
      );
    case ManifestUnusable(:final reason, :final detail):
      throw _input('input.manifest', switch (reason) {
        ManifestUnusableReason.invalid =>
          '`$manifest` is not a valid .crux-project manifest: $detail',
        ManifestUnusableReason.netlistMissing =>
          '`$manifest` names the netlist `$detail`, which is not on disk',
        ManifestUnusableReason.nothingToOpen =>
          '`$manifest` names neither design sources nor a netlist',
        ManifestUnusableReason.noManifestInDirectory =>
          '`$detail` holds no .crux-project manifest',
      });
    case ManifestAmbiguous(:final directory):
      throw _input(
        'input.manifest',
        '`$directory` holds more than one .crux-project manifest',
      );
    case NotAManifest():
      throw _input(
        'input.manifest',
        '`$manifest` is not a .crux-project manifest',
      );
  }
}

NetDesignException _libertyRefusal(String path) => _input(
  'design.liberty_unsupported',
  '`$path` is a Liberty cell library, which the command line does not read',
  fix:
      'give the design as a Yosys JSON netlist, or open it in the NetCrux '
      'app',
);

Future<NetDesignInput> _fromSources(
  List<String> design,
  Map<String, NetDesignFileKind> kinds,
  String? top,
) async {
  final sources = <String>[];
  final defines = <String, String>{};
  final includes = <String>[];
  String? firstFilelist;
  for (final file in design) {
    switch (kinds[file]!) {
      case NetDesignFileKind.liberty:
        throw _libertyRefusal(file);
      case NetDesignFileKind.filelist:
        firstFilelist ??= file;
        final FilelistContents contents;
        try {
          contents = await const FilelistReader().read(file);
        } on FilelistCycleException catch (e) {
          throw _input(
            'input.filelist',
            'the filelists include each other: ${e.cyclePath.join(' -> ')}',
          );
        } on FilelistNotFoundException catch (e) {
          throw _input(
            'input.filelist',
            '`${e.parentPath}` names the filelist `${e.referencedPath}`, '
                'which is not on disk',
          );
        } on FileSystemException catch (e) {
          throw _input(
            'input.unreadable',
            '`$file` could not be read: ${e.message}',
          );
        }
        if (contents.libertyFiles.isNotEmpty) {
          throw _libertyRefusal(contents.libertyFiles.first);
        }
        sources.addAll(contents.sourceFiles);
        defines.addAll(contents.defines);
        includes.addAll(contents.includePaths);
      case NetDesignFileKind.source:
        sources.add(file);
      case NetDesignFileKind.netlist ||
          NetDesignFileKind.manifest ||
          NetDesignFileKind.netcruxFile:
        // Refused above.
        throw StateError('unreachable: $file');
    }
  }
  if (sources.isEmpty) {
    throw _input('input.no_sources', 'the design names no source file');
  }
  final citation = firstFilelist ?? sources.first;
  return NetDesignInput._(
    files: List<String>.unmodifiable(sources),
    citation: citation,
    linked: firstFilelist == null && isNetCruxLinkExtension(citation),
    top: top,
    project: NetcruxProject.create(
      sourceFiles: sources,
      topModule: top ?? '',
      defines: defines,
      includePaths: includes,
    ),
  );
}

/// [input]'s fingerprint, [kNetDesignFingerprintScheme]; null when a file
/// cannot be read.
McpDesignFingerprint? netDesignFingerprint(NetDesignInput input) {
  final top = input.top;
  final text = StringBuffer();
  for (final file in input.files) {
    final List<int> bytes;
    try {
      bytes = File(file).readAsBytesSync();
    } on FileSystemException {
      return null;
    }
    text
      ..write(sha256.convert(bytes))
      ..write('  ')
      ..write(p.basename(file))
      ..write('\n');
  }
  text.write('top=${top ?? ''}\n');
  final defines = input.project?.defines ?? const <String, String>{};
  for (final name in defines.keys.toList()..sort()) {
    text.write('define $name=${defines[name]}\n');
  }
  return McpDesignFingerprint(
    scheme: kNetDesignFingerprintScheme,
    value: sha256.convert(utf8.encode(text.toString())).toString(),
  );
}

// ── elaboration ─────────────────────────────────────────────────────────────

/// Runs Yosys for the headless commands. The default is the app's own
/// runner and probe, with the engine directories added to `PATH` as the app
/// adds them; a test gives its own.
abstract class NetElaborator {
  /// Whether Yosys can run, and which one.
  Future<YosysAvailability> probe();

  /// Whether this Yosys has the yosys-slang front end.
  Future<bool> probeSlang();

  /// Runs [request], bounded by [timeout] when given, leaving the netlist in
  /// a file the caller deletes.
  Future<YosysRunResult> run(
    YosysRunRequest request, {
    Duration? timeout,
    Future<void>? cancelSignal,
  });
}

/// The Yosys on `PATH` (and in the engine directories the app searches).
class SystemNetElaborator implements NetElaborator {
  /// The elaborator of the installed Yosys.
  SystemNetElaborator();

  final YosysAvailabilityService _availability = YosysAvailabilityService(
    runner: const PathAugmentingProcessRunner(),
  );

  final YosysRunner _runner = YosysRunner(
    processRunner: const PathAugmentingProcessRunner(),
  );

  @override
  Future<YosysAvailability> probe() => _availability.probe();

  @override
  Future<bool> probeSlang() => _availability.probeSlang();

  @override
  Future<YosysRunResult> run(
    YosysRunRequest request, {
    Duration? timeout,
    Future<void>? cancelSignal,
  }) => _runner.runKeepingJson(
    request,
    timeout: timeout,
    cancelSignal: cancelSignal,
  );
}

/// A design the reader or Yosys could not produce, by what went wrong.
sealed class NetDesignProblem {
  const NetDesignProblem();
}

/// No usable Yosys was found.
final class YosysUnavailable extends NetDesignProblem {
  /// The probe's [availability].
  const YosysUnavailable(this.availability);

  /// What the probe found.
  final YosysAvailability availability;
}

/// Yosys ran (or was asked to) and gave no netlist: [result] is a
/// [YosysRunFailure], a [YosysRunTimeout] or a [YosysRunCancelled].
final class YosysDidNotElaborate extends NetDesignProblem {
  /// The run's [result].
  const YosysDidNotElaborate(this.result);

  /// What the run returned.
  final YosysRunResult result;
}

/// The netlist document could not be read or parsed: the one the arguments
/// name ([fromYosys] false) or the one Yosys wrote ([fromYosys] true).
final class NetlistUnreadable extends NetDesignProblem {
  /// [file] could not be read, saying [message].
  const NetlistUnreadable(this.file, this.message, {required this.fromYosys});

  /// The netlist.
  final String file;

  /// Why.
  final String message;

  /// Whether Yosys wrote it.
  final bool fromYosys;
}

/// What a design problem means for a command: its outcome and the error
/// diagnostic that says why.
@immutable
class NetDesignFailure {
  /// A failure ending in [outcome], said by [diagnostic].
  const NetDesignFailure(this.outcome, this.diagnostic);

  /// How the command ends.
  final McpOutcome outcome;

  /// Why.
  final McpDiagnostic diagnostic;
}

/// Maps a design problem to how a command ends; [classifyNetDesignProblem]
/// unless a test proves that a broken mapping is caught.
typedef NetDesignProblemMap =
    NetDesignFailure Function(NetDesignProblem problem);

/// Maps what went wrong reading or elaborating a design to how the command
/// ends. Never an answer: a design that was not produced cannot be
/// described. A missing, failed or timed-out Yosys, or a Yosys netlist that
/// does not parse, is an `engine_error`; a request Yosys cannot be given (a
/// path with a quote) or a netlist file that is not a Yosys netlist is an
/// `input_error`. The mutation proof in `test/headless/design_failure_test.dart`
/// holds this to that.
NetDesignFailure classifyNetDesignProblem(NetDesignProblem problem) {
  NetDesignFailure engine(String code, String message, {String? fix}) =>
      NetDesignFailure(
        McpOutcome.engineError,
        McpDiagnostic.error(code, message, fix: fix),
      );
  switch (problem) {
    case YosysUnavailable(:final availability):
      return engine(
        'engine.missing',
        'Yosys is not available (${availability.unavailableReason ?? 'not '
                'found'})',
        fix:
            'install Yosys and put it on PATH, or give the design as a Yosys '
            'JSON netlist',
      );
    case YosysDidNotElaborate(:final result):
      switch (result) {
        case YosysRunTimeout(:final budget):
          return engine(
            'engine.timeout',
            'Yosys did not finish elaborating in ${budget.inSeconds} s',
          );
        case YosysRunCancelled():
          return engine('engine.cancelled', 'the elaboration was cancelled');
        case YosysRunFailure(:final kind, :final exitCode, :final stderr):
          final detail = _firstErrorLine(stderr);
          switch (kind) {
            case YosysFailureKind.launch:
              return engine(
                'engine.missing',
                'Yosys could not be started${detail == null ? '' : ': '
                          '$detail'}',
                fix: 'install Yosys and put it on PATH',
              );
            case YosysFailureKind.invalidRequest:
              return NetDesignFailure(
                McpOutcome.inputError,
                McpDiagnostic.error(
                  'input.unusable',
                  'the design cannot be passed to Yosys'
                      '${detail == null ? '' : ': $detail'}',
                ),
              );
            case YosysFailureKind.outputUnreadable || YosysFailureKind.noOutput:
              return engine(
                'engine.failed',
                'Yosys gave no netlist${detail == null ? '' : ': $detail'}',
              );
            case YosysFailureKind.nonZeroExit:
              return engine(
                'engine.failed',
                'Yosys stopped with exit code $exitCode'
                    '${detail == null ? '' : ': $detail'}',
              );
          }
        case YosysRunSuccess():
          // Not a problem; no caller passes one.
          return engine('engine.failed', 'Yosys reported no problem');
      }
    case NetlistUnreadable(:final file, :final message, :final fromYosys):
      return fromYosys
          ? engine(
              'engine.failed',
              'the netlist Yosys wrote could not be read: $message',
            )
          : NetDesignFailure(
              McpOutcome.inputError,
              McpDiagnostic.error(
                'input.unreadable',
                '`$file` is not a readable Yosys JSON netlist: $message',
              ),
            );
  }
}

/// The first line of [stderr] that says `ERROR`, trimmed; else its last
/// non-empty line; null when it is empty.
String? _firstErrorLine(String stderr) {
  final lines = stderr
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
  if (lines.isEmpty) return null;
  for (final line in lines) {
    if (line.contains('ERROR')) return line;
  }
  return lines.last;
}

/// An elaborated design, as a command reads it.
@immutable
class NetDesign {
  /// A design read from [input].
  const NetDesign({
    required this.model,
    required this.input,
    required this.engines,
    required this.fingerprint,
    required this.linked,
    this.warnings = const <McpDiagnostic>[],
  });

  /// The netlist.
  final NetlistModel model;

  /// What the arguments named.
  final NetDesignInput input;

  /// The engines that ran: Yosys, or none for a netlist read from disk.
  final List<McpEngine> engines;

  /// The design's fingerprint.
  final McpDesignFingerprint? fingerprint;

  /// Whether locations carry a link.
  final bool linked;

  /// Warnings every document about this design carries.
  final List<McpDiagnostic> warnings;

  /// The file every location names.
  String get file => input.citation;
}

/// Reads designs, holding the two most recently read for the life of the
/// process (an `mcp` server answers several calls about one design), keyed
/// by the fingerprint and the top.
class NetDesignReader {
  /// A reader running Yosys through [elaborator].
  NetDesignReader({NetElaborator? elaborator, this.capacity = 2})
    : elaborator = elaborator ?? SystemNetElaborator();

  /// Runs Yosys.
  final NetElaborator elaborator;

  /// How many designs are held.
  final int capacity;

  final Map<String, NetDesign> _held = <String, NetDesign>{};

  /// The keys of the designs held, oldest first. For tests.
  @visibleForTesting
  List<String> get heldKeys => List<String>.unmodifiable(_held.keys);

  /// Reads [input]: the design, or the [NetDesignProblem] that kept it from
  /// being produced, and the engines that ran either way. Throws a
  /// [NetDesignException] when the design cannot be rooted at the top asked
  /// for.
  Future<(NetDesign?, NetDesignProblem?, List<McpEngine>)> read(
    NetDesignInput input,
  ) async {
    final fingerprint = netDesignFingerprint(input);
    final key = fingerprint?.value;
    if (key != null) {
      final held = _held.remove(key);
      if (held != null) {
        _held[key] = held;
        return (held, null, held.engines);
      }
    }
    final NetlistModel model;
    final List<McpEngine> engines;
    final netlist = input.netlist;
    if (netlist != null) {
      try {
        final parsed = await parseNetlistFileWithBlackBoxesOnIsolate(netlist);
        model = parsed!.model;
      } on YosysJsonParseException catch (e) {
        return (
          null,
          NetlistUnreadable(netlist, e.message, fromYosys: false),
          const <McpEngine>[],
        );
      }
      engines = const <McpEngine>[];
    } else {
      final (elaborated, engine, problem) = await _elaborate(input.project!);
      final ran = <McpEngine>[?engine];
      if (problem != null) return (null, problem, ran);
      model = elaborated!;
      engines = ran;
    }
    final NetlistModel rooted;
    final bool linked;
    final List<McpDiagnostic> warnings;
    try {
      (rooted, linked, warnings) = _rootAt(model, input.top, input);
    } on NetDesignException catch (e) {
      throw NetDesignException(e.outcome, e.diagnostic, engines: engines);
    }
    final design = NetDesign(
      model: rooted,
      input: input,
      engines: List<McpEngine>.unmodifiable(engines),
      fingerprint: fingerprint,
      linked: linked,
      warnings: warnings,
    );
    if (key != null) {
      _held[key] = design;
      while (_held.length > capacity) {
        _held.remove(_held.keys.first);
      }
    }
    return (design, null, design.engines);
  }

  Future<(NetlistModel?, McpEngine?, NetDesignProblem?)> _elaborate(
    NetcruxProject project,
  ) async {
    final availability = await elaborator.probe();
    if (!availability.isAvailable) {
      return (null, null, YosysUnavailable(availability));
    }
    final engine = McpEngine(
      name: kYosysEngineName,
      version: _yosysVersion(availability.versionString ?? ''),
      path: availability.executablePath,
    );
    final request = elaborationRequestFor(project);
    const policy = DefaultElaborationTimeoutPolicy();
    final budget = policy.timeoutFor(await elaborationSizeOf(project));
    var result = await elaborator.run(request, timeout: budget);
    // The app reads a design again with yosys-slang when Yosys's own reader
    // stops at a SystemVerilog construct it lacks; so does this.
    if (result is YosysRunFailure &&
        svFrontendGapIn(result.stderr) != null &&
        request.hasVerilogSources &&
        await elaborator.probeSlang()) {
      result = await elaborator.run(
        YosysRunRequest(
          sources: request.sources,
          topModule: request.topModule,
          defines: request.defines,
          includePaths: request.includePaths,
          extraCommands: request.extraCommands,
          vhdlStandard: request.vhdlStandard,
          vhdlTopUnit: request.vhdlTopUnit,
          frontend: YosysFrontend.slang,
          slangOptions: request.slangOptions,
          allowUndefinedModules: request.allowUndefinedModules,
        ),
        timeout: budget,
      );
    }
    if (result is! YosysRunSuccess) {
      return (null, engine, YosysDidNotElaborate(result));
    }
    final path = result.jsonPath;
    try {
      final model = path != null
          ? await parseNetlistFileOnIsolate(path)
          : await parseNetlistOnIsolate(result.rawJson);
      return (model, engine, null);
    } on YosysJsonParseException catch (e) {
      return (
        null,
        engine,
        NetlistUnreadable(path ?? 'yosys output', e.message, fromYosys: true),
      );
    } finally {
      if (path != null) {
        try {
          File(path).deleteSync();
        } on FileSystemException {
          // Already gone.
        }
      }
    }
  }
}

/// The version in a `yosys -V` banner (`Yosys 0.58+12 (git sha1 ...)` gives
/// `0.58+12`); the banner itself when it has no such word.
String _yosysVersion(String banner) {
  final match = RegExp(r'^Yosys\s+(\S+)').firstMatch(banner.trim());
  return match?.group(1) ?? banner.trim();
}

/// [model] rooted at [top]: the model itself, whether a link can place a
/// name in it, and any warning. Throws a [NetDesignException] when [top]
/// cannot be the root, or no root is known.
(NetlistModel, bool, List<McpDiagnostic>) _rootAt(
  NetlistModel model,
  String? top,
  NetDesignInput input,
) {
  final marked = model.topModule;
  if (top == null) {
    if (marked == null) {
      throw _input(
        'design.no_top',
        'no module of the design is marked as its top',
        fix: 'give the top module with --top',
      );
    }
    return (model, input.linked, const <McpDiagnostic>[]);
  }
  if (!model.modules.containsKey(top)) {
    throw _input(
      'design.top_not_found',
      'the design has no module `$top`',
      fix:
          'find its modules with `netcrux search <design> "*" --glob --kind '
          'module`',
    );
  }
  if (marked != null) {
    if (marked.name == top) {
      return (model, input.linked, const <McpDiagnostic>[]);
    }
    throw _input(
      'design.top_mismatch',
      'the netlist marks `${marked.name}` as its top, not `$top`',
      fix: 'leave out --top, or give --top ${marked.name}',
    );
  }
  // A netlist that marks no top: rooted here at the module asked for. The
  // app roots a link's name at the netlist's own top, which this one lacks,
  // so no location can carry a link.
  final rooted = model.copyWith(
    modules: <String, Module>{
      for (final entry in model.modules.entries)
        entry.key: entry.key == top
            ? entry.value.copyWith(
                attributes: <String, String>{
                  ...entry.value.attributes,
                  'top': '1',
                },
              )
            : entry.value,
    },
  );
  return (
    rooted,
    false,
    const <McpDiagnostic>[
      McpDiagnostic.warning(
        'link.unavailable',
        'the netlist marks no top module, so NetCrux cannot place a name in '
            'it from a link; locations carry no link',
      ),
    ],
  );
}
