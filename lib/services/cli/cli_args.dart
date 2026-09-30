// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// App-launch CLI flags — the suite-shared `--reset` / `--no-restore` /
/// `--help` contract, ported from WaveCrux's `services/cli/cli_args.dart`.
///
/// NetCrux's *primary* CLI surface (positional HDL files, `--workspace`,
/// `--session`, `--yosys-path`) is owned by [`CliArgParser`]
/// (`core/cli/cli_arg_parser.dart`). This module only handles the launch
/// recovery flags, which `bootstrap()` consumes before that parser runs.
/// Tests build a [CliArgs] directly to exercise startup behavior without
/// touching `Platform.executableArguments`.
library;

/// Parsed result of app-launch flag parsing.
///
/// Pure-data structure consumed by `bootstrap()` to decide whether to clear
/// persisted state ([reset]) and/or skip this launch's workspace restore
/// ([noRestore]).
class CliArgs {
  /// Creates a parsed flag set; defaults describe a normal launch.
  const CliArgs({
    this.reset = false,
    this.noRestore = false,
  });

  /// `--reset` flag — clear all persisted restore state (the auto-managed
  /// `workspace.json` and every per-tab session sidecar) before launching
  /// into a fresh, empty workspace. The recovery escape hatch for a session
  /// so corrupt it wedges startup. Destructive but scoped: it does NOT touch
  /// app settings, the keymap, or recent-files history.
  final bool reset;

  /// `--no-restore` flag — skip restoring the previous session's tabs for
  /// this launch only, without deleting anything. The workspace document is
  /// left untouched on disk, so the next normal launch (or re-enabling the
  /// Settings toggle) brings the session back. The non-destructive first
  /// thing to try when the app hangs on startup: if it launches cleanly, the
  /// previous session was the culprit and `--reset` clears it permanently.
  final bool noRestore;
}

/// Parses [args] into a [CliArgs] structure.
///
/// Only `--reset` and `--no-restore` are recognized here; every other
/// argument (positional paths, `--workspace`, `--session`, `--yosys-path`,
/// unknown flags) is left for [`CliArgParser`] and silently ignored by this
/// parser — startup must never fail because a user typed `--foo` they read
/// about in an out-of-date blog post.
CliArgs parseCliArgs(List<String> args) {
  var reset = false;
  var noRestore = false;
  for (final a in args) {
    if (a == '--reset') {
      reset = true;
    } else if (a == '--no-restore') {
      noRestore = true;
    }
  }
  return CliArgs(reset: reset, noRestore: noRestore);
}

/// Returns [args] with the launch flags (`--reset`, `--no-restore`) removed.
///
/// `bootstrap()` feeds the stripped list to [`CliArgParser`], whose
/// flag-stripping heuristic would otherwise treat the *following positional
/// path* as the flag's value and drop it (`netcrux --reset top.v` must still
/// open `top.v`).
List<String> stripLaunchFlags(List<String> args) => List<String>.unmodifiable(
  args.where((a) => a != '--reset' && a != '--no-restore'),
);

/// One-line `--help` blurb listing every supported CLI flag and bare
/// positional argument. Surfaced by `netcrux --help` on stdout before the
/// UI starts.
String cliHelpText() => '''
NetCrux — netlist schematic browser for Verilog, SystemVerilog, and VHDL

Usage:
  netcrux [options] [files...]

Options:
  --workspace <path>  Open a .netcrux-workspace named workspace at startup
                      (replaces the auto-saved workspace document).
  --session <path>    Open a session export at startup.
  --yosys-path <path> Override the Yosys binary used for elaboration for
                      this run only.
  --no-restore        Launch without restoring the previous session's tabs
                      (nothing is deleted). Try this first if the app hangs
                      on startup.
  --reset             Clear all saved workspace/session state (workspace
                      document + per-tab sessions) and launch empty.
                      Settings, keymap, and recent files are kept.
  --reset-telemetry-consent
                      Testing aid. Forget this installation's telemetry
                      answer so the one-time first-launch disclosure appears
                      again. The installation ID is kept. The dialog is only
                      shown at all on a build where telemetry is live --
                      --dart-define=TELEMETRY_DEV=true, or BETA_PERIOD=false.
  --reset-eula        Testing aid. Forget this installation's licence
                      agreement acceptance so the agreement is presented
                      again on this launch.
  -h, --help          Show this help and exit.

Bare positional arguments are auto-routed by name:
  *.netcrux-project    -> project file
  *.netcrux            -> session export
  *.crux-project       -> suite design manifest
  <directory>          -> the one *.crux-project manifest inside it
  *.json               -> pre-built Yosys JSON netlist (no elaboration)
  *                    -> HDL source file (.v, .sv, .svh, .vh, .vhd, .vhdl);
                          each opens as a separate tab

Examples:
  netcrux examples/cdc-capture/cdc-capture.netcrux-project
  netcrux cpu.sv alu.sv --yosys-path /opt/oss-cad-suite/bin/yosys
  netcrux --workspace team-review.netcrux-workspace
''';
