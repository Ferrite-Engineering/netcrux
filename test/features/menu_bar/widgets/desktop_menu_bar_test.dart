// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:crux_window_chrome/crux_window_chrome.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/shortcuts/action_tier_label.dart';
import 'package:netcrux/core/shortcuts/netcrux_action.dart';
import 'package:netcrux/core/shortcuts/netcrux_action_context.dart';
import 'package:netcrux/features/menu_bar/widgets/desktop_menu_bar.dart';
import 'package:netcrux/features/workspace/providers/netcrux_action_context_provider.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

/// Flattens a [PlatformMenuBar]'s menu tree into its leaf items (walking
/// through [PlatformMenu] submenus and [PlatformMenuItemGroup] dividers).
List<PlatformMenuItem> _leafItems(PlatformMenuBar bar) {
  final result = <PlatformMenuItem>[];
  void visit(PlatformMenuItem item) {
    if (item is PlatformMenu) {
      item.menus.forEach(visit);
    } else if (item is PlatformMenuItemGroup) {
      item.members.forEach(visit);
    } else {
      result.add(item);
    }
  }

  bar.menus.forEach(visit);
  return result;
}

Widget _harness({
  Locale locale = const Locale('en'),
  TargetPlatform platform = TargetPlatform.macOS,
}) => ProviderScope(
  overrides: [
    // A fixed context keeps the label assertions deterministic (menu
    // presence is context-independent for these actions; the enablement
    // contract is covered by the surface conformance test).
    netcruxActionContextProvider.overrideWithValue(
      const NetcruxActionContext(hasOpenTab: true, hasNetlist: true),
    ),
  ],
  child: MaterialApp(
    locale: locale,
    theme: ThemeData(platform: platform),
    localizationsDelegates: L10N.localizationsDelegates,
    supportedLocales: L10N.supportedLocales,
    home: DesktopMenuBar(
      onAction: (_) {},
      child: const SizedBox.shrink(),
    ),
  ),
);

Set<String> _leafLabels(WidgetTester tester) {
  final bar = tester.widget<PlatformMenuBar>(find.byType(PlatformMenuBar));
  return _leafItems(bar).map((e) => e.label).toSet();
}

/// The Windows/Linux in-window renderer builds a [MnemonicMenuBar]; its menu
/// item labels live on the `MenuItemButton` children of each entry (the menu
/// dropdowns aren't mounted until opened, so we read the widget objects
/// directly rather than the rendered tree).
Set<String> _mnemonicLabels(WidgetTester tester) {
  final bar = tester.widget<MnemonicMenuBar>(find.byType(MnemonicMenuBar));
  final labels = <String>{};
  for (final entry in bar.entries) {
    for (final child in entry.menuChildren) {
      if (child is MenuItemButton && child.child is Text) {
        final text = (child.child! as Text).data;
        if (text != null) labels.add(text);
      }
    }
  }
  return labels;
}

void main() {
  group('DesktopMenuBar tier suffix', () {
    testWidgets('a Pro action label carries the tier suffix; a free action '
        'does not', (tester) async {
      final l10n = await L10N.delegate.load(const Locale('en'));
      await tester.pumpWidget(_harness());
      await tester.pump();

      final labels = _leafLabels(tester);

      // Pro action: "Show Cone of Influence (Fanin) (PRO)".
      final proBase = NetcruxAction.showConeOfInfluenceFanin.label(l10n);
      final proSuffix = tierLabelSuffix(LicenseTier.pro, l10n);
      expect(proSuffix, ' (PRO)');
      expect(labels, contains('$proBase$proSuffix'));
      // The un-suffixed Pro label must NOT appear on its own.
      expect(labels, isNot(contains(proBase)));

      // Free action: "Open Project…" with no suffix.
      final freeBase = NetcruxAction.openProject.label(l10n);
      expect(labels, contains(freeBase));
      expect(labels, isNot(contains('$freeBase (PRO)')));
    });

    testWidgets('renders on Windows / Linux as an in-window MnemonicMenuBar '
        '(no native PlatformMenuBar), with the tier suffix', (
      tester,
    ) async {
      for (final platform in <TargetPlatform>[
        TargetPlatform.windows,
        TargetPlatform.linux,
      ]) {
        final l10n = await L10N.delegate.load(const Locale('en'));
        await tester.pumpWidget(_harness(platform: platform));
        await tester.pump();
        // Windows/Linux draw the VS Code-style in-window menu bar, not the
        // native (invisible-on-Linux) PlatformMenuBar.
        expect(
          find.byType(PlatformMenuBar),
          findsNothing,
          reason: 'no native menu bar on $platform',
        );
        expect(
          find.byType(MnemonicMenuBar),
          findsOneWidget,
          reason: 'in-window menu bar on $platform',
        );
        final labels = _mnemonicLabels(tester);
        final proBase = NetcruxAction.showConeOfInfluenceFanin.label(l10n);
        expect(
          labels,
          contains('$proBase${tierLabelSuffix(LicenseTier.pro, l10n)}'),
          reason: 'Pro suffix must render on $platform',
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    });

    testWidgets('the Pro suffix renders in every supported locale', (
      tester,
    ) async {
      for (final locale in L10N.supportedLocales) {
        final l10n = await L10N.delegate.load(locale);
        await tester.pumpWidget(_harness(locale: locale));
        await tester.pump();

        final labels = _leafLabels(tester);
        final proBase = NetcruxAction.showConeOfInfluenceFanin.label(l10n);
        final freeBase = NetcruxAction.openProject.label(l10n);

        expect(
          labels,
          contains('$proBase${tierLabelSuffix(LicenseTier.pro, l10n)}'),
          reason: 'Pro suffix in $locale',
        );
        expect(
          labels,
          contains(freeBase),
          reason: 'free action unchanged in $locale',
        );
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    });
  });
}
