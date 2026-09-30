// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:netcrux/domain/enums/netcrux_source_language.dart';

/// The HDL a design was elaborated from, as one closed token.
///
/// `design.elaborated` reports which languages are worth engineering effort.
/// A design is a *list* of source files, each with its
/// own resolved [NetcruxSourceLanguage], so the answer needs a fourth constant
/// the per-file enum does not have — [mixed] — for the very common
/// SystemVerilog-testbench-plus-Verilog-RTL and VHDL-wrapper-around-Verilog
/// shapes. That is the whole reason this is a separate enum rather than a reuse
/// of [NetcruxSourceLanguage].
///
/// It also drops [NetcruxSourceLanguage.auto], which is a *declaration* state
/// ("infer this from the extension"), never an outcome:
/// `NetcruxProject.resolveLanguage` always returns a concrete language, so
/// `auto` cannot reach a telemetry call site and listing it would be dead
/// vocabulary in the catalog.
enum NetcruxDesignLanguageMix {
  /// Every source file resolved to IEEE 1364 Verilog.
  verilog,

  /// Every source file resolved to IEEE 1800 SystemVerilog. Note this is the
  /// extension-inference fallback for an unknown suffix, so it is also what a
  /// design of `.f`-listed files with unusual extensions reports.
  systemVerilog,

  /// Every source file resolved to IEEE 1076 VHDL.
  vhdl,

  /// The design spans more than one language.
  mixed,
}

/// Folds a design's per-file resolved languages into one
/// [NetcruxDesignLanguageMix].
///
/// Returns `null` for an empty design — there is nothing to report, and the
/// elaboration pipeline returns early on an empty source list anyway, so no
/// `design.elaborated` is recorded in that case either.
NetcruxDesignLanguageMix? netcruxDesignLanguageMixFor(
  Iterable<NetcruxSourceLanguage> resolved,
) {
  final distinct = resolved.toSet();
  if (distinct.isEmpty) return null;
  if (distinct.length > 1) return NetcruxDesignLanguageMix.mixed;
  return switch (distinct.single) {
    NetcruxSourceLanguage.verilog => NetcruxDesignLanguageMix.verilog,
    NetcruxSourceLanguage.systemVerilog =>
      NetcruxDesignLanguageMix.systemVerilog,
    NetcruxSourceLanguage.vhdl => NetcruxDesignLanguageMix.vhdl,
    // `resolveLanguage` never yields `auto` — it is the "infer from extension"
    // declaration, and inference always lands on a concrete language. Mapping
    // it to `mixed` rather than throwing keeps a telemetry derivation from ever
    // being the thing that breaks an elaboration.
    NetcruxSourceLanguage.auto => NetcruxDesignLanguageMix.mixed,
  };
}
