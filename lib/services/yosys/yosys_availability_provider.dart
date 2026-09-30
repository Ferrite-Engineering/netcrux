// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_yosys/crux_yosys.dart';
import 'package:netcrux/services/yosys/path_augmenting_process_runner.dart';
import 'package:netcrux/services/yosys/yosys_executable_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'yosys_availability_provider.g.dart';

/// The [YosysAvailabilityService] used by the rest of the app. Test
/// code overrides this provider to inject a service backed by a fake
/// [ProcessRunner] so subprocess invocations never happen.
///
/// The service is rebuilt whenever the effective executable path
/// changes — settings change or `--yosys-path <path>` CLI override.
/// Consumers should call `ref.invalidate(yosysAvailabilityProvider)`
/// after the path changes (the Settings UI does so on every save).
@Riverpod(keepAlive: true)
YosysAvailabilityService yosysAvailabilityService(Ref ref) {
  final executable = ref.watch(effectiveYosysExecutableProvider);
  return YosysAvailabilityService(
    executableNameOverride: executable,
    // Ensure Homebrew engine dirs are on PATH for a Finder-launched app.
    runner: const PathAugmentingProcessRunner(),
  );
}

/// Probes the environment for a usable Yosys installation. Returned
/// as a Riverpod async provider so consumers (Welcome screen,
/// project loader, settings panel) can render an "install Yosys"
/// hint while the probe is in flight and react to refreshes without
/// scattering manual state.
///
/// Surfaces a [YosysAvailability] — never throws — so widget code
/// can pattern-match on the result instead of wrapping
/// `AsyncValue.when` in extra error handling. The provider is
/// `keepAlive` so a single probe is reused across the app; call
/// `ref.invalidate(yosysAvailabilityProvider)` after the user
/// changes the configured executable to re-probe.
@Riverpod(keepAlive: true)
Future<YosysAvailability> yosysAvailability(Ref ref) =>
    ref.watch(yosysAvailabilityServiceProvider).probe();
