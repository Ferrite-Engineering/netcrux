// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// How the design currently loaded into a tab got there.
///
/// NetCrux has three distinct entry paths into the elaboration pipeline, and
/// which of them people actually use is the roadmap question `design.elaborated`
/// exists to answer. The paths differ in what the user had
/// to do, not in what the pipeline then does — all three end at a
/// [`NetcruxProject`] handed to `currentProjectProvider`, so nothing downstream
/// can tell them apart. Hence this marker.
///
/// **Not a field of [`NetcruxProject`].** A project is the durable,
/// version-controllable description of a design; how it was opened on this
/// machine is not a property of the design and must never be written into a
/// `.netcrux-project` file. It rides on the notifier instead — see
/// `CurrentProject.activeSource`.
///
/// The constants are a closed set on purpose: the value reaches telemetry
/// through `telemetryEnumToken`, which takes an `Enum` precisely so a file name
/// or a path can never be washed into a well-formed token (event properties
/// are a closed vocabulary, never free text — `https://edacrux.app/telemetry`).
enum NetcruxDesignSource {
  /// Source files chosen directly — the welcome screen's "Open Source
  /// Files…", a CLI positional, a session restore, or a CXP peer's
  /// `request_open_source`.
  rtl,

  /// A `.netcrux-project` file, which carries its own elaboration knobs
  /// (top module, defines, include paths, extra Yosys commands).
  project,

  /// A Vivado-style `.f` filelist, expanded by `FilelistReader`.
  filelist,

  /// An already-elaborated netlist JSON, opened directly — no HDL
  /// elaboration runs, so there is no top module to resolve at open time.
  ///
  /// Distinct from [rtl] because recording a netlist as RTL is simply
  /// untrue: a Yosys netlist is the *output* of elaboration, not source. The
  /// `schematic.opened` audit line is the surface that makes it matter — an
  /// audit trail reading `source: "rtl"` for a file containing no RTL
  /// misdescribes the one thing it was asked to describe.
  netlistJson,
}
