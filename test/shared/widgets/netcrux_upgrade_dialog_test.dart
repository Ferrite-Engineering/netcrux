// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_license/crux_license.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/shared/widgets/netcrux_upgrade_dialog.dart';

Widget _host({Locale locale = const Locale('en')}) => MaterialApp(
  locale: locale,
  localizationsDelegates: L10N.localizationsDelegates,
  supportedLocales: L10N.supportedLocales,
  home: const Scaffold(body: _Opener()),
);

class _Opener extends StatelessWidget {
  const _Opener();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ElevatedButton(
        onPressed: () => NetcruxUpgradeDialog.show(
          context,
          featureLabel: 'Run CDC Analysis',
          requiredTier: LicenseTier.pro,
        ),
        child: const Text('open'),
      ),
    );
  }
}

void main() {
  testWidgets('renders title, tier badge, feature label, and dismisses', (
    tester,
  ) async {
    await tester.pumpWidget(_host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final l10n = L10N.of(tester.element(find.byType(CruxUpgradeDialog)));
    expect(find.text(l10n.upgradeDialogTitle), findsOneWidget);
    expect(find.byType(FeatureTierBadge), findsOneWidget);
    expect(
      find.text(
        l10n.upgradeDialogMessage(
          'Run CDC Analysis',
          l10n.upgradeDialogTierNamePro,
        ),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text(l10n.commonOk));
    await tester.pumpAndSettle();
    expect(find.byType(CruxUpgradeDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('enterprise tier renders the enterprise product name', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: Scaffold(
          body: NetcruxUpgradeDialog(
            featureLabel: 'Feature',
            requiredTier: LicenseTier.enterprise,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final l10n = L10N.of(tester.element(find.byType(NetcruxUpgradeDialog)));
    expect(
      find.textContaining(l10n.upgradeDialogTierNameEnterprise),
      findsOneWidget,
    );
  });

  testWidgets('a repeated denial while the dialog is up stacks nothing', (
    tester,
  ) async {
    // Key auto-repeat on a gated shortcut re-dispatches the denial while the
    // dialog is already open. NetCrux adds no guard of its own; this holds
    // because the shared opener, `CruxUpgradeDialog.show`, is guarded.
    await tester.pumpWidget(_host());
    await tester.tap(find.text('open'));
    await tester.pump();
    final context = tester.element(find.byType(_Opener));
    for (var i = 0; i < 3; i++) {
      unawaited(
        NetcruxUpgradeDialog.show(
          context,
          featureLabel: 'Run CDC Analysis',
          requiredTier: LicenseTier.pro,
        ),
      );
    }
    await tester.pumpAndSettle();

    expect(find.byType(CruxUpgradeDialog), findsOneWidget);
  });

  group('locale sweep', () {
    for (final locale in const [
      Locale('en'),
      Locale('zh', 'CN'),
      Locale('ja'),
      Locale('ko'),
    ]) {
      testWidgets('renders in $locale without exceptions', (tester) async {
        await tester.pumpWidget(_host(locale: locale));
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(find.byType(CruxUpgradeDialog), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
