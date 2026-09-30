// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_io/crux_io.dart';
import 'package:crux_yosys/crux_yosys.dart';

/// A [ProcessRunner] that makes the EDA engine install directories visible
/// to the child process before delegating to an inner runner.
///
/// A GUI-launched app does not always inherit the `PATH` from which an
/// engine resolves: a macOS Finder/Dock launch gets `launchd`'s truncated
/// `$PATH` (missing Homebrew's `/opt/homebrew/bin` / `/usr/local/bin`),
/// and a Windows app launched from a stale shell or an installer's "launch
/// now" carries an older process `PATH` that can omit engines the user has
/// since added (e.g. oss-cad-suite). Either way `yosys` elaboration fails
/// "not found" even though the engine is installed. This runner appends
/// the platform's [engineSearchDirs] so the spawn resolves.
///
/// The augmentation is deliberately conservative:
///   * No-op on Linux, and wherever the search dirs are already on `PATH`.
///   * Applied only when the caller passes no explicit [environment] — an
///     explicit environment is an intentional override we must not
///     clobber.
///   * Only *adds* directories that are missing; existing PATH entries
///     and their order are preserved, and if the extra directories are
///     already present the parent environment is inherited unchanged.
class PathAugmentingProcessRunner implements ProcessRunner {
  /// Creates a runner wrapping an inner runner (defaults to
  /// [DefaultProcessRunner]).
  const PathAugmentingProcessRunner({
    ProcessRunner inner = const DefaultProcessRunner(),
    // Not an initializing formal: named parameters cannot start with `_`,
    // and a public `inner` keeps the wrapped-runner seam usable by callers.
    // ignore: prefer_initializing_formals
  }) : _inner = inner;

  final ProcessRunner _inner;

  @override
  Future<ProcessRunResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    Duration? timeout,
    Future<void>? cancelSignal,
    String? stdoutFilePath,
    void Function(String line)? onStderrLine,
  }) {
    return _inner.run(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment ?? _augmentedEnvironment(),
      timeout: timeout,
      cancelSignal: cancelSignal,
      stdoutFilePath: stdoutFilePath,
      onStderrLine: onStderrLine,
    );
  }

  /// Returns `null` when nothing needs changing — on Linux, or when the
  /// [engineSearchDirs] are already on PATH — so the child inherits the
  /// parent environment exactly as before. Otherwise returns a copy of the
  /// parent environment with those dirs appended to PATH.
  static Map<String, String>? _augmentedEnvironment() {
    final dirs = engineSearchDirs();
    if (dirs.isEmpty) return null;
    final base = Map<String, String>.from(Platform.environment);
    // Match the existing key's case rather than assuming 'PATH' (it is
    // conventionally 'Path' on Windows, 'PATH' on POSIX).
    final pathKey = base.keys.firstWhere(
      (k) => k.toUpperCase() == 'PATH',
      orElse: () => 'PATH',
    );
    final augmented = appendMissingPathDirs(
      base[pathKey] ?? '',
      dirs,
      separator: Platform.isWindows ? ';' : ':',
      caseInsensitive: Platform.isWindows,
    );
    if (augmented == null) return null;
    base[pathKey] = augmented;
    return base;
  }
}
