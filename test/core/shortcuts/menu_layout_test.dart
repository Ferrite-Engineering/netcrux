// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_menu_bar/crux_menu_bar.dart';
import 'package:crux_shortcut_action/crux_shortcut_action.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/shortcuts/menu_layout.dart';
import 'package:netcrux/core/shortcuts/netcrux_action.dart';
import 'package:netcrux/core/shortcuts/netcrux_action_descriptor.dart';
import 'package:netcrux/core/shortcuts/netcrux_action_descriptors.dart';

void main() {
  group('kMenuLayout', () {
    test('covers exactly the menu-visible action set', () {
      // Every action the layout names, plus the two app-folded items
      // (Settings / Quit) the shared menu bar positions per-platform.
      final placed = <NetcruxAction>{
        ...cruxMenuLayoutActions(kMenuLayout),
        ...kAppMenuActions.desktopFolded,
      };
      final menuVisible = NetcruxAction.values
          .where(
            (a) =>
                descriptorFor(a).surfaces.contains(NetcruxActionSurface.menu),
          )
          .toSet();
      expect(
        placed,
        equals(menuVisible),
        reason:
            'A menu-visible action is missing from kMenuLayout (or the table '
            'places an action that is no longer menu-visible). Give it a home '
            'in the appropriate category group in menu_layout.dart.',
      );
    });

    test('places no action more than once', () {
      final seen = <NetcruxAction>{};
      for (final groups in kMenuLayout.values) {
        for (final group in groups) {
          for (final action in group) {
            expect(
              seen.add(action),
              isTrue,
              reason: '$action appears more than once in kMenuLayout',
            );
          }
        }
      }
    });

    test('does not place the app-folded actions (Settings / Quit)', () {
      final placed = cruxMenuLayoutActions(kMenuLayout);
      for (final action in kAppMenuActions.desktopFolded) {
        expect(placed, isNot(contains(action)));
      }
      // About and Check for Updates MUST be in the layout: they stay in Help
      // on Windows/Linux and only macOS hoists them.
      expect(placed, contains(kAppMenuActions.about));
      expect(placed, contains(kAppMenuActions.checkForUpdates));
    });

    test('places each action in the category its own mapping declares', () {
      kMenuLayout.forEach((category, groups) {
        for (final group in groups) {
          for (final action in group) {
            expect(
              action.category,
              category,
              reason:
                  '$action is placed under $category but its category is '
                  '${action.category}',
            );
          }
        }
      });
    });

    test('leads View with the command palette and Help with Documentation', () {
      expect(kMenuLayout[ActionCategory.view]!.first, [
        NetcruxAction.openCommandPalette,
      ]);
      expect(kMenuLayout[ActionCategory.help]!.first, [
        NetcruxAction.openDocumentation,
      ]);
      expect(kMenuLayout[ActionCategory.help]!.last, [NetcruxAction.openAbout]);
    });

    test('ends Tools with diagnostics', () {
      // Tab Diagnostics leads (matching WaveCrux), then the per-tab panel
      // toggle, then the process-wide dialog — the same closing group
      // WaveCrux, LintCrux and SimCrux carry.
      expect(kMenuLayout[ActionCategory.tools]!.last, [
        NetcruxAction.openTabDiagnostics,
        NetcruxAction.toggleDiagnosticsPanel,
        NetcruxAction.openAppDiagnostics,
      ]);
    });

    test('declares no Edit menu — NetCrux has no editing actions', () {
      expect(kMenuLayout.containsKey(ActionCategory.edit), isFalse);
    });

    test('keeps each loader next to the command that undoes it', () {
      // The comparison netlist and waveform pairs used to be split across
      // File / Tools / View. Whatever group they land in, both halves must
      // share it, or the user hunts three menus for one workflow.
      List<NetcruxAction> groupContaining(NetcruxAction action) => kMenuLayout
          .values
          .expand((groups) => groups)
          .firstWhere((group) => group.contains(action));

      expect(
        groupContaining(NetcruxAction.loadComparisonNetlist),
        contains(NetcruxAction.clearComparisonNetlist),
      );
      expect(
        groupContaining(NetcruxAction.openWaveformFile),
        contains(NetcruxAction.closeWaveformFile),
      );
    });
  });
}
