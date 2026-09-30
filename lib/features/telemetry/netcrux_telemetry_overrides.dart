// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:netcrux/core/app_info/about_providers.dart';
import 'package:netcrux/core/telemetry/netcrux_telemetry_config.dart';
import 'package:netcrux/core/telemetry/netcrux_telemetry_storage.dart';
import 'package:netcrux/features/settings/providers/app_settings_provider.dart';
import 'package:netcrux/services/telemetry/telemetry_platform.dart';
import 'package:url_launcher/url_launcher.dart';

/// Root-scope overrides binding the cross-suite `crux_telemetry` package to
/// NetCrux's own configuration, persistence, build metadata, layout idiom,
/// locale, and URL launcher.
///
/// Spread into the root `ProviderContainer` by `bootstrap`, ahead of the
/// Pro overlay's `proOverrides` so the overlay can layer on top
/// under the standard later-wins conflict semantics — that is where the
/// Enterprise `.crux-policy.json` `telemetry: allow | deny` key will bind, as
/// an override of `telemetryConsentPromptVisibleProvider`.
///
/// The localized string bundle is deliberately **not** here: it needs a
/// `BuildContext` to resolve `L10N.of(context)`, so `NetcruxApp` overrides
/// `cruxTelemetryStringsProvider` from inside `MaterialApp.builder` instead —
/// exactly as it does for `cruxUpdateStringsProvider`.
final List<Override> netcruxTelemetryOverrides = <Override>[
  // The one binding with no working default. A product that forgets it throws
  // at wiring rather than reporting somebody else's product slug on every
  // batch — and a wrong slug is rejected by the Worker with a 400 the client
  // never sees.
  cruxTelemetryConfigProvider.overrideWithValue(netcruxTelemetryConfig),

  // Where `telemetry.consent` and `telemetry.installationId` live. The package
  // default is an in-memory store, which would re-prompt the disclosure every
  // launch and re-mint the installation id every session.
  telemetryStorageProvider.overrideWithValue(const NetcruxTelemetryStorage()),

  // "Learn more" on both consent surfaces. The package default throws rather
  // than silently doing nothing when the user taps a link on a privacy notice.
  telemetryUrlLauncherProvider.overrideWithValue(launchUrl),

  // The `app_version` envelope field. Until this resolves the package's
  // envelope resolver returns null and the flush skips — a version we do not
  // have must not be invented, because a bad `app_version` rejects the whole
  // batch at the Worker. Note this takes `ApplicationBuildInfo.version` only:
  // its `os` field is a display string (`macOS 15.0`), which would fail the
  // Worker's `os` enum on every platform, so the slug is derived separately by
  // `telemetryOsSlug()` inside the package.
  telemetryAppVersionProvider.overrideWith(
    (ref) async => (await ref.watch(aboutBuildInfoProvider.future)).version,
  ),

  // The `form_factor` bucket, derived from the layout idiom the app actually
  // drew. This stays in NetCrux on purpose: a second breakpoint set inside
  // `crux_telemetry` is how telemetry would come to disagree with what the
  // user is looking at. NetCrux's idiom is host-based rather than
  // width-based — see `telemetryFormFactorFor`.
  //
  // The seam is `Provider<String?>` so a product whose idiom comes from the
  // widget tree can answer "not yet" and have the flush skip rather than report
  // a pre-layout default — WaveCrux's D2, where a Pixel Tablet in portrait
  // reported `desktop` on three of four launches. **NetCrux must not do that.**
  // `isDesktopPlatform` is a host predicate and `kIsWeb` a compile-time
  // constant: both are knowable before anything is drawn, there is no race to
  // lose, and deferring would cost a flush interval to answer a question that
  // was never open.
  telemetryFormFactorProvider.overrideWith(
    (ref) => telemetryFormFactorFor(
      isWeb: kIsWeb,
      platform: defaultTargetPlatform,
    ),
  ),

  // The display language actually in effect — the field that answers whether
  // the zh/zh_CN/ja/ko localizations earn their maintenance cost. Falls back to
  // the seam default while settings are still loading; a flush that early has
  // nothing queued to send anyway.
  telemetryLocaleProvider.overrideWith(
    (ref) => ref.watch(appSettingsProvider).value?.core.locale ?? 'en',
  ),
];
