// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_io/crux_io.dart';
import 'package:meta/meta.dart';

/// Result of an [`EditorOpenService.openSourceLocation`] attempt.
@immutable
class EditorOpenResult {
  /// Creates a result.
  const EditorOpenResult({
    required this.honored,
    this.reason,
  });

  /// Successful invocation — the configured editor was launched (no
  /// guarantee the editor actually opened, but the shell-out returned
  /// without error).
  static const EditorOpenResult ok = EditorOpenResult(honored: true);

  /// True when the configured editor was launched successfully.
  final bool honored;

  /// Human-readable failure reason. Set only when [honored] is false.
  final String? reason;
}

/// Launches the user's configured editor to open a source-code location.
///
/// The sole consumer is NetCrux's CXP `request_open_source` handler: an
/// external editor is launched only when a peer application asks for it,
/// never from a local gesture. A local "show me the source" request goes
/// to the in-app RTL Source Pane instead. The command template is read
/// from [`AppSettings.cxpEditorCommand`] — tokens `{file}` and `{line}`
/// are substituted at invocation time.
///
/// Empty command string disables shell-out and the handler responds
/// with `honored: false` so peers know NetCrux is configured to not
/// shell-out.
///
/// ## What the service refuses
///
/// `filePath` arrives over a socket from a CXP peer, and CXP authenticates
/// no sender. Two refusals stand between it and `Process.run`, both
/// reported to the peer through [`EditorOpenResult.reason`] so a legitimate
/// caller sees why rather than a silent no-op:
///
///   * a `filePath` that is not absolute — an argv element beginning with
///     `+` is an ex command to the `vim` and `emacs` command shapes, and an
///     absolute path is the one form no editor reads as an option
///     ([isAbsoluteSpawnPath]);
///   * a [commandTemplate] whose *first* token carries a placeholder —
///     that token becomes the executable, and the executable is the user's
///     choice, never a peer's.
class EditorOpenService {
  /// Creates a service. [processRunner] is overridable for tests so the
  /// service can be exercised without forking real subprocesses.
  EditorOpenService({ProcessRunner? processRunner})
    : _runner = processRunner ?? resolvingProcessRunner(Process.run);

  final ProcessRunner _runner;

  /// Launches the configured editor for [filePath]:[line]:[column].
  ///
  /// [commandTemplate] is the command-line invocation from
  /// [`AppSettings.cxpEditorCommand`]. An empty template returns
  /// `honored: false` with a documented reason.
  Future<EditorOpenResult> openSourceLocation({
    required String commandTemplate,
    required String filePath,
    required int line,
    int? column,
  }) async {
    if (commandTemplate.trim().isEmpty) {
      return const EditorOpenResult(
        honored: false,
        reason: 'No editor command configured.',
      );
    }
    // The last gate before a peer's string becomes argv. Substitution is
    // per-element, so there is no shell to inject into; the exposure is the
    // editor's own option parser, and containment — not escaping — is what
    // closes it.
    if (!isAbsoluteSpawnPath(filePath)) {
      return EditorOpenResult(
        honored: false,
        reason:
            'Refusing to open "$filePath": only absolute file paths are '
            'opened in an editor.',
      );
    }
    // Tokenize on whitespace — quoting / shell escaping is intentionally
    // out of scope for v1; users configure simple invocations like
    // `code -g {file}:{line}`. Future enhancement: shell-aware
    // tokenization with quote handling.
    final tokens = commandTemplate
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList(growable: false);
    if (tokens.isEmpty) {
      return const EditorOpenResult(
        honored: false,
        reason: 'Editor command is empty after tokenization.',
      );
    }
    // `substituted.first` becomes the executable. A template of `{file} …`
    // would therefore let the peer name the program to run — contrived,
    // but the settings field accepts any string and nothing else stops it.
    // The executable is the user's own choice, so no placeholder may reach
    // it; `{line}` and `{column}` are covered too, because a peer-chosen
    // integer in a program name is no more the user's choice than a
    // peer-chosen path.
    if (_placeholder.hasMatch(tokens.first)) {
      return EditorOpenResult(
        honored: false,
        reason:
            'Editor command "${tokens.first}" substitutes into the '
            'executable position; the executable must be a fixed program '
            'name.',
      );
    }
    final substituted = tokens
        .map((t) {
          return t
              .replaceAll('{file}', filePath)
              .replaceAll('{line}', '$line')
              .replaceAll('{column}', '${column ?? 1}');
        })
        .toList(growable: false);
    final executable = substituted.first;
    final args = substituted.skip(1).toList(growable: false);
    try {
      final result = await _runner(executable, args);
      if (result.exitCode == 0) return EditorOpenResult.ok;
      return EditorOpenResult(
        honored: false,
        reason: 'Editor exited with code ${result.exitCode}.',
      );
    } on ProcessException catch (e) {
      return EditorOpenResult(
        honored: false,
        reason: 'Failed to launch "$executable": ${e.message}',
      );
    }
  }
}

/// The substitution tokens [`EditorOpenService`] replaces. Matched against
/// the first command token so none of them can choose the executable.
final RegExp _placeholder = RegExp(r'\{(?:file|line|column)\}');

/// Signature of the underlying process-launching seam used by
/// [`EditorOpenService`]. Tests substitute a fake to assert the editor
/// invocation without forking a real subprocess.
typedef ProcessRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments,
    );

/// Wraps [launch] so the executable it is handed is resolved first, through
/// crux_io's spawn resolver.
///
/// On Windows, `CreateProcess` searches the calling process's current
/// directory ahead of `PATH`, and NetCrux's current directory is whatever
/// shell launched it — for a developer, the repository being worked on. A
/// `code.exe` committed to that repository would otherwise win. A bare name
/// is therefore resolved to the absolute path `PATH` answers with, and a
/// name `PATH` does not answer to throws the `not found on PATH`
/// [ProcessException] instead of reaching [launch] bare. That is the
/// exception [EditorOpenService.openSourceLocation] already reports as
/// "Failed to launch", with nothing started. The identity off Windows.
///
/// [host] is the machine the resolution describes: the live one when null,
/// a synthetic Windows host in a test, so the Windows branch is proven on
/// any machine.
ProcessRunner resolvingProcessRunner(
  ProcessRunner launch, {
  @visibleForTesting SpawnHost? host,
}) => (executable, arguments) async {
  final resolved = host == null
      ? requireSpawnExecutableForHost(executable)
      : host.requireExecutable(executable);
  return launch(resolved, arguments);
};
