// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async' show unawaited;
import 'dart:io' show exit;

import 'package:crux_license/crux_license.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/core/updates/netcrux_update_config.dart';
import 'package:netcrux/features/beta_expiry/widgets/beta_expiry_blocking_overlay.dart';
import 'package:netcrux/features/beta_expiry/widgets/netcrux_beta_expiry_strings.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

/// Seam for opening the "download the latest build" page, overridable in tests
/// so the banner / modal actions can be exercised without the `url_launcher`
/// platform channel.
Future<bool> Function(Uri uri) betaExpiryLaunchUrl = launchUrl;

/// Seam for terminating the process from the expired modal's quit action,
/// overridable in tests (calling the real `exit` would kill the test runner).
///
/// Defaults to the same immediate `exit(0)` the menu-bar quit action uses. The
/// expired modal only ever renders on a native desktop beta build — the web
/// viewer ships no `BETA_EXPIRY` — so the `dart:io`-on-web caveat never fires.
void Function() betaExpiryExitApp = () => exit(0);

/// Startup / resume gate enforcing the per-release hard beta build expiry.
///
/// Wraps the routed app content ([child]) and, based on
/// `crux_license`'s `betaExpiryStatusProvider`:
///
/// - `BetaExpiryStatus.expiringSoon` → a dismissible [CruxBetaExpiryBanner]
///   above [child].
/// - `BetaExpiryStatus.expired` → the blocking, non-dismissable
///   [BetaExpiryBlockingOverlay] over [child].
/// - `BetaExpiryStatus.active` / `BetaExpiryStatus.notApplicable` → [child]
///   unchanged. That is every developer build and every post-beta build:
///   expiry applies only while `kBetaPeriod` is on and only when a release
///   injected `--dart-define=BETA_EXPIRY=<yyyymmdd>`.
///
/// The status is read at startup (first build) and re-evaluated on app resume:
/// [didChangeAppLifecycleState] invalidates the expiry providers so they
/// re-read the clock, and clears the session dismissal so a warning the user
/// dismissed earlier re-surfaces when they return. The check never runs
/// mid-session — only on the resume lifecycle edge — so an in-progress
/// elaboration or layout is never interrupted.
///
/// The clock those providers read is `trustedBetaExpiryNow`, which takes the
/// later of the device clock and the persisted server-time watermark fed by
/// the update-manifest check (`ObservedServerTimeStore`). Winding the device
/// clock back therefore cannot defer expiry below the last server time the
/// app has seen.
///
/// Sits inside `MaterialApp` (so `L10N.of` resolves) but above the routed
/// content, and *outside* the update banner so a blocking expiry modal covers
/// it — see `app.dart`'s `MaterialApp.builder`.
class BetaExpiryGate extends ConsumerStatefulWidget {
  /// Creates the gate wrapping [child].
  const BetaExpiryGate({required this.child, super.key});

  /// The routed app content the gate wraps.
  final Widget child;

  @override
  ConsumerState<BetaExpiryGate> createState() => _BetaExpiryGateState();
}

class _BetaExpiryGateState extends ConsumerState<BetaExpiryGate>
    with WidgetsBindingObserver {
  /// Whether the user dismissed the "expires soon" banner this session. Reset
  /// on app resume so a returning user is reminded again.
  bool _bannerDismissed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // Re-evaluate expiry against the latest clock reading. The providers
    // capture the instant when first read, so invalidation forces a fresh
    // read — a build still inside its window at launch can cross into
    // expiringSoon / expired while the app was suspended.
    ref
      ..invalidate(betaExpiryStatusProvider)
      ..invalidate(betaExpiryDaysRemainingProvider);
    if (_bannerDismissed && mounted) {
      setState(() => _bannerDismissed = false);
    }
  }

  void _download() {
    unawaited(betaExpiryLaunchUrl(Uri.parse(netcruxDownloadPageUrl)));
  }

  @override
  Widget build(BuildContext context) {
    switch (ref.watch(betaExpiryStatusProvider)) {
      case BetaExpiryStatus.expired:
        return BetaExpiryBlockingOverlay(
          onDownload: _download,
          onQuit: betaExpiryExitApp,
          child: widget.child,
        );
      case BetaExpiryStatus.expiringSoon:
        if (_bannerDismissed) return widget.child;
        return Column(
          children: [
            // Default `CruxBetaExpirySizing` — 20 dp icon, 44 dp touch target —
            // is exactly what NetCrux's own constants encoded before the widget
            // was lifted into `crux_license`. NetCrux is desktop + read-only web
            // only, so it has no device-class metrics to derive a size from.
            CruxBetaExpiryBanner(
              daysRemaining: ref.watch(betaExpiryDaysRemainingProvider) ?? 0,
              onDownload: _download,
              onDismiss: () => setState(() => _bannerDismissed = true),
              strings: NetcruxBetaExpiryStrings(L10N.of(context)),
            ),
            Expanded(child: widget.child),
          ],
        );
      case BetaExpiryStatus.active:
      case BetaExpiryStatus.notApplicable:
        return widget.child;
    }
  }
}
