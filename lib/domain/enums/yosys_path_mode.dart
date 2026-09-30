// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// How NetCrux selects the Yosys binary at elaboration time.
///
/// The three knobs the
/// user can tune from Settings → Engines → Yosys, plus the
/// `--yosys-path <path>` CLI override that wins over all three at
/// session scope.
enum YosysPathMode {
  /// PATH search — let the cross-suite `YosysAvailabilityService`
  /// invoke the default executable name (`yosys` / `yosys.exe`) and
  /// rely on the operating system's PATH lookup. Default for fresh
  /// installs that don't yet know the user's preference.
  autoDetect,

  /// Use the binary bundled inside the NetCrux distribution.
  ///
  /// No binary is bundled with the distribution, so this option renders
  /// in the UI but degrades to [autoDetect] under the hood. The seam
  /// exists so the Settings model does not change when one is.
  bundled,

  /// Use the executable at the path the user supplied. Surfaced in
  /// the Settings UI as a text field with live `yosys -V` validation.
  custom,
}
