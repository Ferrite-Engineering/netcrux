// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// `netcrux --help`, answered by the desktop runner before it creates a window
// or starts the Flutter engine. The Dart side (`bootstrap` in lib/app.dart)
// keeps its own `--help` branch as the fallback for an embedder that does not
// use these runners.
//
// kNetCruxHelpText is a copy of cliHelpText() in
// lib/services/cli/cli_args.dart. test/static/cli_help_runner_test.dart keeps
// the two identical and keeps this file ASCII (a Windows build without /utf-8
// would read other bytes in the console's code page). Edit both together.
//
// Included by the open-core and Pro runners on Linux (main.cc) and Windows
// (main.cpp). Header only, standard library only.

#ifndef NETCRUX_CLI_HELP_H_
#define NETCRUX_CLI_HELP_H_

#include <cstddef>
#include <string>
#include <vector>

static const char kNetCruxHelpText[] = R"NETCRUXHELP(NetCrux: netlist schematic browser for Verilog, SystemVerilog, and VHDL

Usage:
  netcrux [options] [files...]

Options:
  --workspace <path>  Open a .netcrux-workspace named workspace at startup
                      (replaces the auto-saved workspace document).
  --session <path>    Open a session export at startup.
  --yosys-path <path> Override the Yosys binary used for elaboration for
                      this run only.
  --netlist-reader <yosys|native>
                      Choose how a gate-level Verilog netlist is read for
                      this run only: `native` uses the built-in reader (a
                      design it cannot read still falls back to Yosys),
                      `yosys` always runs Yosys. Overrides Settings >
                      Engines and the project's netlistReader key.
  --symbol-library <path>
                      NetCrux Pro: read a Symlib symbol library, or every
                      .sym and .symlib file in a folder, and draw the cells
                      it names with its symbols. Repeat for more libraries;
                      a later one wins over an earlier one. Ignored by the
                      open-core build.
  --no-restore       Launch without restoring the previous session's tabs
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
  *                    -> HDL source file (.v, .v.gz, .sv, .svh, .vh, .vhd, .vhdl);
                          each opens as a separate tab

Examples:
  netcrux examples/cdc-capture/cdc-capture.netcrux-project
  netcrux cpu.sv alu.sv --yosys-path /opt/oss-cad-suite/bin/yosys
  netcrux --workspace team-review.netcrux-workspace
)NETCRUXHELP";

// True when [arg] begins with "netcrux:" in any case, which is how the Dart
// side (NetCruxLaunchArgs.split) tells a link from a command line.
inline bool NetCruxArgIsLink(const std::string& arg) {
  static const char kScheme[] = "netcrux:";
  const std::size_t n = sizeof(kScheme) - 1;
  if (arg.size() < n) {
    return false;
  }
  for (std::size_t i = 0; i < n; i++) {
    char c = arg[i];
    if (c >= 'A' && c <= 'Z') {
      c = static_cast<char>(c - 'A' + 'a');
    }
    if (c != kScheme[i]) {
      return false;
    }
  }
  return true;
}

// True when the command line (without the program name, UTF-8) asks for help
// and is not a link launch. A launch that carries a link is that link and
// nothing else, as in bootstrap.
inline bool NetCruxHelpRequested(const std::vector<std::string>& args) {
  bool help = false;
  for (const std::string& arg : args) {
    if (NetCruxArgIsLink(arg)) {
      return false;
    }
    if (arg == "--help" || arg == "-h") {
      help = true;
    }
  }
  return help;
}

#endif  // NETCRUX_CLI_HELP_H_
