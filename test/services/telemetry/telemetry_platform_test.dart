// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/platform_utils.dart';
import 'package:netcrux/features/telemetry/netcrux_telemetry_overrides.dart';
import 'package:netcrux/services/telemetry/telemetry_platform.dart';

// The `os` slug derivation lives in `crux_telemetry` with the rest of the
// pipeline — it needs nothing NetCrux knows. What stays here, and is tested
// here, is the mapping from NetCrux's own layout idiom onto the Worker's
// `form_factor` bucket.
//
// NetCrux's idiom is `isDesktopPlatform`, not a width breakpoint: it is the one
// bit `openAdaptive`, `DesktopMenuBar` and the shortcuts editor all read. The
// first test below is the one that matters — it asserts the two agree, so the
// bucket telemetry reports is by construction the chrome the user saw.

void main() {
  group('telemetryFormFactorFor', () {
    test('agrees with isDesktopPlatform on every host', () {
      // The property that makes this derivation honest. If someone changes
      // `isDesktopPlatform` (adds a host, drops one) without changing this
      // mapping, telemetry starts reporting a form factor the app did not draw.
      for (final platform in TargetPlatform.values) {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        final bucket = telemetryFormFactorFor(
          isWeb: false,
          platform: platform,
        );
        expect(
          bucket == 'desktop',
          isDesktopPlatform || platform == TargetPlatform.fuchsia,
          reason:
              '$platform: form factor "$bucket" disagrees with '
              'isDesktopPlatform ($isDesktopPlatform)',
        );
      }
      debugDefaultTargetPlatformOverride = null;
    });

    test('maps every host NetCrux ships a runner for to desktop', () {
      for (final platform in const [
        TargetPlatform.linux,
        TargetPlatform.macOS,
        TargetPlatform.windows,
      ]) {
        expect(
          telemetryFormFactorFor(isWeb: false, platform: platform),
          'desktop',
        );
      }
    });

    test('fuchsia joins desktop, matching the os slug fallback', () {
      // `telemetryOsSlugFor` reports fuchsia as `linux`; reporting it as a
      // phone here would produce a `linux` + `phone` envelope nobody can read.
      expect(
        telemetryFormFactorFor(
          isWeb: false,
          platform: TargetPlatform.fuchsia,
        ),
        'desktop',
      );
      expect(
        telemetryOsSlugFor(isWeb: false, platform: TargetPlatform.fuchsia),
        'linux',
      );
    });

    test('the mobile hosts report phone, not tablet', () {
      // NetCrux has no phone/tablet split — one non-desktop layout — and
      // inventing a breakpoint here to distinguish an iPad is exactly what the
      // `telemetryFormFactorProvider` seam exists to prevent. Neither branch is
      // reachable in a shipped build: there is no iOS or Android runner.
      for (final platform in const [
        TargetPlatform.iOS,
        TargetPlatform.android,
      ]) {
        expect(
          telemetryFormFactorFor(isWeb: false, platform: platform),
          'phone',
        );
      }
    });

    test('kIsWeb wins for every platform', () {
      for (final platform in TargetPlatform.values) {
        expect(telemetryFormFactorFor(isWeb: true, platform: platform), 'web');
      }
    });

    test('every bucket is one the ingestion Worker accepts', () {
      // A `form_factor` outside `FORM_FACTORS` rejects the WHOLE batch with a
      // 400 the client never sees.
      for (final platform in TargetPlatform.values) {
        for (final isWeb in const [true, false]) {
          expect(
            kTelemetryFormFactors,
            contains(
              telemetryFormFactorFor(isWeb: isWeb, platform: platform),
            ),
          );
        }
      }
    });

    test('no dimension survives the mapping', () {
      // Three reachable buckets over every host, and none of them carries a
      // pixel count — nothing downstream can reconstruct a window size.
      final buckets = <String>{
        for (final platform in TargetPlatform.values) ...<String>{
          telemetryFormFactorFor(isWeb: false, platform: platform),
          telemetryFormFactorFor(isWeb: true, platform: platform),
        },
      };
      expect(buckets, <String>{'desktop', 'phone', 'web'});
    });

    test('it never defers — NetCrux has no first-layout race to lose', () {
      // `telemetryFormFactorProvider` became `Provider<String?>` so a product
      // whose idiom comes from the widget tree can answer "not yet" and have
      // the flush skip rather than report a pre-layout default (WaveCrux's D2).
      // NetCrux is not such a product: `isDesktopPlatform` is a host predicate
      // and `kIsWeb` a compile-time constant, both knowable before anything is
      // drawn. Deferring here would cost a flush interval to answer a question
      // that was never open.
      for (final platform in TargetPlatform.values) {
        for (final isWeb in const [true, false]) {
          expect(
            telemetryFormFactorFor(isWeb: isWeb, platform: platform),
            isNotNull,
          );
        }
      }
    });
  });

  group('the wired seam', () {
    test('resolves to a real bucket with no widget tree at all', () {
      // The end-to-end statement of the test above, through the override the
      // app actually installs: a bare container, nothing mounted, and the
      // envelope can still be assembled. This is the launch-flush situation.
      final container = ProviderContainer(
        overrides: netcruxTelemetryOverrides,
      );
      addTearDown(container.dispose);

      final bucket = container.read(telemetryFormFactorProvider);
      expect(bucket, isNotNull);
      expect(kTelemetryFormFactors, contains(bucket));
    });
  });
}
