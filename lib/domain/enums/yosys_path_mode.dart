// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// How NetCrux selects the Yosys binary at elaboration time.
///
/// Settings → Engines → Yosys offers [autoDetect] and [custom], plus the
/// `--yosys-path <path>` CLI override that wins over both at session scope.
/// [bundled] is kept only so a setting saved by an earlier version still
/// loads; the UI no longer offers it.
enum YosysPathMode {
  /// PATH search — let the cross-suite `YosysAvailabilityService`
  /// invoke the default executable name (`yosys` / `yosys.exe`) and
  /// rely on the operating system's PATH lookup. Default for fresh
  /// installs that don't yet know the user's preference.
  autoDetect,

  /// Use the binary bundled inside the NetCrux distribution.
  ///
  /// No binary is bundled with the distribution, so the UI does not offer
  /// this option. A setting already saved as [bundled] still loads, shows as
  /// Auto-detect, and resolves as [autoDetect] unless `NETCRUX_BUNDLED_BIN_DIR`
  /// names a directory holding the binary. The seam exists so the Settings
  /// model does not change when engines ship.
  bundled,

  /// Use the executable at the path the user supplied. Surfaced in
  /// the Settings UI as a text field with live `yosys -V` validation.
  custom,
}
