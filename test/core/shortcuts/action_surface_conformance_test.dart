// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Cross-surface conformance: every action-discovery surface (toolbar, menu
// bar, command palette) must render exactly the actions — and exactly the
// enabled/disabled state — that the single-source-of-truth selectors in
// `netcrux_action_descriptors.dart` prescribe, across a matrix of contexts.
//
// Each surface reads the shared `netcruxActionContextProvider`, so the
// harness overrides that provider with a precise `NetcruxActionContext` and
// asserts the rendered surface matches `groupedActionsFor` /
// `paletteActionsFor` / `isActionEnabled` for the same context. This keeps
// the assertions tied to the contract, not to any surface's internals.

import 'package:crux_command_palette/crux_command_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/shortcuts/action_tier_label.dart';
import 'package:netcrux/core/shortcuts/netcrux_action.dart';
import 'package:netcrux/core/shortcuts/netcrux_action_context.dart';
import 'package:netcrux/core/shortcuts/netcrux_action_descriptor.dart';
import 'package:netcrux/core/shortcuts/netcrux_action_descriptors.dart';
import 'package:netcrux/features/command_palette/widgets/command_palette_dialog.dart';
import 'package:netcrux/features/menu_bar/widgets/desktop_menu_bar.dart';
import 'package:netcrux/features/viewer/widgets/netcrux_toolbar.dart';
import 'package:netcrux/features/workspace/providers/netcrux_action_context_provider.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

void _noop(NetcruxAction _) {}

/// The context matrix every surface is checked against: empty workspace,
/// open tab with nothing loaded, loaded design without a selection, loaded
/// design with a selection, and the fully-loaded analysis state.
const Map<String, NetcruxActionContext> _contextMatrix = {
  'no tab': NetcruxActionContext(),
  'tab, no design': NetcruxActionContext(hasOpenTab: true),
  'design, no selection': NetcruxActionContext(
    hasOpenTab: true,
    hasNetlist: true,
  ),
  'design + selection': NetcruxActionContext(
    hasOpenTab: true,
    hasNetlist: true,
    hasSelection: true,
  ),
  'analysis loaded (split panes)': NetcruxActionContext(
    hasOpenTab: true,
    hasNetlist: true,
    hasSelection: true,
    hasTraceOverlay: true,
    hasXTraceResult: true,
    comparisonActive: true,
    waveformLoaded: true,
    cdcAnalysisPresent: true,
    resetAnalysisPresent: true,
    fsmFocused: true,
    activityColoringActive: true,
    paneCount: 2,
  ),
  'browser build, design loaded': NetcruxActionContext(
    hasOpenTab: true,
    hasNetlist: true,
    hasSelection: true,
    isBrowser: true,
  ),
};

Widget _wrap({
  required Widget home,
  required NetcruxActionContext ctx,
  String locale = 'en',
  TargetPlatform platform = TargetPlatform.macOS,
}) => ProviderScope(
  overrides: [netcruxActionContextProvider.overrideWithValue(ctx)],
  child: MaterialApp(
    theme: ThemeData(platform: platform),
    locale: Locale(locale),
    localizationsDelegates: L10N.localizationsDelegates,
    supportedLocales: L10N.supportedLocales,
    home: home,
  ),
);

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

String _menuLabel(NetcruxAction a, L10N l10n) =>
    a.label(l10n) + tierLabelSuffix(a.requiredTier, l10n);

void main() {
  // ── Menu bar (native, desktop) ─────────────────────────────────────────────
  group('DesktopMenuBar conformance', () {
    Future<(PlatformMenuBar, L10N)> pumpMenu(
      WidgetTester tester,
      NetcruxActionContext ctx,
    ) async {
      await tester.pumpWidget(
        _wrap(
          ctx: ctx,
          home: const DesktopMenuBar(
            onAction: _noop,
            child: Scaffold(body: SizedBox.shrink()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final bar = tester.widget<PlatformMenuBar>(find.byType(PlatformMenuBar));
      final l10n = L10N.of(tester.element(find.byType(PlatformMenuBar)));
      return (bar, l10n);
    }

    // The browser never mounts the desktop menu bar (`CruxDesktopMenuBar`
    // returns its child under `kIsWeb`), so the browser context is checked on
    // the palette and the toolbar only.
    for (final entry in _contextMatrix.entries.where(
      (e) => !e.value.isBrowser,
    )) {
      testWidgets('presence + enablement match the table (${entry.key})', (
        tester,
      ) async {
        final ctx = entry.value;
        final (bar, l10n) = await pumpMenu(tester, ctx);
        final expected = groupedActionsFor(
          NetcruxActionSurface.menu,
          ctx,
        ).values.expand((x) => x).toList();

        // Presence: the leaf labels are exactly the table's menu actions
        // (with tier suffixes).
        expect(
          _leafItems(bar).map((e) => e.label).toSet(),
          expected.map((a) => _menuLabel(a, l10n)).toSet(),
        );

        // Enablement: a menu item is enabled iff the table says so.
        final leafByLabel = {for (final i in _leafItems(bar)) i.label: i};
        for (final a in expected) {
          final item = leafByLabel[_menuLabel(a, l10n)];
          expect(item, isNotNull, reason: '$a missing from menu');
          expect(
            item!.onSelected != null,
            isActionEnabled(a, ctx),
            reason: '$a enablement mismatch under "${entry.key}"',
          );
        }
      });
    }
  });

  // ── Command palette ────────────────────────────────────────────────────────
  group('CommandPaletteDialog conformance', () {
    for (final entry in _contextMatrix.entries) {
      testWidgets('listed actions match paletteActionsFor (${entry.key})', (
        tester,
      ) async {
        final ctx = entry.value;
        await tester.pumpWidget(
          _wrap(
            ctx: ctx,
            home: const Scaffold(body: CommandPaletteDialog(onAction: _noop)),
          ),
        );
        await tester.pumpAndSettle();
        final palette = tester.widget<CommandPalette<NetcruxAction>>(
          find.byType(CommandPalette<NetcruxAction>),
        );
        expect(
          palette.actions,
          paletteActionsFor(ctx),
          reason:
              'the palette must list exactly the visible+enabled actions '
              'under "${entry.key}"',
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('disabled and hidden actions never surface as rows', (
      tester,
    ) async {
      const ctx = NetcruxActionContext();
      await tester.pumpWidget(
        _wrap(
          ctx: ctx,
          home: const Scaffold(body: CommandPaletteDialog(onAction: _noop)),
        ),
      );
      await tester.pumpAndSettle();
      final l10n = L10N.of(
        tester.element(find.byType(CommandPalette<NetcruxAction>)),
      );
      for (final hidden in [
        NetcruxAction.zoomIn, // disabled: no design
        NetcruxAction.showXTrace, // structurally hidden
        NetcruxAction.openCommandPalette, // self-referential
      ]) {
        expect(
          find.descendant(
            of: find.byType(CommandPalette<NetcruxAction>),
            matching: find.text(hidden.label(l10n)),
          ),
          findsNothing,
          reason: '$hidden must not render a palette row',
        );
      }
    });
  });

  // ── Toolbar ────────────────────────────────────────────────────────────────
  group('NetcruxToolbar conformance', () {
    Iterable<NetcruxAction> toolbarActions() => NetcruxAction.values.where(
      (a) => descriptorFor(a).surfaces.contains(NetcruxActionSurface.toolbar),
    );

    for (final entry in _contextMatrix.entries) {
      testWidgets(
        'every visible toolbar action has a button enabled per the table '
        '(${entry.key})',
        (tester) async {
          final ctx = entry.value;
          await tester.pumpWidget(
            _wrap(
              ctx: ctx,
              home: const Scaffold(body: NetcruxToolbar(onAction: _noop)),
            ),
          );
          await tester.pumpAndSettle();
          // The trace trio shares one grouped slot, so only its faced variant
          // has a top-level button; the siblings live in the cluster menu.
          const inSplitCluster = {
            NetcruxAction.showFanout,
            NetcruxAction.clearOverlay,
          };
          for (final a in toolbarActions()) {
            if (inSplitCluster.contains(a)) continue;
            final keyFinder = find.byKey(ValueKey<NetcruxAction>(a));
            if (!isActionVisibleIn(a, NetcruxActionSurface.toolbar, ctx)) {
              expect(keyFinder, findsNothing, reason: '$a must be hidden');
              continue;
            }
            expect(keyFinder, findsOneWidget, reason: '$a button missing');
            // The shared CruxToolbarButton wraps the IconButton, so reach
            // through rather than casting the keyed widget itself.
            final button = tester.widget<IconButton>(
              find.descendant(of: keyFinder, matching: find.byType(IconButton)),
            );
            expect(
              button.onPressed != null,
              isActionEnabled(a, ctx),
              reason: '$a enablement mismatch under "${entry.key}"',
            );
          }
        },
      );
    }
  });

  // ── Locale sweep ───────────────────────────────────────────────────────────
  group('locale sweep', () {
    for (final locale in ['en', 'zh', 'ja', 'ko']) {
      testWidgets('palette + toolbar render in $locale without exceptions', (
        tester,
      ) async {
        await tester.pumpWidget(
          _wrap(
            ctx: _contextMatrix['analysis loaded (split panes)']!,
            locale: locale,
            home: const Scaffold(
              body: Column(
                children: [
                  NetcruxToolbar(onAction: _noop),
                  Expanded(child: CommandPaletteDialog(onAction: _noop)),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });
}
