// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';

import 'package:crux_yosys/crux_yosys.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/features/project/providers/current_project_provider.dart';
import 'package:netcrux/features/project/providers/loaded_netlist_provider.dart';
import 'package:netcrux/services/yosys/yosys_availability_provider.dart';
import 'package:netcrux/services/yosys/yosys_runner_provider.dart';
import 'package:netcrux/services/yosys/yosys_timeout_exception.dart';
import '../../helpers/telemetry_test_overrides.dart';

/// A [ProcessRunner] that reports a fixed [ProcessTermination] without
/// touching the filesystem — stands in for a Yosys that the runner had to
/// kill. It also captures whether a `timeout` / `cancelSignal` reached it,
/// proving the timeout wiring actually plumbs the budget through.
class _KilledProcessRunner implements ProcessRunner {
  _KilledProcessRunner(this.termination);

  final ProcessTermination termination;
  Duration? capturedTimeout;
  Future<void>? capturedCancelSignal;

  @override
  Future<ProcessRunResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    Duration? timeout,
    Future<void>? cancelSignal,
    String? stdoutFilePath,
    void Function(String line)? onStderrLine,
  }) async {
    capturedTimeout = timeout;
    capturedCancelSignal = cancelSignal;
    return ProcessRunResult(
      exitCode: -9,
      stdout: '',
      stderr: 'killed',
      termination: termination,
    );
  }
}

ProviderContainer _container(_KilledProcessRunner processRunner) {
  final container = ProviderContainer(
    overrides: [
      ...netcruxTelemetryTestOverrides(),
      // Yosys is "available" so build() proceeds to runner.run.
      yosysAvailabilityProvider.overrideWith(
        (ref) async => const YosysAvailability.available(
          executablePath: 'yosys',
          versionString: 'Yosys 0.50',
        ),
      ),
      // The runner maps the fake termination into a YosysRunTimeout /
      // YosysRunCancelled via its real switch.
      yosysRunnerProvider.overrideWithValue(
        YosysRunner(
          processRunner: processRunner,
          executable: 'yosys',
          tempDirectory: Directory.systemTemp,
        ),
      ),
    ],
  );
  // A pending source file drives build() past the empty-state guard. The
  // path need not exist — _estimateSize tolerates an unstattable file.
  container.read(currentProjectProvider.notifier).setSourceFiles(
    const <String>['/tmp/does_not_exist_top.v'],
  );
  return container;
}

/// Triggers the elaboration build and resolves with the first error the
/// notifier surfaces into its [AsyncValue] state.
Future<Object> _firstError(ProviderContainer container) {
  final completer = Completer<Object>();
  final sub = container.listen<AsyncValue<NetlistModel?>>(
    loadedNetlistProvider,
    (previous, next) {
      final error = next.error;
      if (error != null && !completer.isCompleted) completer.complete(error);
    },
    fireImmediately: true,
  );
  return completer.future
      .timeout(const Duration(seconds: 5))
      .whenComplete(sub.close);
}

void main() {
  group('elaboration timeout wiring', () {
    test(
      'a timed-out Yosys surfaces a YosysTimeoutException',
      () async {
        final runner = _KilledProcessRunner(ProcessTermination.timedOut);
        final container = _container(runner);
        addTearDown(container.dispose);

        // Assert on the AsyncValue's error rather than `loadedNetlistProvider
        // .future`: a throwing elaboration build leaves the keepAlive
        // notifier in a loading-with-error state in a bare ProviderContainer
        // (the pre-existing "Yosys not available" path behaves identically),
        // so `.future` does not settle under test. The error itself does
        // land in the state, which is what the diagnostics UI reads.
        final error = await _firstError(container);
        expect(error, isA<LoadedNetlistException>());
        expect(
          (error as LoadedNetlistException).cause,
          isA<YosysTimeoutException>(),
        );
        // The size-aware budget (30 s floor for the unstattable source)
        // actually reached the runner.
        expect(runner.capturedTimeout, isNotNull);
        expect(runner.capturedTimeout, greaterThan(Duration.zero));
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );

    test(
      'a cancelled elaboration yields the empty state, not an error',
      () async {
        final runner = _KilledProcessRunner(ProcessTermination.cancelled);
        final container = _container(runner);
        addTearDown(container.dispose);

        final model = await container.read(loadedNetlistProvider.future);
        expect(model, isNull);
        // A cancel signal was plumbed through so a real tab-close could fire.
        expect(runner.capturedCancelSignal, isNotNull);
      },
    );
  });
}
