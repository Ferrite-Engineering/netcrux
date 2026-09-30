// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_telemetry/crux_telemetry.dart' show kTelemetryFormFactors;
import 'package:flutter/foundation.dart' show TargetPlatform;

/// Maps the layout idiom the app **already** uses onto the coarse
/// `form_factor` bucket (`crux_telemetry`'s [kTelemetryFormFactors]).
///
/// This is the one half of the telemetry envelope `crux_telemetry` refuses to
/// derive for a product, and deliberately: a second breakpoint set inside the
/// shared package is exactly how telemetry would come to disagree with what
/// the user is actually looking at.
///
/// NetCrux's layout idiom is **not** a width breakpoint. Where WaveCrux has a
/// `DeviceClass` computed from the window size, NetCrux is desktop-first and
/// classifies on the host alone: `isDesktopPlatform` (`lib/core/platform_utils.dart`)
/// is the single bit every adaptive surface reads — `openAdaptive` picks a
/// modal dialog over a pushed route with it, `DesktopMenuBar` mounts on it, and
/// the keyboard-shortcut editor suppresses its phone note because of it. This
/// function is that same predicate, projected onto the Worker's vocabulary, so
/// the reported bucket is always the chrome NetCrux drew.
///
/// The [TargetPlatform.iOS] / [TargetPlatform.android] branch reports `phone`
/// rather than `tablet` because NetCrux has no phone/tablet split to consult:
/// it has one non-desktop layout, and inventing a breakpoint here to
/// distinguish an iPad is precisely what `telemetryFormFactorProvider` exists
/// to prevent. That branch is also unreachable in every shipped build — the
/// repo has `linux/`, `macos/`, `web/` and `windows/` runners and no mobile
/// ones — so it is a total-function obligation, not a measurement. Should
/// NetCrux ever ship a mobile target, it needs a real layout idiom **first**
/// and this mapping second.
///
/// [TargetPlatform.fuchsia] joins the desktop bucket, matching
/// `telemetryOsSlugFor`'s fuchsia → `linux` fallback and how the suite treats
/// it everywhere else.
///
/// `kIsWeb` wins outright: a browser tab is a browser tab whatever its width,
/// and `web` vs `desktop` is the split the roadmap question ("does the web
/// build earn its maintenance") actually needs. No dimensions are sent, and
/// none are derivable from the four buckets.
String telemetryFormFactorFor({
  required bool isWeb,
  required TargetPlatform platform,
}) {
  if (isWeb) return 'web';
  return switch (platform) {
    TargetPlatform.linux ||
    TargetPlatform.macOS ||
    TargetPlatform.windows ||
    TargetPlatform.fuchsia => 'desktop',
    TargetPlatform.iOS || TargetPlatform.android => 'phone',
  };
}
