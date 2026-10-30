// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';

import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:crux_yosys/crux_yosys.dart';
import 'package:meta/meta.dart';
import 'package:netcrux/domain/enums/netcrux_source_language.dart';
import 'package:netcrux/domain/interfaces/elaboration_timeout_policy.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/project/netcrux_project.dart';
import 'package:netcrux/features/project/providers/current_project_provider.dart';
import 'package:netcrux/features/project/providers/elaboration_diagnostics_provider.dart';
import 'package:netcrux/features/statistics/providers/elaboration_progress_provider.dart';
import 'package:netcrux/services/liberty/liberty_stub_service.dart';
import 'package:netcrux/services/liberty/liberty_stub_service_provider.dart';
import 'package:netcrux/services/telemetry/netcrux_design_language_mix.dart';
import 'package:netcrux/services/web/web_json_loader.dart';
import 'package:netcrux/services/yosys/black_box_port_inference.dart';
import 'package:netcrux/services/yosys/elaboration_cache_provider.dart';
import 'package:netcrux/services/yosys/elaboration_cache_service.dart';
import 'package:netcrux/services/yosys/elaboration_timeout_provider.dart';
import 'package:netcrux/services/yosys/isolate_netlist_parser.dart';
import 'package:netcrux/services/yosys/prebuilt_netlist_loader_provider.dart';
import 'package:netcrux/services/yosys/sv_frontend_gap.dart';
import 'package:netcrux/services/yosys/yosys_availability_provider.dart';
import 'package:netcrux/services/yosys/yosys_json_parser.dart';
import 'package:netcrux/services/yosys/yosys_runner_provider.dart';
import 'package:netcrux/services/yosys/yosys_timeout_exception.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'loaded_netlist_provider.g.dart';

/// Opts a provider out of Riverpod's automatic exponential-backoff retry.
/// Used by the elaboration pipeline ([LoadedNetlist],
/// `currentLaidOutGraphProvider`): their failures are deterministic, so a
/// retry can only burn CPU (respawning Yosys / re-running ELK) and churn
/// every listener with loading/error transitions.
Duration? noElaborationRetry(int retryCount, Object error) => null;

/// The typed shape of an elaboration failure. Lets the UI pick a
/// localized message per failure instead of rendering the (English)
/// [LoadedNetlistException.message] verbatim. [unknown] covers every
/// error the pipeline does not classify (parse errors, layout errors,
/// anything reaching the schematic error view that isn't one of the
/// named shapes) — those get a generic localized envelope with the raw
/// detail shown separately.
enum LoadedNetlistErrorKind {
  /// Yosys binary missing or not runnable.
  yosysUnavailable,

  /// The runner killed Yosys after its time budget elapsed.
  timeout,

  /// Yosys ran to completion but exited non-zero.
  nonZeroExit,

  /// Yosys stopped because the design instantiates a module that no source
  /// file or cell library defines (`hierarchy -check`: "is not part of the
  /// design"), or yosys-slang's "unknown module". For the built-in reader
  /// the error view offers to show missing modules as black boxes
  /// ([NetcruxProject.blackBoxMissingModules]); yosys-slang cannot draw
  /// them, so there the view asks for a definition.
  missingModule,

  /// Unclassified failure — render the generic envelope.
  unknown,
}

/// Surfaced when elaboration fails (yosys missing, parse error, no
/// source files provided). Carries a one-line English message (for logs
/// / diagnostics), a typed [kind] the UI maps to a localized message,
/// an optional underlying [cause], and optional structured fields the
/// localized message interpolates ([exitCode], [timeoutSeconds]) or
/// shows as expandable [detail].
@immutable
class LoadedNetlistException implements Exception {
  /// Creates a load exception.
  const LoadedNetlistException(
    this.message, {
    this.cause,
    this.kind = LoadedNetlistErrorKind.unknown,
    this.detail,
    this.exitCode,
    this.timeoutSeconds,
    this.frontendGap,
    this.missingModule,
    this.readBySlang = false,
  });

  /// Short user-actionable English message. Kept for logs, `toString`,
  /// and the diagnostics drawer; the schematic error view renders a
  /// localized message keyed off [kind] instead.
  final String message;

  /// Underlying error (a [YosysJsonParseException], the
  /// [YosysRunFailure] stderr, etc.) — `null` when the failure is a
  /// missing-input case.
  final Object? cause;

  /// Typed failure shape driving the localized UI message.
  final LoadedNetlistErrorKind kind;

  /// Raw secondary text (Yosys stderr, an unavailability reason) shown
  /// in the error view's expandable "Details" section. `null` when
  /// there's nothing extra to show.
  final String? detail;

  /// Yosys process exit code — set for [LoadedNetlistErrorKind.nonZeroExit].
  final int? exitCode;

  /// Elapsed timeout budget in whole seconds — set for
  /// [LoadedNetlistErrorKind.timeout].
  final int? timeoutSeconds;

  /// The SystemVerilog construct Yosys's built-in reader stopped at, when a
  /// [LoadedNetlistErrorKind.nonZeroExit] failure is one of the reader's
  /// known gaps rather than an error in the design. The error view then
  /// names the construct and the way past it.
  final SvFrontendGap? frontendGap;

  /// The module Yosys found no definition for, as the design names it — set
  /// for [LoadedNetlistErrorKind.missingModule] when the message names one.
  final String? missingModule;

  /// Whether the yosys-slang reader stopped at [missingModule]. That reader
  /// refuses a module nothing defines and cannot draw it as a black box, so
  /// the error view asks for a definition or a cell library instead of
  /// offering the black-box option.
  final bool readBySlang;

  @override
  String toString() => cause == null
      ? 'LoadedNetlistException: $message'
      : 'LoadedNetlistException: $message ($cause)';
}

/// AsyncNotifier that drives the elaboration pipeline.
///
/// On first read it:
///   1. Reads [currentProjectProvider] for the user's choice of
///      sources, defines, include paths, top module, and Yosys
///      knobs.
///   2. Checks yosys availability via [yosysAvailabilityProvider].
///   3. Runs [YosysRunner], parses the output into a [NetlistModel],
///      and returns it.
///
/// A project whose single source is a Yosys JSON netlist
/// ([NetcruxProject.isPrebuiltNetlist]) skips steps 2 and 3: the document is
/// read and parsed through [prebuiltNetlistLoaderProvider]. A build that
/// cannot elaborate at all ([hdlElaborationSupportedProvider] `false` — the
/// browser) takes that branch for every design.
///
/// Errors surface as [AsyncError]. Returns a `null` model when the
/// project carries no source files — the empty-state landing case,
/// which the schematic pane renders as its "no design loaded" empty
/// state rather than as an error.
///
/// Retry is manual, never automatic: elaboration failures are
/// deterministic (Yosys missing, non-zero exit, parse error) and cannot
/// self-heal, so Riverpod's default exponential-backoff auto-retry would
/// silently re-spawn the Yosys subprocess over and over against the same
/// failing input — and each retry transition re-fires every
/// `loadedNetlistProvider` listener (hierarchy re-roots, canvas flickers).
/// The schematic error view's Retry button invalidates the provider
/// explicitly.
@Riverpod(keepAlive: true, retry: noElaborationRetry)
class LoadedNetlist extends _$LoadedNetlist {
  /// Elaborates, and reports the outcome to the elaboration funnel
  /// (`design.elaborated` / `design.elaboration_failed`).
  ///
  /// The counters live in this wrapper rather than sprinkled through
  /// [_elaborate] so there is exactly one success site and one failure site,
  /// and so the failure site can key off the *typed* [LoadedNetlistErrorKind]
  /// the pipeline already produces for the localized error view. That typing
  /// is what keeps the never-collect rule intact: the only thing reported is
  /// a classification NetCrux itself made, never the Yosys diagnostic or the
  /// exception message that came with it.
  @override
  Future<NetlistModel?> build() async {
    final project = ref.watch(currentProjectProvider);
    if (project.sourceFiles.isEmpty) return null;
    // A pre-built netlist is read, not elaborated — and in the browser every
    // design is one. Neither path is an elaboration, so neither reports to
    // the elaboration funnel below: a `.json` document has no HDL language
    // to count, and a parse failure is not a Yosys failure.
    if (project.isPrebuiltNetlist ||
        !ref.read(hdlElaborationSupportedProvider)) {
      return await _loadPrebuiltNetlist(project);
    }
    final ({NetlistModel? model, bool cached}) outcome;
    try {
      outcome = await _elaborate(project);
    } on LoadedNetlistException catch (e) {
      _recordElaborationFailed(e.kind);
      rethrow;
      // Everything the pipeline throws that is *not* already classified — a
      // parse error re-thrown from a nested layer, a RangeError out of a
      // malformed netlist — still failed an elaboration the user asked for, and
      // a funnel that only counts the classified failures reads healthier than
      // it is.
    } on Object {
      _recordElaborationFailed(LoadedNetlistErrorKind.unknown);
      rethrow;
    }
    final model = outcome.model;
    // A null model is "nothing to elaborate" (no sources) or "this run was
    // superseded / cancelled" — neither is an elaboration that happened.
    if (model == null) return null;
    _recordElaborated(cached: outcome.cached);
    return model;
  }

  void _recordElaborated({required bool cached}) {
    final project = ref.read(currentProjectProvider);
    final language = netcruxDesignLanguageMixFor(
      project.sourceFiles.map(project.resolveLanguage),
    );
    if (language == null) return;
    ref
        .read(telemetryServiceProvider)
        .record(
          TelemetryEvent(
            'design.elaborated',
            properties: <String, Object?>{
              // Both tokens come from Dart enums through `telemetryEnumToken`.
              // Nothing here is derived from a path, a file name, or a module
              // name: event properties are a closed vocabulary, never free
              // text (`https://edacrux.app/telemetry`).
              'language': telemetryEnumToken(language),
              'source': telemetryEnumToken(
                ref.read(currentProjectProvider.notifier).activeSource,
              ),
              'cached': cached,
            },
          ),
        );
  }

  void _recordElaborationFailed(LoadedNetlistErrorKind kind) {
    ref
        .read(telemetryServiceProvider)
        .record(
          TelemetryEvent(
            'design.elaboration_failed',
            properties: <String, Object?>{'reason': telemetryEnumToken(kind)},
          ),
        );
  }

  /// Reads and parses the single netlist document [project] names.
  ///
  /// A multi-file project can only reach here in a build that cannot
  /// elaborate, and there is no netlist to read in it, so it is reported as
  /// the missing engine it is.
  Future<NetlistModel?> _loadPrebuiltNetlist(NetcruxProject project) async {
    final cancel = Completer<void>();
    ref.onDispose(() {
      if (!cancel.isCompleted) cancel.complete();
    });
    // No Yosys ran, so there is no stderr to show; clear what a previous
    // elaboration in this tab left behind.
    ref.read(elaborationStderrProvider.notifier).set('');
    final loaded = await _readPrebuiltNetlist(
      ref,
      project,
      cancelSignal: cancel.future,
    );
    // The pins given a direction here are the only diagnostics a netlist
    // read from disk has.
    final report = loaded?.report ?? BlackBoxReport.none;
    if (!report.isEmpty) {
      ref
          .read(elaborationStderrProvider.notifier)
          .set(_withWarnings(report.warningLines, ''));
    }
    return loaded?.model;
  }

  Future<({NetlistModel? model, bool cached})> _elaborate(
    NetcruxProject project,
  ) async {
    final availability = await _requireYosys(ref);
    final runner = ref.read(yosysRunnerProvider);
    final options = _buildRequest(project);
    // Elaboration cache (a re-open of an unchanged design is a sub-50 ms cache
    // hit): fingerprint = per-file path+size+mtime (sources and Liberty cell
    // libraries) + yosys version + the request options. A hit returns the
    // previously parsed model and its stderr without spawning yosys or
    // re-parsing. A null key (a source vanished) simply bypasses the cache.
    final cache = ref.read(elaborationCacheServiceProvider);
    final cacheKey = await ElaborationCacheService.buildKey(
      sourceFilePaths: project.sourceFiles,
      libertyFilePaths: project.libertyFiles,
      yosysVersion: availability.versionString ?? '',
      topModule: options.topModule,
      defines: options.defines,
      includePaths: options.includePaths,
      extraCommands: options.extraCommands,
      blackBoxMissingModules: project.blackBoxMissingModules,
    );
    if (cacheKey != null) {
      final hit = cache.lookup(cacheKey);
      if (hit != null) {
        ref.read(elaborationStderrProvider.notifier).set(hit.stderr);
        return (model: hit.model, cached: true);
      }
    }
    // Cell libraries become one more Verilog source: a file of black-box
    // stubs, generated (or read from its on-disk cache) only on a miss.
    final liberty = await _libertyStubs(ref, project);
    final request = liberty == null
        ? options
        : _buildRequest(project, libertyStubPath: liberty.stubPath);
    // VHDL sources are not pre-empted here on a ghdl-availability check:
    // the runner lowers them with a standalone `ghdl --synth` step and a
    // missing or failing ghdl surfaces its stderr as a pipeline error,
    // so probing first would only duplicate that with no added signal.
    // Bound the subprocess. The size-aware policy yields a budget
    // from the source byte size; the runner kills Yosys if it overruns.
    final policy = ref.read(elaborationTimeoutPolicyProvider);
    final budget = policy.timeoutFor(await _estimateSize(project));
    // Disposing this provider (tab close) or re-running it
    // (superseding elaboration on a project change) fires onDispose,
    // which kills the stale in-flight Yosys and drops its late reply.
    final cancel = Completer<void>();
    ref.onDispose(() {
      if (!cancel.isCompleted) cancel.complete();
    });
    // Live pass readout for the statistics strip. Yosys
    // announces each pass on stderr as it starts, so the strip can say
    // "HIERARCHY" rather than an undifferentiated "running" for a long
    // elaboration. Cleared in the finally below — the readout is only
    // meaningful while a subprocess is actually in flight.
    final progress = ref.read(elaborationProgressProvider.notifier);
    var result = await _runOnce(
      runner,
      request,
      progress,
      timeout: policy.killOnTimeout ? budget : null,
      cancelSignal: cancel.future,
    );
    // The built-in reader refuses some ordinary SystemVerilog (a `return`,
    // a package import in a module header, a cast of a non-constant
    // expression). When it stops at one of those and this Yosys has the
    // yosys-slang front end, the design is read again with it.
    final gap = result is YosysRunFailure
        ? svFrontendGapIn(result.stderr)
        : null;
    if (gap != null &&
        request.hasVerilogSources &&
        await ref.read(yosysAvailabilityServiceProvider).probeSlang()) {
      result = await _runOnce(
        runner,
        _withFrontend(request, YosysFrontend.slang),
        progress,
        timeout: policy.killOnTimeout ? budget : null,
        cancelSignal: cancel.future,
      );
    }
    // Publish stderr — successes and failures alike — so the
    // diagnostics drawer can surface warnings even on healthy runs. The cell
    // libraries' own warnings go first, in Yosys's `Warning:` form.
    var stderr = _withLibertyWarnings(liberty, result.stderr);
    ref.read(elaborationStderrProvider.notifier).set(stderr);
    // A killed subprocess is reported by its result type, not an
    // exit code. Branch on those before the success / failure handling.
    if (result is YosysRunTimeout) throw _failureFor(result);
    if (result is YosysRunCancelled) {
      // Superseded / tab-closed: this build was disposed, so Riverpod
      // ignores the return value. Yield the empty state rather than an
      // error toast for the (dropped) stale result.
      return (model: null, cached: false);
    }
    if (result is YosysRunSuccess) {
      final document = _NetlistDocument.of(result);
      try {
        // Parse on a background isolate so a large design (the perf report
        // measures 0.34 s @ 100K cells, 4.8 s @ 1M) doesn't freeze the UI
        // isolate inside build(). The result transfers back zero-copy via
        // Isolate.exit; the `cancel` completer (fired on dispose above)
        // hard-kills the worker, so a superseded elaboration stops parsing
        // instead of burning a core to completion.
        //
        // The write_json document is never read into this process: Yosys
        // leaves it in a temp file and the worker reads that file in
        // fixed-size chunks, so neither isolate holds the text (or any part
        // of it larger than one cell) and the design's size is not limited by
        // the size of a string. Peak memory is the model being built. See
        // ARCHITECTURE.md §8.9.
        final parsed = await _parse(
          project,
          document,
          cancelSignal: cancel.future,
        );
        final model = parsed?.model;
        // The modules drawn as black boxes lead the diagnostics, ahead of
        // the cell libraries' warnings and Yosys's own.
        final blackBoxes = parsed?.report ?? BlackBoxReport.none;
        if (!blackBoxes.isEmpty) {
          stderr = _withWarnings(blackBoxes.warningLines, stderr);
          ref.read(elaborationStderrProvider.notifier).set(stderr);
        }
        // Cache only a fully-parsed success (never populate the cache
        // with a partial result — cancelled and
        // failed runs return above, parse failures throw below, and a
        // null model here means the parse was cancelled mid-flight).
        if (cacheKey != null && model != null) {
          cache.store(
            cacheKey,
            ElaborationCacheEntry(
              model: model,
              stderr: stderr,
              approxBytes: document.byteLength,
            ),
          );
        }
        return (model: model, cached: false);
      } on YosysJsonParseException catch (e) {
        throw LoadedNetlistException(e.message, cause: e);
      } finally {
        document.dispose();
      }
    }
    throw _failureFor(result, frontendGap: gap);
  }

  /// One Yosys run with the live pass readout attached and cleared after.
  Future<YosysRunResult> _runOnce(
    YosysRunner runner,
    YosysRunRequest request,
    ElaborationProgressNotifier progress, {
    required Duration? timeout,
    required Future<void> cancelSignal,
  }) async {
    try {
      // The document stays in Yosys's temp file; see [_NetlistDocument].
      return await runner.runKeepingJson(
        request,
        timeout: timeout,
        cancelSignal: cancelSignal,
        onStderrLine: progress.consumeStderrLine,
      );
    } finally {
      // Runs on the throwing paths too: a failed elaboration must not
      // leave the strip advertising a pass that stopped executing.
      progress.clear();
    }
  }

  /// Overrides the elaborated model directly — used by tests and by
  /// the in-process fixture-loading path that bypasses yosys.
  void setModel(NetlistModel? model) {
    state = AsyncData<NetlistModel?>(model);
  }

  /// Best-effort pre-elaboration size signal for the timeout policy: the
  /// source-file count plus their combined byte size. Uses async `stat` so
  /// the (potentially many) source-file stats never block the UI isolate.
  /// `stat` failures (a path that vanished, a permission error) fall back to
  /// 0 bytes for that file — the policy floor still bounds the run, so a
  /// missing size never produces an unbounded budget.
  static Future<ElaborationSizeEstimate> _estimateSize(
    NetcruxProject project,
  ) async {
    var totalBytes = 0;
    for (final path in project.sourceFiles) {
      try {
        // The async stat is intentional: this runs in build() on the UI
        // isolate, and keeping it off-thread matters more than the small
        // per-call overhead the lint warns about.
        // ignore: avoid_slow_async_io
        final stat = await File(path).stat();
        // A missing path yields FileSystemEntityType.notFound with size -1;
        // clamp so a vanished file counts as 0, not a negative.
        if (stat.size > 0) totalBytes += stat.size;
      } on FileSystemException {
        // Unstattable source — count it as 0 bytes.
      }
    }
    return ElaborationSizeEstimate(
      sourceFileCount: project.sourceFiles.length,
      totalSourceBytes: totalBytes,
    );
  }

  /// Translates a [NetcruxProject] into the [YosysRunRequest] the
  /// runner expects. Map → list conversion follows the Verilator /
  /// Yosys convention: empty-value defines emit `NAME` (no `=`);
  /// non-empty defines emit `NAME=VALUE`. Per-file language is
  /// resolved by [NetcruxProject.resolveLanguage].
  @visibleForTesting
  static YosysRunRequest buildRequest(
    NetcruxProject project, {
    String? libertyStubPath,
  }) => _buildRequest(project, libertyStubPath: libertyStubPath);

  /// [libertyStubPath], when given, is the generated black-box stub file
  /// for the project's cell libraries. It is read first, as plain Verilog,
  /// so a module the sources define under a cell's name replaces the stub
  /// (Yosys replaces a black box with a later full definition).
  static YosysRunRequest _buildRequest(
    NetcruxProject project, {
    String? libertyStubPath,
  }) {
    return YosysRunRequest(
      sources: <YosysSourceFile>[
        if (libertyStubPath != null) YosysSourceFile(libertyStubPath),
        for (final path in project.sourceFiles)
          _sourceFileFor(path, project.resolveLanguage(path)),
      ],
      topModule: project.topModule.isEmpty ? null : project.topModule,
      defines: <String>[
        for (final entry in project.defines.entries)
          if (entry.value.isEmpty) entry.key else '${entry.key}=${entry.value}',
      ],
      includePaths: project.includePaths,
      extraCommands: project.extraYosysCommands,
      vhdlTopUnit: project.topModule.isEmpty ? null : project.topModule,
      allowUndefinedModules: project.blackBoxMissingModules,
    );
  }

  static YosysSourceFile _sourceFileFor(
    String path,
    NetcruxSourceLanguage lang,
  ) {
    switch (lang) {
      case NetcruxSourceLanguage.verilog:
        return YosysSourceFile(path);
      case NetcruxSourceLanguage.systemVerilog:
        return YosysSourceFile.systemVerilog(path);
      case NetcruxSourceLanguage.vhdl:
        return YosysSourceFile.vhdl(path);
      case NetcruxSourceLanguage.auto:
        // `auto` should be resolved upstream by `resolveLanguage`;
        // reaching here means the inference returned `auto` which is
        // not a valid runtime value. Treat as verilog (legacy
        // behavior) for safety.
        return YosysSourceFile(path);
    }
  }
}

/// Loads [project]'s netlist once, outside any tab's pipeline — for a design
/// that is not the tab's own, such as the comparison side of a netlist diff.
///
/// The same two paths the tab pipeline takes, with the same failures: a
/// pre-built netlist is read and parsed, and HDL is elaborated by Yosys under
/// the size-aware timeout policy and parsed off the UI isolate. What it leaves
/// out is what describes the tab's own design — the elaboration cache, the
/// stderr and progress readouts, and the elaboration telemetry.
///
/// Throws [LoadedNetlistException]. Returns `null` for a project with no
/// sources.
Future<NetlistModel?> loadDesignNetlist(
  Ref ref,
  NetcruxProject project,
) async {
  if (project.sourceFiles.isEmpty) return null;
  if (project.isPrebuiltNetlist || !ref.read(hdlElaborationSupportedProvider)) {
    return (await _readPrebuiltNetlist(ref, project))?.model;
  }
  await _requireYosys(ref);
  final liberty = await _libertyStubs(ref, project);
  final policy = ref.read(elaborationTimeoutPolicyProvider);
  final budget = policy.timeoutFor(await LoadedNetlist._estimateSize(project));
  final result = await ref
      .read(yosysRunnerProvider)
      .runKeepingJson(
        LoadedNetlist._buildRequest(
          project,
          libertyStubPath: liberty?.stubPath,
        ),
        timeout: policy.killOnTimeout ? budget : null,
      );
  if (result is YosysRunCancelled) return null;
  if (result is! YosysRunSuccess) throw _failureFor(result);
  final document = _NetlistDocument.of(result);
  try {
    return (await _parse(project, document))?.model;
  } on YosysJsonParseException catch (e) {
    throw LoadedNetlistException(e.message, cause: e);
  } finally {
    document.dispose();
  }
}

/// Reads and parses the single netlist document [project] names.
///
/// A multi-file project can only reach here in a build that cannot
/// elaborate, and there is no netlist to read in it, so it is reported as
/// the missing engine it is.
Future<({NetlistModel model, BlackBoxReport report})?> _readPrebuiltNetlist(
  Ref ref,
  NetcruxProject project, {
  Future<void>? cancelSignal,
}) async {
  if (project.sourceFiles.length != 1) {
    throw const LoadedNetlistException(
      'This build cannot elaborate HDL sources; open a Yosys JSON netlist',
      kind: LoadedNetlistErrorKind.yosysUnavailable,
    );
  }
  try {
    return await ref
        .read(prebuiltNetlistLoaderProvider)
        .loadWithReport(project.sourceFiles.single, cancelSignal: cancelSignal);
  } on WebJsonLoadException catch (e) {
    throw LoadedNetlistException(
      e.message,
      cause: e,
      detail: e.cause?.toString(),
    );
  } on YosysJsonParseException catch (e) {
    throw LoadedNetlistException(e.message, cause: e, detail: e.message);
  }
}

/// The black-box stubs for [project]'s cell libraries, or `null` when it
/// has none.
///
/// A library that is missing or is not valid Liberty does not stop the
/// elaboration: [LibertyStubService.stubsFor] leaves it out and says so in
/// the returned warnings, which [_withLibertyWarnings] puts in front of the
/// run's stderr so they reach Diagnostics. Its cells are then missing
/// modules, drawn as black boxes when the project asks for that and
/// otherwise reported as the usual missing-module error.
Future<LibertyStubs?> _libertyStubs(Ref ref, NetcruxProject project) async {
  if (project.libertyFiles.isEmpty) return null;
  return await ref
      .read(libertyStubServiceProvider)
      .stubsFor(project.libertyFiles);
}

/// [stderr] with [liberty]'s warnings in front, one `Warning:` line each,
/// the form the diagnostics drawer parses.
String _withLibertyWarnings(LibertyStubs? liberty, String stderr) {
  if (liberty == null || liberty.warnings.isEmpty) return stderr;
  return _withWarnings(<String>[
    for (final warning in liberty.warnings) 'Warning: $warning',
  ], stderr);
}

/// [stderr] with [lines] in front, one per line.
String _withWarnings(List<String> lines, String stderr) {
  if (lines.isEmpty) return stderr;
  final buffer = StringBuffer();
  lines.forEach(buffer.writeln);
  return '$buffer$stderr';
}

/// The `write_json` document of a successful Yosys run: the temp file the
/// runner left it in, or, from a runner that hands the text back, the text.
///
/// The file is the real case. It is never read into this process; the parse
/// worker reads it in chunks. Whoever takes the document owns the file and
/// calls [dispose] when done with it, on every path out.
class _NetlistDocument {
  _NetlistDocument.of(YosysRunSuccess result)
    : path = result.jsonPath,
      text = result.jsonPath == null ? result.rawJson : null;

  /// The temp file holding the document, or `null` for [text].
  final String? path;

  /// The document itself, only from a runner that does not keep a file.
  final String? text;

  /// The document's size in bytes (characters, for [text]); `0` when the
  /// file cannot be read.
  int get byteLength {
    final file = path;
    if (file == null) return text!.length;
    try {
      return File(file).lengthSync();
    } on FileSystemException {
      return 0;
    }
  }

  /// Deletes the temp file; the caller owns it, and a leftover one is a
  /// whole netlist's worth of disk.
  void dispose() {
    final file = path;
    if (file == null) return;
    try {
      File(file).deleteSync();
    } on FileSystemException {
      // Already gone, or the platform holds it; nothing else to do.
    }
  }
}

/// Parses [document] off the UI isolate. For a [project] that shows missing
/// modules as black boxes, the black-box pins are given directions there
/// too ([inferBlackBoxPorts]); otherwise the report is
/// [BlackBoxReport.none]. `null` when [cancelSignal] fires first.
Future<({NetlistModel model, BlackBoxReport report})?> _parse(
  NetcruxProject project,
  _NetlistDocument document, {
  Future<void>? cancelSignal,
}) async {
  final path = document.path;
  if (project.blackBoxMissingModules) {
    return path != null
        ? await parseNetlistFileWithBlackBoxesOnIsolate(
            path,
            cancelSignal: cancelSignal,
          )
        : await parseNetlistWithBlackBoxesOnIsolate(
            document.text!,
            cancelSignal: cancelSignal,
          );
  }
  final model = path != null
      ? await parseNetlistFileOnIsolate(path, cancelSignal: cancelSignal)
      : await parseNetlistOnIsolate(document.text!, cancelSignal: cancelSignal);
  return model == null ? null : (model: model, report: BlackBoxReport.none);
}

/// The Yosys probe result, or a [LoadedNetlistErrorKind.yosysUnavailable]
/// failure when there is no usable Yosys.
Future<YosysAvailability> _requireYosys(Ref ref) async {
  final availability = await ref.read(yosysAvailabilityProvider.future);
  if (!availability.isAvailable) {
    throw LoadedNetlistException(
      'Yosys is not available: '
      '${availability.unavailableReason ?? 'unknown reason'}',
      kind: LoadedNetlistErrorKind.yosysUnavailable,
      detail: availability.unavailableReason,
    );
  }
  return availability;
}

/// The typed failure for a Yosys run that timed out or exited non-zero.
LoadedNetlistException _failureFor(
  YosysRunResult result, {
  SvFrontendGap? frontendGap,
}) {
  if (result is YosysRunTimeout) {
    final timeout = YosysTimeoutException(result.budget);
    return LoadedNetlistException(
      timeout.message,
      cause: timeout,
      kind: LoadedNetlistErrorKind.timeout,
      timeoutSeconds: result.budget.inSeconds,
    );
  }
  final failure = result as YosysRunFailure;
  // VHDL is lowered by a standalone `ghdl --synth` before Yosys runs
  // (no Yosys GHDL plugin). A ghdl analyze/synth error, or a missing
  // ghdl binary, comes back as a YosysRunFailure whose stderr carries
  // the actionable ghdl diagnostic; it surfaces as a non-zero-exit
  // pipeline error with that stderr shown in the details section, the
  // same envelope any tool failure uses.
  final stderr = failure.stderr;
  // `hierarchy -check` refusing an instance of a module nothing defines.
  // Matched on the message rather than reported as a plain non-zero exit,
  // so the error view can offer the black-box option.
  if (failure.kind == YosysFailureKind.nonZeroExit &&
      stderr.contains(_missingModuleMarker)) {
    return LoadedNetlistException(
      'Elaboration failed: a module is not part of the design',
      cause: stderr,
      kind: LoadedNetlistErrorKind.missingModule,
      exitCode: failure.exitCode,
      detail: stderr,
      missingModule: missingModuleIn(stderr),
    );
  }
  // yosys-slang refusing an instance of a module nothing defines, before
  // `hierarchy` runs. It has no way to leave such a module undefined (its
  // option for that was removed upstream), so the black-box option cannot
  // help and is not offered.
  final slangModule = slangUnknownModuleIn(stderr);
  if (failure.kind == YosysFailureKind.nonZeroExit && slangModule != null) {
    return LoadedNetlistException(
      'Elaboration failed: a module is not defined',
      cause: stderr,
      kind: LoadedNetlistErrorKind.missingModule,
      exitCode: failure.exitCode,
      detail: stderr,
      missingModule: slangModule,
      readBySlang: true,
    );
  }
  return LoadedNetlistException(
    'Elaboration failed with exit code ${failure.exitCode}',
    cause: stderr.isEmpty ? null : stderr,
    kind: LoadedNetlistErrorKind.nonZeroExit,
    exitCode: failure.exitCode,
    detail: stderr.isEmpty ? null : stderr,
    // Only when the failure is still the built-in reader's: a slang re-run
    // that failed for its own reason reports that instead.
    frontendGap: frontendGap != null && svFrontendGapIn(stderr) == frontendGap
        ? frontendGap
        : null,
  );
}

/// [request] read by [frontend] instead of its own.
YosysRunRequest _withFrontend(
  YosysRunRequest request,
  YosysFrontend frontend,
) => YosysRunRequest(
  sources: request.sources,
  topModule: request.topModule,
  defines: request.defines,
  includePaths: request.includePaths,
  extraCommands: request.extraCommands,
  vhdlStandard: request.vhdlStandard,
  vhdlTopUnit: request.vhdlTopUnit,
  frontend: frontend,
  slangOptions: request.slangOptions,
  allowUndefinedModules: request.allowUndefinedModules,
);

/// What Yosys's `hierarchy -check` says of an instance whose module no
/// source defines: ``Module `\X' referenced in module `\top' in cell
/// `\u1' is not part of the design.``
const String _missingModuleMarker = 'is not part of the design';

final RegExp _missingModulePattern = RegExp(
  r"Module `\\?([^']+)' referenced in module .* is not part of the design",
);

/// The module name in Yosys's missing-module error in [stderr], without the
/// backslash Yosys puts in front of a user identifier, or `null` when
/// [stderr] has no such error.
@visibleForTesting
String? missingModuleIn(String stderr) =>
    _missingModulePattern.firstMatch(stderr)?.group(1);

/// What yosys-slang says of an instance whose module no source defines:
/// `top.sv:4: ERROR: unknown module 'mystery'`.
final RegExp _slangUnknownModulePattern = RegExp(
  "ERROR: unknown module '([^']+)'",
);

/// The first module name in yosys-slang's unknown-module error in
/// [stderr], or `null` when [stderr] has no such error.
@visibleForTesting
String? slangUnknownModuleIn(String stderr) =>
    _slangUnknownModulePattern.firstMatch(stderr)?.group(1);
