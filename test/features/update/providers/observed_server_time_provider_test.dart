// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/features/update/providers/observed_server_time_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The persisted server-time watermark that hardens beta expiry against a
/// device-clock rollback. The store must be **monotonic** — a stale cached
/// manifest or a server blip must never move the trusted clock backward — and
/// must survive a relaunch so an offline start still benefits from the last
/// server time the app ever saw.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  ProviderContainer makeContainer() {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    return container;
  }

  group('ObservedServerTimeStore', () {
    test('starts empty when nothing was ever persisted', () async {
      final container = makeContainer();
      expect(container.read(observedServerTimeStoreProvider), isNull);
      // Let the async load settle; still nothing to load.
      await Future<void>.delayed(Duration.zero);
      expect(container.read(observedServerTimeStoreProvider), isNull);
    });

    test('records the first observation', () async {
      final container = makeContainer();
      final observed = DateTime.utc(2026, 9, 15, 12);
      await container
          .read(observedServerTimeStoreProvider.notifier)
          .record(observed);
      expect(container.read(observedServerTimeStoreProvider), observed);
    });

    test('advances only forward', () async {
      final container = makeContainer();
      final notifier = container.read(observedServerTimeStoreProvider.notifier);
      final later = DateTime.utc(2026, 9, 15, 12);
      final earlier = DateTime.utc(2026, 1, 2);

      await notifier.record(later);
      await notifier.record(earlier);
      expect(
        container.read(observedServerTimeStoreProvider),
        later,
        reason: 'an earlier observation must not roll the watermark back',
      );

      final latest = DateTime.utc(2027, 3, 4);
      await notifier.record(latest);
      expect(container.read(observedServerTimeStoreProvider), latest);
    });

    test('an equal observation is not re-persisted', () async {
      final container = makeContainer();
      final notifier = container.read(observedServerTimeStoreProvider.notifier);
      final observed = DateTime.utc(2026, 9, 15, 12);
      await notifier.record(observed);
      await notifier.record(observed);
      expect(container.read(observedServerTimeStoreProvider), observed);
    });

    test('persists to SharedPreferences as ISO-8601', () async {
      final container = makeContainer();
      final observed = DateTime.utc(2026, 9, 15, 12);
      await container
          .read(observedServerTimeStoreProvider.notifier)
          .record(observed);

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(ObservedServerTimeStore.prefsKey),
        observed.toIso8601String(),
      );
    });

    test('reloads the persisted watermark on a fresh launch', () async {
      final observed = DateTime.utc(2026, 9, 15, 12);
      SharedPreferences.setMockInitialValues(<String, Object>{
        ObservedServerTimeStore.prefsKey: observed.toIso8601String(),
      });

      final container = makeContainer();
      // `build` returns null synchronously and kicks off the load.
      expect(container.read(observedServerTimeStoreProvider), isNull);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(observedServerTimeStoreProvider), observed);
    });

    test('a corrupt persisted value is ignored, not fatal', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        ObservedServerTimeStore.prefsKey: 'not-a-timestamp',
      });

      final container = makeContainer();
      await Future<void>.delayed(Duration.zero);
      expect(container.read(observedServerTimeStoreProvider), isNull);
    });
  });
}
