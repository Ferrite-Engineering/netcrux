// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_updates/crux_updates.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/updates/netcrux_update_config.dart';

/// The update-check state machine as NetCrux binds it.
///
/// `crux_updates` owns the notifier, but the launch / periodic / manual /
/// suppressed contract is what the Settings → General toggle promises a
/// NetCrux user, so it is pinned here against NetCrux's own configuration
/// rather than trusted from the package suite alone.
class _FakeUpdateCheckService implements UpdateCheckService {
  _FakeUpdateCheckService({this.result, this.throwFailure = false});

  final UpdateInfo? result;
  final bool throwFailure;
  int calls = 0;

  @override
  Future<UpdateInfo?> checkForUpdate() async {
    calls++;
    if (throwFailure) {
      throw const UpdateCheckException('manifest unreachable');
    }
    return result;
  }
}

void main() {
  const newerRelease = UpdateInfo(version: '9.9.9');
  const mandatoryRelease = UpdateInfo(version: '9.9.9', mandatory: true);

  ProviderContainer containerWith({
    required _FakeUpdateCheckService service,
    bool autoCheckEnabled = true,
    Duration? checkInterval,
  }) {
    final container = ProviderContainer(
      overrides: <Override>[
        cruxUpdateConfigProvider.overrideWithValue(
          checkInterval == null
              ? netcruxUpdateConfig
              : netcruxUpdateConfig.copyWith(checkInterval: checkInterval),
        ),
        autoUpdateCheckEnabledProvider.overrideWith(
          (_) async => autoCheckEnabled,
        ),
        updateCheckServiceProvider.overrideWithValue(service),
      ],
    );
    addTearDown(container.dispose);
    // Riverpod 3 pauses a provider nobody listens to, so an eager side effect
    // (here: the launch check and the periodic timer in `build`) only runs for
    // a *listened* provider. `read` alone is not enough.
    final sub = container.listen<UpdateStatus>(
      updateStatusProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(sub.close);
    return container;
  }

  group('UpdateStatusNotifier as NetCrux configures it', () {
    test('the launch check runs and surfaces an available update', () async {
      final service = _FakeUpdateCheckService(result: newerRelease);
      final container = containerWith(service: service);

      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(service.calls, 1);
      final status = container.read(updateStatusProvider);
      expect(status, isA<UpdateStatusAvailable>());
      expect((status as UpdateStatusAvailable).info.version, '9.9.9');
    });

    test('the launch check reports current when nothing is newer', () async {
      final service = _FakeUpdateCheckService();
      final container = containerWith(service: service);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(service.calls, 1);
      expect(container.read(updateStatusProvider), isA<UpdateStatusCurrent>());
    });

    test('turning the setting off suppresses the automatic check', () async {
      final service = _FakeUpdateCheckService(result: newerRelease);
      final container = containerWith(
        service: service,
        autoCheckEnabled: false,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(
        service.calls,
        0,
        reason: 'the launch check must honour the persisted setting',
      );
      expect(container.read(updateStatusProvider), isA<UpdateStatusCurrent>());

      await container.read(updateStatusProvider.notifier).runScheduledCheck();
      expect(
        service.calls,
        0,
        reason: 'every scheduled path goes through the same gate',
      );
    });

    test('a manual check always runs, even with auto-check off', () async {
      final service = _FakeUpdateCheckService(result: newerRelease);
      final container = containerWith(
        service: service,
        autoCheckEnabled: false,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(service.calls, 0);

      await container.read(updateStatusProvider.notifier).checkNow();

      expect(service.calls, 1);
      expect(
        container.read(updateStatusProvider),
        isA<UpdateStatusAvailable>(),
      );
    });

    test('the periodic timer keeps checking', () async {
      final service = _FakeUpdateCheckService();
      containerWith(
        service: service,
        checkInterval: const Duration(milliseconds: 15),
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(
        service.calls,
        greaterThan(1),
        reason: 'launch check plus at least one periodic tick',
      );
    });

    test('a failed check resolves to a typed error, never a throw', () async {
      final service = _FakeUpdateCheckService(throwFailure: true);
      final container = containerWith(service: service);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(container.read(updateStatusProvider), isA<UpdateStatusError>());
    });

    test('a mandatory update is carried through to the status', () async {
      final service = _FakeUpdateCheckService(result: mandatoryRelease);
      final container = containerWith(service: service);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final status =
          container.read(updateStatusProvider) as UpdateStatusAvailable;
      expect(status.info.mandatory, isTrue);
    });
  });
}
