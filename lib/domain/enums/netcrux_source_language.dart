// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Per-source-file language declaration in the `.netcrux-project`
/// schema. Mirrors LintCrux's [`ProjectSourceFileLanguage`] enum and
/// matches the LintCrux schema names so a future shared model could be
/// promoted into `crux-shared` without renaming.
///
/// [auto] is the default and infers the language from the file
/// extension. Explicit values are needed
/// for projects where the extension is misleading (a legacy `.v` file
/// that is actually SystemVerilog, for example).
///
/// The elaboration backend uses it to dispatch each source file to the
/// correct front end: Yosys `read_verilog` or `read_verilog -sv`, or, for
/// VHDL, standalone `ghdl --synth` lowering to Verilog that Yosys then
/// reads (no GHDL Yosys plugin). A `.netcrux-project` file without
/// an explicit `sourceFileLanguages` map keeps the legacy
/// auto-from-extension behavior and is fully backwards-compatible.
enum NetcruxSourceLanguage {
  /// Inferred at elaboration-time from the file extension. The
  /// extension → language mapping is:
  ///   - `.v`, `.vh` → verilog
  ///   - `.sv`, `.svh` → systemVerilog
  ///   - `.vhd`, `.vhdl` → vhdl
  ///
  /// Lookup is case-insensitive. Unknown extensions fall back to
  /// systemVerilog (the superset that Yosys's `read_verilog -sv`
  /// accepts).
  auto,

  /// IEEE 1364 Verilog. Emits `read_verilog`.
  verilog,

  /// IEEE 1800 SystemVerilog. Emits `read_verilog -sv`.
  systemVerilog,

  /// IEEE 1076 VHDL. Lowered to Verilog by a standalone
  /// `ghdl --synth --out=verilog … -e <top>` run, whose output Yosys then
  /// reads with `read_verilog`. The `ghdl-yosys-plugin` is NOT used and no
  /// `plugin -i ghdl` is ever emitted — `crux_yosys`'s runner test asserts
  /// that. A plain GHDL build is therefore sufficient; a plugin-capable
  /// Yosys is not.
  vhdl,
}
