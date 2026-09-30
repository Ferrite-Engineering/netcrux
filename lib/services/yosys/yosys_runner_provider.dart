// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_yosys/crux_yosys.dart';
import 'package:netcrux/services/yosys/path_augmenting_process_runner.dart';
import 'package:netcrux/services/yosys/yosys_executable_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'yosys_runner_provider.g.dart';

/// The [YosysRunner] used by the elaboration pipeline. Test code
/// overrides this provider to inject a runner with a fake
/// `ProcessRunner` so subprocess invocations stay out of the test
/// suite.
///
/// The runner is rebuilt whenever the effective executable path
/// changes — either because the user picked a new
/// `YosysPathMode` / `yosysCustomPath` in Settings → Engines, or
/// because the `--yosys-path <path>` CLI override is installed via
/// [cliYosysPathOverrideProvider]. A rebuild produces a fresh runner
/// pointing at the new binary; downstream `loadedNetlistProvider`
/// invalidation belongs to the settings notifier, not this provider.
@Riverpod(keepAlive: true)
YosysRunner yosysRunner(Ref ref) {
  final executable = ref.watch(effectiveYosysExecutableProvider);
  final ghdlExecutable = ref.watch(effectiveGhdlExecutableProvider);
  return YosysRunner(
    executable: executable,
    // The standalone GHDL binary used to lower VHDL sources to Verilog.
    ghdlExecutable: ghdlExecutable,
    // Ensure Homebrew engine dirs are on PATH for a Finder-launched app.
    processRunner: const PathAugmentingProcessRunner(),
  );
}
