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
import 'package:netcrux/services/telemetry/netcrux_design_language_mix.dart';
import 'package:netcrux/services/web/web_json_loader.dart';
import 'package:netcrux/services/yosys/elaboration_cache_provider.dart';
import 'package:netcrux/services/yosys/elaboration_cache_service.dart';
import 'package:netcrux/services/yosys/elaboration_timeout_provider.dart';
import 'package:netcrux/services/yosys/isolate_netlist_parser.dart';
import 'package:netcrux/services/yosys/prebuilt_netlist_loader_provider.dart';
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
  Future<NetlistModel?> _loadPrebuiltNetlist(NetcruxProject project) {
    final cancel = Completer<void>();
    ref.onDispose(() {
      if (!cancel.isCompleted) cancel.complete();
    });
    // No Yosys ran, so there is no stderr to show; clear what a previous
    // elaboration in this tab left behind.
    ref.read(elaborationStderrProvider.notifier).set('');
    return _readPrebuiltNetlist(ref, project, cancelSignal: cancel.future);
  }

  Future<({NetlistModel? model, bool cached})> _elaborate(
    NetcruxProject project,
  ) async {
    final availability = await _requireYosys(ref);
    final runner = ref.read(yosysRunnerProvider);
    final request = _buildRequest(project);
    // Elaboration cache (a re-open of an unchanged design is a sub-50 ms cache
    // hit): fingerprint = per-file path+size+mtime + yosys version + the
    // request options. A hit returns the previously parsed model and its stderr
    // without spawning yosys or re-parsing. A null key (a source vanished)
    // simply bypasses the cache.
    final cache = ref.read(elaborationCacheServiceProvider);
    final cacheKey = await ElaborationCacheService.buildKey(
      sourceFilePaths: project.sourceFiles,
      yosysVersion: availability.versionString ?? '',
      topModule: request.topModule,
      defines: request.defines,
      includePaths: request.includePaths,
      extraCommands: request.extraCommands,
    );
    if (cacheKey != null) {
      final hit = cache.lookup(cacheKey);
      if (hit != null) {
        ref.read(elaborationStderrProvider.notifier).set(hit.stderr);
        return (model: hit.model, cached: true);
      }
    }
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
    final YosysRunResult result;
    try {
      result = await runner.run(
        request,
        timeout: policy.killOnTimeout ? budget : null,
        cancelSignal: cancel.future,
        onStderrLine: progress.consumeStderrLine,
      );
    } finally {
      // Runs on the throwing paths too: a failed elaboration must not
      // leave the strip advertising a pass that stopped executing.
      progress.clear();
    }
    // Publish stderr — successes and failures alike — so the
    // diagnostics drawer can surface warnings even on healthy runs.
    ref.read(elaborationStderrProvider.notifier).set(result.stderr);
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
      try {
        // Parse on a background isolate so a large design (the perf report
        // measures 0.34 s @ 100K cells, 4.8 s @ 1M) doesn't freeze the UI
        // isolate inside build(). The result transfers back zero-copy via
        // Isolate.exit; the `cancel` completer (fired on dispose above)
        // hard-kills the worker, so a superseded elaboration stops parsing
        // instead of burning a core to completion.
        //
        // NOTE: this bounds *UI-thread* time, not peak memory — `rawJson`
        // is the whole write_json document already materialized as a String
        // (the runner reads it with readAsStringSync), and the streaming
        // reader's per-module slicing keeps only O(largest module) live on
        // top of that. Behavior is drop-in compatible with the legacy
        // in-memory `YosysJsonParser`, retained for tests. See
        // ARCHITECTURE.md §8.9.
        final model = await parseNetlistOnIsolate(
          result.rawJson,
          cancelSignal: cancel.future,
        );
        // Cache only a fully-parsed success (never populate the cache
        // with a partial result — cancelled and
        // failed runs return above, parse failures throw below, and a
        // null model here means the parse was cancelled mid-flight).
        if (cacheKey != null && model != null) {
          cache.store(
            cacheKey,
            ElaborationCacheEntry(
              model: model,
              stderr: result.stderr,
              approxBytes: result.rawJson.length,
            ),
          );
        }
        return (model: model, cached: false);
      } on YosysJsonParseException catch (e) {
        throw LoadedNetlistException(e.message, cause: e);
      }
    }
    throw _failureFor(result);
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
  static YosysRunRequest buildRequest(NetcruxProject project) =>
      _buildRequest(project);

  static YosysRunRequest _buildRequest(NetcruxProject project) {
    return YosysRunRequest(
      sources: <YosysSourceFile>[
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
    return await _readPrebuiltNetlist(ref, project);
  }
  await _requireYosys(ref);
  final policy = ref.read(elaborationTimeoutPolicyProvider);
  final budget = policy.timeoutFor(await LoadedNetlist._estimateSize(project));
  final result = await ref
      .read(yosysRunnerProvider)
      .run(
        LoadedNetlist._buildRequest(project),
        timeout: policy.killOnTimeout ? budget : null,
      );
  if (result is YosysRunCancelled) return null;
  if (result is! YosysRunSuccess) throw _failureFor(result);
  try {
    return await parseNetlistOnIsolate(result.rawJson);
  } on YosysJsonParseException catch (e) {
    throw LoadedNetlistException(e.message, cause: e);
  }
}

/// Reads and parses the single netlist document [project] names.
///
/// A multi-file project can only reach here in a build that cannot
/// elaborate, and there is no netlist to read in it, so it is reported as
/// the missing engine it is.
Future<NetlistModel?> _readPrebuiltNetlist(
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
        .load(project.sourceFiles.single, cancelSignal: cancelSignal);
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
LoadedNetlistException _failureFor(YosysRunResult result) {
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
  return LoadedNetlistException(
    'Elaboration failed with exit code ${failure.exitCode}',
    cause: stderr.isEmpty ? null : stderr,
    kind: LoadedNetlistErrorKind.nonZeroExit,
    exitCode: failure.exitCode,
    detail: stderr.isEmpty ? null : stderr,
  );
}
