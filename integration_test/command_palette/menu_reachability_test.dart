// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/command_palette/menu_reachability_test.dart
//
// Verification driver for Open-Core Guide §4.1.11 (Command palette
// reachable via the menu bar after its own shortcut is unbound).
// The opener sat under Help until the shared menu bar landed and moved
// it to View, where all four products now carry it.
// `openCommandPalette` used to be hidden from the browsable menu, so a
// user who unbound its keyboard shortcut lost every way to reach the
// palette. The descriptor table (`netcrux_action_descriptors.dart`)
// keeps the action on the menu surface (View category) while excluding
// it from the palette surface so it can't list itself.
//
// The native macOS/Windows/Linux menu bar renders through
// `PlatformMenuBar`, which isn't a Flutter widget `WidgetTester` can tap
// (its items are native NSMenu / Win32 / GTK menu entries, invisible to
// the widget tree). Per the CLAUDE.md guidance for this item, this test
// instead drives the exact dispatch path the native View-menu item's
// `onSelected` callback uses: `DesktopMenuBar.onAction`, which
// `WorkspaceScreen.build` wires to `_dispatchAction` — the same
// dispatcher the command palette's own row taps and every keyboard
// shortcut route through (see that file's "Single source of truth"
// comment). Reading the live `DesktopMenuBar` widget's `onAction`
// callback and invoking it with `NetcruxAction.openCommandPalette`
// is exactly what clicking "View → Command Palette" would do —
// `PlatformMenuItem(onSelected: () => onAction(action))` is a direct,
// untransformed call to the same field.

import 'package:crux_command_palette/crux_command_palette.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:netcrux/core/shortcuts/action_category.dart';
import 'package:netcrux/core/shortcuts/netcrux_action.dart';
import 'package:netcrux/core/shortcuts/netcrux_action_context.dart';
import 'package:netcrux/core/shortcuts/netcrux_action_descriptor.dart';
import 'package:netcrux/core/shortcuts/netcrux_action_descriptors.dart';
import 'package:netcrux/core/shortcuts/shortcut_bindings_provider.dart';
import 'package:netcrux/features/menu_bar/widgets/desktop_menu_bar.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

import '../helpers/app_driver.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets(
    'command palette opens via the View-menu dispatch path after its own '
    'shortcut is unbound, and does not list itself (Guide §4.1.11)',
    (tester) async {
      // Static preconditions this test's premise depends on — fail loudly
      // (not just "widget not found") if either regresses.
      expect(
        NetcruxAction.openCommandPalette.category,
        ActionCategory.view,
        reason: 'this test drives the View-menu dispatch path',
      );
      const emptyContext = NetcruxActionContext();
      expect(
        isActionVisibleIn(
          NetcruxAction.openCommandPalette,
          NetcruxActionSurface.menu,
          emptyContext,
        ),
        isTrue,
        reason:
            'the palette opener must stay reachable from the menu bar '
            'even when its shortcut is unbound',
      );
      expect(
        descriptorFor(
          NetcruxAction.openCommandPalette,
        ).surfaces.contains(NetcruxActionSurface.palette),
        isFalse,
        reason: 'the palette must not list its own opener action',
      );

      await bootNetcrux(tester);
      final root = rootContainer(tester);
      final bindingsNotifier = root.read(shortcutBindingsProvider.notifier);

      // Sane starting point: the default keymap does bind a shortcut.
      expect(
        root.read(shortcutBindingsProvider)[NetcruxAction.openCommandPalette],
        isNotNull,
      );

      // Unbind — the scenario under test. `unbind` PERSISTS the diff to
      // the keymap store, so without this teardown the unbind outlives
      // the process and every later run of this test starts with the
      // shortcut already gone — failing the "sane starting point" check
      // above rather than the thing under test. `reset` restores the
      // platform default and clears the stored diff.
      addTearDown(
        () => bindingsNotifier.reset(NetcruxAction.openCommandPalette),
      );
      bindingsNotifier.unbind(NetcruxAction.openCommandPalette);
      await tester.pump();
      expect(
        root.read(shortcutBindingsProvider)[NetcruxAction.openCommandPalette],
        isNull,
        reason: 'unbind must clear the activator',
      );

      // Dispatch the View-menu action the way its native menu item would —
      // through the live DesktopMenuBar's onAction callback, not by trying
      // to tap native menu chrome.
      final menuBar = tester.widget<DesktopMenuBar>(
        find.byType(DesktopMenuBar),
      );
      menuBar.onAction(NetcruxAction.openCommandPalette);

      // The palette opens on a dialog route: pushing it, building it and
      // running its transition take more than the two fixed pumps this
      // test used to spend, so poll for the route rather than asserting
      // on whichever frame happened to land first.
      final paletteFinder = find.byType(CommandPalette<NetcruxAction>);
      final paletteOpened = await pumpUntil(
        tester,
        () => paletteFinder.evaluate().length == 1,
      );
      expect(
        paletteOpened,
        isTrue,
        reason: 'the palette route never opened',
      );
      expect(
        paletteFinder,
        findsOneWidget,
        reason:
            'the View-menu dispatch path must open the command palette '
            'even with no keyboard shortcut bound to it',
      );

      final context = tester.element(paletteFinder);
      final l10n = L10N.of(context);
      expect(
        find.descendant(
          of: paletteFinder,
          matching: find.text(l10n.commandPaletteSearchHint),
        ),
        findsOneWidget,
        reason: 'sanity check that the opened dialog really is the palette',
      );

      // The palette does not list itself.
      expect(
        find.descendant(
          of: paletteFinder,
          matching: find.text(
            NetcruxAction.openCommandPalette.label(l10n),
          ),
        ),
        findsNothing,
        reason: 'the command palette must not list "Open Command Palette"',
      );

      expect(tester.takeException(), isNull);
    },
  );
}
