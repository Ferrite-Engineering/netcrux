// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:crux_settings/crux_settings.dart';
import 'package:crux_updates/crux_updates.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/updates/netcrux_update_config.dart';
import 'package:netcrux/domain/models/app_settings.dart';
import 'package:netcrux/features/settings/providers/app_settings_provider.dart';
import 'package:netcrux/features/update/netcrux_update_overrides.dart';
import 'package:netcrux/features/update/providers/observed_server_time_provider.dart';
import 'package:netcrux/services/settings/netcrux_settings_codec.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A licence tier a test can change mid-session, the way entering a key does.
class _MutableTier extends Notifier<LicenseTier> {
  @override
  LicenseTier build() => LicenseTier.openCore;

  LicenseTier get value => state;

  set value(LicenseTier tier) => state = tier;
}

final _mutableTierProvider = NotifierProvider<_MutableTier, LicenseTier>(
  _MutableTier.new,
);

/// NetCrux's binding of `crux_updates`: the configuration values themselves,
/// and the root overrides that make the package's seams resolve to real
/// NetCrux state — build info, the persisted auto-check setting, the URL
/// launcher, the observed-server-time loop feeding `crux_license`, and the
/// seat's edition.
void main() {
  Future<ProviderContainer> containerWith({
    bool autoCheckForUpdates = true,
    List<Override> extra = const [],
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final service = SettingsService<AppSettings>(
      const NetcruxSettingsCodec(),
      prefsOverride: prefs,
    );
    await service.save(
      const AppSettings.defaults().copyWith(
        autoCheckForUpdates: autoCheckForUpdates,
      ),
    );
    final container = ProviderContainer(
      overrides: <Override>[
        ...netcruxUpdateOverrides,
        settingsServiceProvider.overrideWithValue(service),
        ...extra,
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('netcruxUpdateConfig', () {
    test('names NetCrux and points at the public manifest', () {
      expect(netcruxUpdateConfig.productName, 'NetCrux');
      expect(
        netcruxUpdateConfig.manifestUri.toString(),
        'https://updates.netcrux.app/manifest.json',
      );
      expect(
        netcruxUpdateConfig.downloadPageUri.toString(),
        netcruxDownloadPageUrl,
      );
    });

    test('declares no mobile targets and no mobile check', () {
      // NetCrux ships desktop + a read-only web viewer; there is no iOS or
      // Android build, so there is no store listing to deep-link to and no
      // reason to fetch the manifest on a mobile host.
      expect(netcruxUpdateConfig.appStoreUri, isNull);
      expect(netcruxUpdateConfig.playStoreUri, isNull);
      expect(netcruxUpdateConfig.checkOnMobile, isFalse);
    });

    test('every desktop platform resolves to the download page', () {
      for (final platform in [
        TargetPlatform.macOS,
        TargetPlatform.linux,
        TargetPlatform.windows,
      ]) {
        expect(
          netcruxUpdateConfig.updateTargetFor(platform).toString(),
          netcruxDownloadPageUrl,
          reason: '$platform must deep-link to the download page',
        );
      }
      expect(
        netcruxUpdateConfig
            .updateTargetFor(TargetPlatform.macOS, isWeb: true)
            .toString(),
        netcruxDownloadPageUrl,
      );
    });
  });

  group('netcruxUpdateOverrides', () {
    test('binds the config the package would otherwise throw for', () async {
      final container = await containerWith();
      expect(container.read(cruxUpdateConfigProvider), netcruxUpdateConfig);
    });

    test('binds a working URL launcher', () async {
      final container = await containerWith();
      // The package default throws on invocation; only the identity matters
      // here — actually launching would need a platform channel.
      expect(container.read(updateUrlLauncherProvider), isNotNull);
    });

    test('auto-check honours the persisted setting — enabled', () async {
      final container = await containerWith();
      expect(
        await container.read(autoUpdateCheckEnabledProvider.future),
        isTrue,
      );
    });

    test('auto-check honours the persisted setting — disabled', () async {
      final container = await containerWith(autoCheckForUpdates: false);
      expect(
        await container.read(autoUpdateCheckEnabledProvider.future),
        isFalse,
      );
    });

    test('the server-time sink advances the persisted store', () async {
      final container = await containerWith();
      final observed = DateTime.utc(2026, 9, 15, 12);

      container.read(observedServerTimeSinkProvider)(observed);
      // The sink is fire-and-forget; let the persist path settle.
      await Future<void>.delayed(Duration.zero);

      expect(container.read(observedServerTimeStoreProvider), observed);
    });

    test(
      "crux_license's observedServerTimeProvider mirrors the store",
      () async {
        final container = await containerWith();
        expect(container.read(observedServerTimeProvider), isNull);

        final observed = DateTime.utc(2026, 9, 15, 12);
        await container
            .read(observedServerTimeStoreProvider.notifier)
            .record(observed);

        // This is the loop that makes a clock rollback unable to defer expiry:
        // the manifest's server_time lands in the store, and the store is what
        // `trustedBetaExpiryNow` compares the device clock against.
        expect(container.read(observedServerTimeProvider), observed);
      },
    );
  });

  group('updateEditionProvider binding', () {
    // Decides whether a release that changed only paid features is offered
    // (the manifest's `open_core_version`). Left unbound, the package default
    // offers every release to every seat — silently.
    ProviderContainer seat(LicenseTier tier, {bool betaPeriod = false}) {
      final container = ProviderContainer(
        overrides: <Override>[
          ...netcruxUpdateOverrides,
          betaPeriodProvider.overrideWithValue(betaPeriod),
          licenseTierProvider.overrideWithValue(tier),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('a seat without a licence is an open-core seat', () {
      expect(
        seat(LicenseTier.openCore).read(updateEditionProvider),
        UpdateEdition.openCore,
      );
    });

    test('every paid tier unlocks', () {
      for (final tier in [
        LicenseTier.edu,
        LicenseTier.pro,
        LicenseTier.enterprise,
      ]) {
        expect(
          seat(tier).read(updateEditionProvider),
          UpdateEdition.unlocked,
          reason: '$tier',
        );
      }
    });

    test('a beta period unlocks every seat, as it opens every gate', () {
      expect(
        seat(
          LicenseTier.openCore,
          betaPeriod: true,
        ).read(updateEditionProvider),
        UpdateEdition.unlocked,
      );
    });

    test('follows a licence entered mid-session', () {
      final container = ProviderContainer(
        overrides: <Override>[
          ...netcruxUpdateOverrides,
          betaPeriodProvider.overrideWithValue(false),
          licenseTierProvider.overrideWith(
            (ref) => ref.watch(_mutableTierProvider),
          ),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(updateEditionProvider), UpdateEdition.openCore);

      container.read(_mutableTierProvider.notifier).value = LicenseTier.pro;

      expect(container.read(updateEditionProvider), UpdateEdition.unlocked);
    });
  });
}
