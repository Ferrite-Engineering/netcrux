// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_project/crux_project.dart';
import 'package:netcrux/core/cli/cli_launch_intent.dart';
import 'package:path/path.dart' as p;

/// Pure-Dart parser that turns CLI args from `main(args)` into a
/// [CliLaunchIntent] plus the optional flag overrides ([yosysPathOverride]).
///
/// Positional rules:
///
/// - **No args** → [CliLaunchIntent.empty]. Shows the empty-canvas state.
/// - **Exactly one `.netcrux-project`, `.netcrux` or `<design>.crux-project`
///   arg, or one directory** → [CliLaunchIntent.openProject]. A directory
///   opens the design manifest inside it.
/// - **One or more HDL source files** (`.v`, `.sv`, `.svh`, `.vh`, `.vhd`,
///   `.vhdl`) → [CliLaunchIntent.openSourceFiles].
/// - **Mixed or unrecognized extensions** → falls back to source-files
///   semantics so the user still sees their files in a new tab; the
///   elaboration step is responsible for surfacing format errors.
///
/// `--flag value` and `--flag=value` arguments are stripped from the
/// positional list. `--yosys-path <path>` is surfaced via
/// [yosysPathOverride]; bootstrap installs the value on
/// `cliYosysPathOverrideProvider` so the elaboration backend honours it for
/// the session.
class CliArgParser {
  /// Const constructor — parser is stateless.
  ///
  /// [isDirectory] is the one filesystem question the parser asks, about a
  /// lone positional argument; tests inject it.
  const CliArgParser({this.isDirectory = _isDirectorySync});

  /// Whether a path names an existing directory.
  final bool Function(String path) isDirectory;

  static bool _isDirectorySync(String path) =>
      FileSystemEntity.isDirectorySync(path);

  /// Returns the launch intent corresponding to [args].
  ///
  /// Precedence:
  ///
  /// - `--workspace <path>` → [`CliLaunchIntent.openWorkspace`]. Wins
  ///   over every other intent — positional args + `--session` are
  ///   ignored when the workspace flag is present (the workspace
  ///   already carries its own tabs).
  /// - `--session <path>` → [`CliLaunchIntent.openSession`]. Wins over
  ///   positional args.
  /// - One positional `.netcrux-project`, `.netcrux` or
  ///   `<design>.crux-project`, or one directory → opens as a project.
  ///   (Sessions, suite manifests and design directories opened via a
  ///   positional path follow the open-project path; the dispatcher branches
  ///   inside.)
  /// - One or more positional HDL source files → opens each as a
  ///   **separate tab** in the active pane (workspace adoption — one
  ///   tab per file).
  /// - No positional args + no flags → [`CliLaunchIntent.empty`].
  CliLaunchIntent parse(List<String> args) {
    final workspacePath = workspacePathOverride(args);
    if (workspacePath != null) {
      return CliLaunchIntent.openWorkspace(workspacePath);
    }
    final sessionPath = sessionPathOverride(args);
    if (sessionPath != null) {
      return CliLaunchIntent.openSession(sessionPath);
    }
    final positional = _stripFlags(args);
    if (positional.isEmpty) return const CliLaunchIntent.empty();
    if (positional.length == 1 && _isProject(positional.single)) {
      return CliLaunchIntent.openProject(positional.single);
    }
    return CliLaunchIntent.openSourceFiles(List.unmodifiable(positional));
  }

  /// The launch intent for a start with [args], falling back to the document
  /// the operating system opened the app with.
  ///
  /// [openedDocument] is asked only when [args] name nothing. A launch with
  /// both is left to the argument; the document is still delivered, after
  /// it, on the running app's document stream.
  Future<CliLaunchIntent> parseLaunch(
    List<String> args, {
    required Future<String?> Function() openedDocument,
  }) async {
    final fromArgs = parse(args);
    if (fromArgs is! EmptyCliLaunch) return fromArgs;
    final document = await openedDocument();
    if (document == null || document.isEmpty) return fromArgs;
    return parseOpenedDocument(document);
  }

  /// The launch intent for one document the operating system asked the app
  /// to open — a Finder double-click, "Open With", or a drop on the Dock.
  ///
  /// The same routing as that path given alone on the command line, so the
  /// document reaches the same open flow, with one addition: a
  /// `.netcrux-workspace`, which the command line only opens behind
  /// `--workspace`, opens as a workspace rather than as a source file.
  /// Flags are never parsed out of [path]; it is a path, whatever it spells.
  CliLaunchIntent parseOpenedDocument(String path) {
    if (p.extension(path).toLowerCase() == '.netcrux-workspace') {
      return CliLaunchIntent.openWorkspace(path);
    }
    if (_isProject(path)) return CliLaunchIntent.openProject(path);
    return CliLaunchIntent.openSourceFiles(List.unmodifiable(<String>[path]));
  }

  /// Returns the value of the `--yosys-path` flag in [args], or `null`
  /// when absent / empty. Accepts both `--yosys-path /usr/bin/yosys`
  /// and `--yosys-path=/usr/bin/yosys`.
  String? yosysPathOverride(List<String> args) =>
      _flagValue(args, 'yosys-path');

  /// Returns the value of the `--session` flag, or `null` when absent.
  /// Accepts `--session foo.netcrux` and `--session=foo.netcrux`.
  String? sessionPathOverride(List<String> args) => _flagValue(args, 'session');

  /// Returns the value of the `--workspace` flag, or `null` when absent.
  /// Accepts `--workspace foo.netcrux-workspace` and the `=` form.
  String? workspacePathOverride(List<String> args) =>
      _flagValue(args, 'workspace');

  String? _flagValue(List<String> args, String name) {
    final prefix = '--$name';
    final eqPrefix = '$prefix=';
    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      if (arg == prefix) {
        if (i + 1 >= args.length) return null;
        final next = args[i + 1];
        if (next.isEmpty) return null;
        return next;
      }
      if (arg.startsWith(eqPrefix)) {
        final value = arg.substring(eqPrefix.length);
        return value.isEmpty ? null : value;
      }
    }
    return null;
  }

  /// Project-flavored files, and directories, route to the open-project
  /// intent, which branches on the path again to pick a reader.
  ///
  /// `.netcrux-project` has to be matched explicitly: `p.extension` returns
  /// the whole `.netcrux-project` suffix, so an equality test against
  /// `.netcrux` alone rejects the canonical project extension and sends it
  /// down the HDL-source branch, where Yosys is asked to parse JSON.
  ///
  /// The suite manifest is matched by `CruxProjectParser.isManifestPath`,
  /// which accepts `<design>.crux-project` and the legacy bare
  /// `.crux-project`, whose leading-dot basename has an empty `p.extension`.
  /// A directory is a design directory: the open flow finds the one manifest
  /// in it, or says why it cannot.
  ///
  /// The session and project suffixes are spelled literally rather than read
  /// from `kNetcruxProjectExtension` / `NetcruxSession.fileExtension` because
  /// `core/` may not import `domain/` (see `docs/ARCHITECTURE.md` §6.2).
  bool _isProject(String path) {
    if (CruxProjectParser.isManifestPath(path)) return true;
    final extension = p.extension(path).toLowerCase();
    if (extension == '.netcrux' || extension == '.netcrux-project') {
      return true;
    }
    return isDirectory(path);
  }

  /// The flags that take a value (`--flag value` or `--flag=value`).
  static const _valueFlags = {'--workspace', '--session', '--yosys-path'};

  /// Strips flags from [args], leaving only positional file paths. A value
  /// flag in its `--flag value` form takes the next argument with it; every
  /// other `--flag` (a boolean flag such as `--reset-telemetry-consent`, or
  /// one this parser does not know) and every bare `-x` short flag stands
  /// alone, so the path after it is still opened.
  List<String> _stripFlags(List<String> args) {
    final out = <String>[];
    var i = 0;
    while (i < args.length) {
      final arg = args[i];
      if (arg.startsWith('--')) {
        // `--flag=value` consumes one arg; `--flag value` consumes two.
        if (_valueFlags.contains(arg) &&
            i + 1 < args.length &&
            !args[i + 1].startsWith('-')) {
          i += 2;
        } else {
          i += 1;
        }
        continue;
      }
      if (arg.startsWith('-') && arg.length > 1) {
        i += 1;
        continue;
      }
      out.add(arg);
      i += 1;
    }
    return out;
  }
}
