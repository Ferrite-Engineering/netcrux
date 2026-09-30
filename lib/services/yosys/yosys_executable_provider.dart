// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:netcrux/domain/enums/yosys_path_mode.dart';
import 'package:netcrux/features/settings/providers/app_settings_provider.dart';
import 'package:netcrux/services/engines/bundled_binary_resolver.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'yosys_executable_provider.g.dart';

/// Session-scope override for the Yosys executable path, set by
/// `bootstrap()` from the `--yosys-path <path>` CLI flag.
///
/// When non-null this wins over the Settings → Engines → Yosys
/// preference (auto / bundled / custom) — exactly mirroring how
/// command-line invocations of any EDA tool override the saved
/// preference. `null` means "no CLI override; consult settings".
@Riverpod(keepAlive: true)
String? cliYosysPathOverride(Ref ref) => null;

/// The [BundledBinaryResolver] consulted by the [YosysPathMode.bundled]
/// case in [effectiveYosysExecutable] and by [effectiveGhdlExecutable]
/// for the standalone GHDL binary.
///
/// Default returns a real resolver that consults the
/// `NETCRUX_BUNDLED_BIN_DIR` env var; tests override this provider with
/// a resolver pointed at a temp directory.
@Riverpod(keepAlive: true)
BundledBinaryResolver bundledBinaryResolver(Ref ref) {
  return const BundledBinaryResolver();
}

/// The Yosys executable NetCrux should invoke right now.
///
/// Resolution order (first non-null wins):
///
///   1. [cliYosysPathOverride] — `--yosys-path <path>` for the session
///   2. Settings: when [YosysPathMode.custom] is selected, the user's
///      configured path (empty → falls through to default)
///   3. Settings: when [YosysPathMode.bundled] is selected, the
///      bundled-binary resolver's `yosys` entry. When the env var is unset the
///      resolver returns `null` and we fall through to auto-detect, preserving
///      the UI for users who have already picked "bundled" in Settings.
///   4. Auto-detect — `null`, meaning the cross-suite
///      `YosysAvailabilityService` / `YosysRunner` use their default
///      executable name and let the operating system's PATH lookup
///      resolve it.
///
/// `null` means "use the cross-suite default" — services that read
/// this provider should treat it as "no override" rather than "no
/// yosys".
@Riverpod(keepAlive: true)
String? effectiveYosysExecutable(Ref ref) {
  final cli = ref.watch(cliYosysPathOverrideProvider);
  if (cli != null && cli.isNotEmpty) return cli;
  final settingsAsync = ref.watch(appSettingsProvider);
  final settings = settingsAsync.value;
  if (settings == null) return null;
  switch (settings.yosysPathMode) {
    case YosysPathMode.autoDetect:
      return null;
    case YosysPathMode.bundled:
      // Ask the bundled-binary resolver. When the env var is
      // unset (the common path: release packaging sets none) the
      // resolver returns null and we fall through to PATH — same UX
      // as auto-detect, with the seam already exercised.
      final resolver = ref.watch(bundledBinaryResolverProvider);
      return resolver.resolve('yosys');
    case YosysPathMode.custom:
      final path = settings.yosysCustomPath;
      if (path.isEmpty) return null;
      return path;
  }
}

/// The standalone GHDL executable NetCrux should invoke to lower VHDL
/// sources to Verilog before Yosys runs, or `null` to let PATH resolve
/// `ghdl`.
///
/// Used by [YosysRunner]: for any request containing VHDL, the runner
/// spawns `ghdl --synth --out=verilog … -e <top>` and feeds the emitted
/// Verilog into the ordinary `read_verilog` pipeline (no Yosys GHDL
/// plugin is involved).
///
/// The lookup honors the user's Settings → Engines → Yosys mode the same
/// way [effectiveYosysExecutable] does: the bundled-binary resolver is
/// consulted in the `bundled` case; the `custom` and `autoDetect` modes
/// both return `null` and let the operating system's PATH lookup resolve
/// `ghdl`. `null` means "use the cross-suite default" — treat it as "no
/// override", not "no GHDL".
@Riverpod(keepAlive: true)
String? effectiveGhdlExecutable(Ref ref) {
  final settingsAsync = ref.watch(appSettingsProvider);
  final settings = settingsAsync.value;
  if (settings == null) return null;
  if (settings.yosysPathMode != YosysPathMode.bundled) return null;
  final resolver = ref.watch(bundledBinaryResolverProvider);
  return resolver.resolve('ghdl');
}
