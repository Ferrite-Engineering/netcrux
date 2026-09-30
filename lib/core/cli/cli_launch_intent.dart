// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// The action the app should take based on its command-line arguments.
///
/// Five shapes:
///
/// 1. `netcrux` (no args) — the workspace's empty-canvas state
///    ([CliLaunchIntent.empty]).
/// 2. `netcrux project.netcrux-project` — open that saved project
///    ([CliLaunchIntent.openProject]).
/// 3. `netcrux file1.v file2.sv …` — open those source files
///    ([CliLaunchIntent.openSourceFiles]).
/// 4. `netcrux --session <path>` — open a session export
///    ([CliLaunchIntent.openSession]).
/// 5. `netcrux --workspace <path>` — open a named workspace
///    ([CliLaunchIntent.openWorkspace]).
///
/// Option flags that do not choose what to open (`--yosys-path`) are parsed
/// separately by `CliArgParser` and never become an intent.
@immutable
sealed class CliLaunchIntent {
  const CliLaunchIntent();

  /// No CLI arguments — show the workspace's empty-canvas state.
  const factory CliLaunchIntent.empty() = EmptyCliLaunch;

  /// Open the saved project at [path].
  const factory CliLaunchIntent.openProject(String path) = OpenProjectCliLaunch;

  /// Start a new tab for every entry in [paths] (Verilog / VHDL source
  /// files). Each path becomes a separate tab in the active pane.
  const factory CliLaunchIntent.openSourceFiles(List<String> paths) =
      OpenSourceFilesCliLaunch;

  /// Open a `.netcrux` session export as a single new tab in the active
  /// pane. Triggered by `--session <path>`.
  const factory CliLaunchIntent.openSession(String path) = OpenSessionCliLaunch;

  /// Open a `.netcrux-workspace` named-workspace file, replacing the
  /// current workspace after a single confirmation. Triggered by
  /// `--workspace <path>`.
  const factory CliLaunchIntent.openWorkspace(String path) =
      OpenWorkspaceCliLaunch;
}

/// Empty-launch case (no CLI args). Renders the empty-canvas state.
class EmptyCliLaunch extends CliLaunchIntent {
  /// Const constructor — value-typed.
  const EmptyCliLaunch();

  @override
  bool operator ==(Object other) => other is EmptyCliLaunch;

  @override
  int get hashCode => (EmptyCliLaunch).hashCode;
}

/// Launch with a single `.netcrux` saved project.
class OpenProjectCliLaunch extends CliLaunchIntent {
  /// Wraps an absolute or working-directory-relative project [path].
  const OpenProjectCliLaunch(this.path);

  /// The saved project path the user passed on the command line.
  final String path;

  @override
  bool operator ==(Object other) =>
      other is OpenProjectCliLaunch && other.path == path;

  @override
  int get hashCode => Object.hash(OpenProjectCliLaunch, path);
}

/// Launch with one or more Verilog / VHDL source files.
class OpenSourceFilesCliLaunch extends CliLaunchIntent {
  /// Wraps absolute or working-directory-relative HDL source [paths].
  /// Iteration order is preserved.
  const OpenSourceFilesCliLaunch(this.paths);

  /// The source files the user passed on the command line, in order.
  final List<String> paths;

  @override
  bool operator ==(Object other) {
    if (other is! OpenSourceFilesCliLaunch) return false;
    if (other.paths.length != paths.length) return false;
    for (var i = 0; i < paths.length; i++) {
      if (other.paths[i] != paths[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(OpenSourceFilesCliLaunch, Object.hashAll(paths));
}

/// Launch with a single `.netcrux` session export — opens as a single new
/// tab in the active pane.
class OpenSessionCliLaunch extends CliLaunchIntent {
  /// Wraps an absolute or working-directory-relative session [path].
  const OpenSessionCliLaunch(this.path);

  /// The session path supplied via `--session <path>`.
  final String path;

  @override
  bool operator ==(Object other) =>
      other is OpenSessionCliLaunch && other.path == path;

  @override
  int get hashCode => Object.hash(OpenSessionCliLaunch, path);
}

/// Launch with a `.netcrux-workspace` named-workspace file — replaces the
/// current workspace after a single confirmation.
class OpenWorkspaceCliLaunch extends CliLaunchIntent {
  /// Wraps an absolute or working-directory-relative workspace [path].
  const OpenWorkspaceCliLaunch(this.path);

  /// The workspace path supplied via `--workspace <path>`.
  final String path;

  @override
  bool operator ==(Object other) =>
      other is OpenWorkspaceCliLaunch && other.path == path;

  @override
  int get hashCode => Object.hash(OpenWorkspaceCliLaunch, path);
}
