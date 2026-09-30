// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/shortcuts/netcrux_action.dart';
import 'package:netcrux/core/shortcuts/netcrux_action_context.dart';
import 'package:netcrux/features/command_palette/widgets/command_palette_dialog.dart';
import 'package:netcrux/features/workspace/providers/netcrux_action_context_provider.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/shared/widgets/netcrux_feature_tier_badge.dart';

Widget _harness({Locale locale = const Locale('en')}) => ProviderScope(
  overrides: [
    // A loaded design + selection so the Pro selection-seeded rows under
    // test are enabled (the palette omits disabled actions).
    netcruxActionContextProvider.overrideWithValue(
      const NetcruxActionContext(
        hasOpenTab: true,
        hasNetlist: true,
        hasSelection: true,
      ),
    ),
  ],
  child: MaterialApp(
    locale: locale,
    localizationsDelegates: L10N.localizationsDelegates,
    supportedLocales: L10N.supportedLocales,
    home: Scaffold(
      body: CommandPaletteDialog(onAction: (_) {}),
    ),
  ),
);

/// Enters [query] into the palette's search field and settles the list.
Future<void> _search(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(TextField), query);
  await tester.pumpAndSettle();
}

void main() {
  group('CommandPaletteDialog tier badges (trailingBuilder)', () {
    testWidgets('a Pro action row renders a NetCruxFeatureTierBadge', (
      tester,
    ) async {
      final l10n = await L10N.delegate.load(const Locale('en'));
      // `showConeOfInfluenceFanin` is Pro (requiredTier == pro) and
      // palette-visible. Its full label isolates exactly that row
      // (fanout diverges at "(Fanin)"/"(Fanout)").
      final proLabel = NetcruxAction.showConeOfInfluenceFanin.label(l10n);
      expect(proLabel, 'Show Cone of Influence (Fanin)');

      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();
      await _search(tester, proLabel);

      expect(find.byType(NetCruxFeatureTierBadge), findsOneWidget);
    });

    testWidgets('a free (open-core) action row renders no badge', (
      tester,
    ) async {
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();
      // `openProject` is open-core; trailingBuilder returns null so no
      // NetCruxFeatureTierBadge is created for its row.
      await _search(tester, 'Open Project');

      // The row is present (its label + the search field both match the
      // substring) but it carries no tier badge.
      expect(find.textContaining('Open Project'), findsNWidgets(2));
      expect(find.byType(NetCruxFeatureTierBadge), findsNothing);
    });

    testWidgets('the Pro badge renders in every supported locale', (
      tester,
    ) async {
      for (final locale in L10N.supportedLocales) {
        final l10n = await L10N.delegate.load(locale);
        final proLabel = NetcruxAction.showConeOfInfluenceFanin.label(l10n);

        await tester.pumpWidget(_harness(locale: locale));
        await tester.pumpAndSettle();
        await _search(tester, proLabel);

        expect(
          find.byType(NetCruxFeatureTierBadge),
          findsAtLeastNWidgets(1),
          reason: 'Pro action must show a tier badge in $locale',
        );
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
    });
  });
}
