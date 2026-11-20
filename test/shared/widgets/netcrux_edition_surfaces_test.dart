// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/license/netcrux_edition_line_strings.dart';
import 'package:netcrux/core/providers/status_bar_trailing_widgets_provider.dart';
import 'package:netcrux/features/viewer/widgets/netcrux_status_bar.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/shared/widgets/netcrux_edition_badge.dart';

import '../../helpers/license_status_fixtures.dart';

/// E3 — the edition is visible in the window without opening a dialog.
///
/// The property asserted first is that OPEN CORE CONTRIBUTES NOTHING. It holds
/// twice over and both halves are checked here, because either one alone would
/// be a silent regression: the badge renders `SizedBox.shrink()` at open core,
/// AND open core never mounts it at all (the trailing slot is a Pro override).
void main() {
  Widget harness(
    Widget child, {
    required LicenseTier tier,
    CruxLicenseStatus? status,
  }) => ProviderScope(
    overrides: [
      licenseTierProvider.overrideWithValue(tier),
      if (status != null) licenseStatusProvider.overrideWithValue(status),
    ],
    child: MaterialApp(
      localizationsDelegates: L10N.localizationsDelegates,
      supportedLocales: L10N.supportedLocales,
      home: Scaffold(body: Center(child: child)),
    ),
  );

  group('the status-bar edition badge', () {
    testWidgets('renders nothing at open core', (tester) async {
      await tester.pumpWidget(
        harness(const NetCruxEditionBadge(), tier: LicenseTier.openCore),
      );
      expect(find.text('PRO'), findsNothing);
      expect(find.text('ENT'), findsNothing);
      expect(find.text('EDU'), findsNothing);
    });

    for (final (tier, label) in const <(LicenseTier, String)>[
      (LicenseTier.pro, 'PRO'),
      (LicenseTier.enterprise, 'ENT'),
    ]) {
      testWidgets('renders $label at ${tier.name}', (tester) async {
        await tester.pumpWidget(
          harness(const NetCruxEditionBadge(), tier: tier),
        );
        expect(find.text(label), findsOneWidget);
      });

      testWidgets('still renders $label beside a ${tier.name} licence', (
        tester,
      ) async {
        await tester.pumpWidget(
          harness(
            const NetCruxEditionBadge(),
            tier: tier,
            status: activeLicenseStatus(tier),
          ),
        );
        expect(find.text(label), findsOneWidget);
      });
    }

    testWidgets('renders nothing under an educational licence: the '
        "status bar's educational-licence chip carries the EDU badge", (
      tester,
    ) async {
      await tester.pumpWidget(
        harness(
          const NetCruxEditionBadge(),
          tier: LicenseTier.edu,
          status: activeLicenseStatus(LicenseTier.edu),
        ),
      );
      expect(find.text('EDU'), findsNothing);
      expect(find.byType(EditionBadge), findsNothing);
    });

    testWidgets('one EDU badge in the status bar, not two', (tester) async {
      // The overlay mounts this badge in the extension slot; the bar adds the
      // educational-licence chip after it.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            licenseTierProvider.overrideWithValue(LicenseTier.edu),
            licenseStatusProvider.overrideWithValue(
              activeLicenseStatus(LicenseTier.edu),
            ),
            statusBarTrailingWidgetsProvider.overrideWithValue(
              const [NetCruxEditionBadge()],
            ),
          ],
          child: const MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Scaffold(body: Builder(builder: NetcruxStatusBar.idle)),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('EDU'), findsOneWidget);
      expect(find.byType(CruxEduStatusChip), findsOneWidget);
    });

    testWidgets('does not throw when no licence exists at all', (tester) async {
      // It is mounted in shared chrome during startup; throwing here would take
      // the window with it.
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Scaffold(body: NetCruxEditionBadge()),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('the application-menu edition line', () {
    testWidgets('is null at open core, so no menu item is added', (
      tester,
    ) async {
      late String? line;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Consumer(
              builder: (context, ref, _) {
                line = cruxLicenseEditionLine(
                  ref.watch(licenseStatusProvider),
                  NetCruxEditionLineStrings(L10N.of(context)),
                );
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      expect(line, isNull);
    });

    testWidgets('names the organization when the licence names nobody', (
      tester,
    ) async {
      // The Enterprise-by-policy-file case: no user email exists, and the line
      // must not render an empty string or the word "null".
      late String? line;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            licenseStatusProvider.overrideWithValue(
              const CruxLicenseStatus(
                activation: CruxLicenseActivation.active,
                grant: LicenseGrant(
                  issuerId: 'keygen',
                  tier: LicenseTier.enterprise,
                  products: {CruxProduct.netCrux},
                ),
              ),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Consumer(
              builder: (context, ref, _) {
                line = cruxLicenseEditionLine(
                  ref.watch(licenseStatusProvider),
                  NetCruxEditionLineStrings(L10N.of(context)),
                );
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      expect(line, isNotNull);
      expect(line, isNot(contains('null')));
      expect(line!.trim(), isNotEmpty);
    });
  });
}
