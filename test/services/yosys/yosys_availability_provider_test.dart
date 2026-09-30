// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_yosys/crux_yosys.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/services/yosys/yosys_availability_provider.dart';

class _FakeRunner implements ProcessRunner {
  _FakeRunner(this.result);
  final ProcessRunResult result;

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
    return result;
  }
}

void main() {
  group('yosysAvailabilityProvider', () {
    test('resolves to the result produced by the service override', () async {
      final container = ProviderContainer(
        overrides: [
          yosysAvailabilityServiceProvider.overrideWithValue(
            YosysAvailabilityService(
              runner: _FakeRunner(
                const ProcessRunResult(
                  exitCode: 0,
                  stdout: 'Yosys 0.50 (test)\n',
                  stderr: '',
                ),
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final availability = await container.read(
        yosysAvailabilityProvider.future,
      );

      expect(availability.isAvailable, isTrue);
      expect(availability.versionString, 'Yosys 0.50 (test)');
    });

    test('surfaces a not-found probe without throwing', () async {
      final container = ProviderContainer(
        overrides: [
          yosysAvailabilityServiceProvider.overrideWithValue(
            YosysAvailabilityService(
              runner: _FakeRunner(
                const ProcessRunResult(
                  exitCode: 0,
                  stdout: 'unrelated output',
                  stderr: '',
                ),
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final availability = await container.read(
        yosysAvailabilityProvider.future,
      );

      expect(availability.isAvailable, isFalse);
      expect(
        availability.unavailableReason,
        YosysUnavailableReason.bannerUnparsed,
      );
    });
  });
}
