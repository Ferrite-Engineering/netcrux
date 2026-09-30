// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/updates/netcrux_update_config.dart';
import 'package:netcrux/features/beta_expiry/widgets/beta_expiry_blocking_overlay.dart';
import 'package:netcrux/features/beta_expiry/widgets/beta_expiry_gate.dart';
import 'package:netcrux/features/beta_expiry/widgets/netcrux_beta_expiry_strings.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

/// The suite accessibility floor, read from the shared sizing rather than
/// re-declared — NetCrux takes `CruxBetaExpirySizing`'s desktop defaults, which
/// is exactly what its own `kBetaExpiryTouchTarget` said before the banner was
/// lifted into `crux_license`.
final double kTouchTargetFloor = const CruxBetaExpirySizing().touchTarget;

/// The per-release hard build-expiry gate.
///
/// Three behaviours are contract-bearing: the status → UI mapping, the fact
/// that an expired build cannot be dismissed past, and the clock-tampering
/// hardening — winding the device clock backwards must not defer expiry below
/// the server-time watermark the update check observed.
void main() {
  const childKey = Key('routedContent');

  Widget buildGate({
    required BetaExpiryStatus status,
    int? daysRemaining,
    String locale = 'en',
  }) => ProviderScope(
    overrides: <Override>[
      betaExpiryStatusProvider.overrideWithValue(status),
      betaExpiryDaysRemainingProvider.overrideWithValue(daysRemaining),
    ],
    child: MaterialApp(
      locale: Locale(locale),
      localizationsDelegates: L10N.localizationsDelegates,
      supportedLocales: L10N.supportedLocales,
      home: const Scaffold(
        body: BetaExpiryGate(
          child: ColoredBox(key: childKey, color: Colors.transparent),
        ),
      ),
    ),
  );

  late List<Uri> launched;
  late int quitCalls;

  setUp(() {
    launched = <Uri>[];
    quitCalls = 0;
    betaExpiryLaunchUrl = (uri) async {
      launched.add(uri);
      return true;
    };
    betaExpiryExitApp = () => quitCalls++;
  });

  group('status mapping', () {
    testWidgets('notApplicable renders the child untouched', (tester) async {
      await tester.pumpWidget(
        buildGate(status: BetaExpiryStatus.notApplicable),
      );
      expect(find.byKey(childKey), findsOneWidget);
      expect(find.byType(CruxBetaExpiryBanner), findsNothing);
      expect(find.byType(BetaExpiryBlockingOverlay), findsNothing);
    });

    testWidgets('active renders the child untouched', (tester) async {
      await tester.pumpWidget(buildGate(status: BetaExpiryStatus.active));
      expect(find.byKey(childKey), findsOneWidget);
      expect(find.byType(CruxBetaExpiryBanner), findsNothing);
    });

    testWidgets('expiringSoon shows the dismissible banner', (tester) async {
      await tester.pumpWidget(
        buildGate(status: BetaExpiryStatus.expiringSoon, daysRemaining: 3),
      );
      expect(find.byType(CruxBetaExpiryBanner), findsOneWidget);
      expect(find.byKey(childKey), findsOneWidget);
      expect(find.textContaining('3'), findsOneWidget);
    });

    testWidgets('expired shows the blocking modal over the child', (
      tester,
    ) async {
      await tester.pumpWidget(buildGate(status: BetaExpiryStatus.expired));
      expect(find.byType(BetaExpiryBlockingOverlay), findsOneWidget);
      // The content is still mounted behind the barrier — the modal blocks
      // input, it does not tear down the app.
      expect(find.byKey(childKey), findsOneWidget);
      expect(find.byType(ModalBarrier), findsWidgets);
    });
  });

  group('banner interaction', () {
    testWidgets('dismissing hides the strip for the session', (tester) async {
      await tester.pumpWidget(
        buildGate(status: BetaExpiryStatus.expiringSoon, daysRemaining: 2),
      );
      await tester.tap(find.byKey(CruxBetaExpiryBanner.dismissButtonKey));
      await tester.pump();

      expect(find.byType(CruxBetaExpiryBanner), findsNothing);
      expect(find.byKey(childKey), findsOneWidget);
    });

    testWidgets('the download action opens the download page', (tester) async {
      await tester.pumpWidget(
        buildGate(status: BetaExpiryStatus.expiringSoon, daysRemaining: 2),
      );
      await tester.tap(find.byKey(CruxBetaExpiryBanner.downloadButtonKey));
      await tester.pump();

      expect(launched, [Uri.parse(netcruxDownloadPageUrl)]);
    });

    testWidgets('the strip speaks NetCrux l10n, not the English default', (
      tester,
    ) async {
      // The shared widget defaults to `CruxBetaExpiryStringsEn`; the gate must
      // pass NetCrux's adapter, or every locale silently renders English.
      await tester.pumpWidget(
        buildGate(
          status: BetaExpiryStatus.expiringSoon,
          daysRemaining: 4,
          locale: 'ja',
        ),
      );
      final banner = tester.widget<CruxBetaExpiryBanner>(
        find.byType(CruxBetaExpiryBanner),
      );
      expect(banner.strings, isA<NetcruxBetaExpiryStrings>());

      // And the dismiss button's accessible name comes from that adapter. It
      // is carried by an enclosing Semantics rather than a Tooltip, because
      // the strip renders above the Navigator where no Overlay ancestor
      // exists — so read the wrapper, not the button's own (empty) node.
      final context = tester.element(find.byType(CruxBetaExpiryBanner));
      final wrapper = tester.widget<Semantics>(
        find
            .ancestor(
              of: find.byKey(CruxBetaExpiryBanner.dismissButtonKey),
              matching: find.byType(Semantics),
            )
            .first,
      );
      expect(
        wrapper.properties.label,
        L10N.of(context).betaExpiryDismissLabel,
      );
    });
  });

  group('expired modal', () {
    testWidgets('offers no dismiss affordance', (tester) async {
      await tester.pumpWidget(buildGate(status: BetaExpiryStatus.expired));
      // The only two ways out are Download and Quit; nothing closes the modal
      // and leaves the app usable.
      expect(find.byKey(CruxBetaExpiryBanner.dismissButtonKey), findsNothing);
      expect(
        find.byKey(BetaExpiryBlockingOverlay.downloadButtonKey),
        findsOneWidget,
      );
      expect(
        find.byKey(BetaExpiryBlockingOverlay.quitButtonKey),
        findsOneWidget,
      );
    });

    testWidgets('blocks the system back gesture', (tester) async {
      await tester.pumpWidget(buildGate(status: BetaExpiryStatus.expired));
      final popScope = tester.widget<PopScope<dynamic>>(
        find.descendant(
          of: find.byType(BetaExpiryBlockingOverlay),
          matching: find.byWidgetPredicate((w) => w is PopScope),
        ),
      );
      expect(popScope.canPop, isFalse);
    });

    testWidgets('download and quit are both wired', (tester) async {
      await tester.pumpWidget(buildGate(status: BetaExpiryStatus.expired));

      await tester.tap(find.byKey(BetaExpiryBlockingOverlay.downloadButtonKey));
      await tester.pump();
      expect(launched, [Uri.parse(netcruxDownloadPageUrl)]);

      await tester.tap(find.byKey(BetaExpiryBlockingOverlay.quitButtonKey));
      await tester.pump();
      // The quit action is load-bearing on Windows/Linux, where the in-app
      // close caption button sits behind the modal barrier.
      expect(quitCalls, 1);
    });
  });

  group('touch targets', () {
    testWidgets('every banner control clears 44 dp', (tester) async {
      await tester.pumpWidget(
        buildGate(status: BetaExpiryStatus.expiringSoon, daysRemaining: 5),
      );
      for (final key in [
        CruxBetaExpiryBanner.downloadButtonKey,
        CruxBetaExpiryBanner.dismissButtonKey,
      ]) {
        final size = tester.getSize(find.byKey(key));
        expect(size.height, greaterThanOrEqualTo(kTouchTargetFloor));
        expect(size.width, greaterThanOrEqualTo(kTouchTargetFloor));
      }
    });

    testWidgets('every expired-modal control clears 44 dp', (tester) async {
      await tester.pumpWidget(buildGate(status: BetaExpiryStatus.expired));
      for (final key in [
        BetaExpiryBlockingOverlay.downloadButtonKey,
        BetaExpiryBlockingOverlay.quitButtonKey,
      ]) {
        expect(
          tester.getSize(find.byKey(key)).height,
          greaterThanOrEqualTo(kTouchTargetFloor),
        );
      }
    });
  });

  group('locale sweep', () {
    for (final locale in ['en', 'zh_CN', 'ja', 'ko']) {
      testWidgets('banner renders in $locale', (tester) async {
        await tester.pumpWidget(
          buildGate(
            status: BetaExpiryStatus.expiringSoon,
            daysRemaining: 1,
            locale: locale,
          ),
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('expired modal renders in $locale', (tester) async {
        await tester.pumpWidget(
          buildGate(status: BetaExpiryStatus.expired, locale: locale),
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('clock-tampering hardening', () {
    // `trustedBetaExpiryNow` takes the LATER of the device clock and the
    // server-time watermark the update check persisted, so winding the device
    // clock back cannot defer expiry below what the app has already seen.
    final expiry = DateTime(2026, 9);

    test('a rolled-back device clock does not revive an expired build', () {
      final serverTime = DateTime(2026, 9, 20);
      final rolledBack = DateTime(2025, 2, 3);

      expect(
        betaExpiryStatusFor(rolledBack, expiry: expiry),
        BetaExpiryStatus.active,
        reason: 'the device clock alone would say the build is fine',
      );
      expect(
        betaExpiryStatusFor(
          trustedBetaExpiryNow(rolledBack, observedServerTime: serverTime),
          expiry: expiry,
        ),
        BetaExpiryStatus.expired,
      );
    });

    test('a rolled-back clock cannot escape the warning window', () {
      final serverTime = DateTime(2026, 8, 28);
      final rolledBack = DateTime(2025, 2, 3);

      expect(
        betaExpiryStatusFor(
          trustedBetaExpiryNow(rolledBack, observedServerTime: serverTime),
          expiry: expiry,
          warningDays: 7,
        ),
        BetaExpiryStatus.expiringSoon,
      );
    });

    test('a device clock ahead of the watermark still wins', () {
      // The mechanism retires stale builds; it does not try to resist a user
      // who moves their clock forward.
      final serverTime = DateTime(2026, 8);
      final ahead = DateTime(2026, 9, 20);
      expect(
        trustedBetaExpiryNow(ahead, observedServerTime: serverTime),
        ahead,
      );
      expect(
        betaExpiryStatusFor(
          trustedBetaExpiryNow(ahead, observedServerTime: serverTime),
          expiry: expiry,
        ),
        BetaExpiryStatus.expired,
      );
    });

    test('no observed server time falls back to the device clock', () {
      // A fresh or permanently-offline install has never reached the manifest
      // endpoint; the pre-hardening behaviour must be preserved rather than
      // failing closed.
      final deviceNow = DateTime(2026, 5);
      expect(trustedBetaExpiryNow(deviceNow), deviceNow);
      expect(
        betaExpiryStatusFor(
          trustedBetaExpiryNow(deviceNow),
          expiry: expiry,
        ),
        BetaExpiryStatus.active,
      );
    });

    test('a build with no injected expiry never expires', () {
      // Every developer build, and every post-beta production build.
      expect(
        betaExpiryStatusFor(DateTime(2099), expiry: parseBetaExpiryDate(0)),
        BetaExpiryStatus.notApplicable,
      );
    });
  });
}
