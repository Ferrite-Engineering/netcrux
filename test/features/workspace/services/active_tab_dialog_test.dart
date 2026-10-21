// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// A dialog that reads a tab's state is TAB-MODAL: pushed on that tab's own
// navigator (`PaneHost.tabNavigators`), built under the tab's one scope.
// These tests drive the real app (`WorkspaceAppHarness`) through the Search
// dialog, the tab-modal dialog every one of them follows.

import 'dart:async';

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/netlist/cell.dart';
import 'package:netcrux/domain/models/netlist/module.dart';
import 'package:netcrux/domain/models/netlist/net.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/domain/models/workspace/netcrux_tab_payload.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/search/widgets/search_dialog.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/features/viewer/widgets/netcrux_toolbar.dart';
import 'package:netcrux/features/workspace/screens/workspace_screen.dart';
import 'package:netcrux/features/workspace/services/active_tab_navigator.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_notifier.dart';

import '../../../helpers/app_boot_overrides.dart';
import '../../../helpers/workspace_app_harness.dart';

NetlistModel _model(String cellName) => NetlistModel(
  creator: 'test',
  modules: <String, Module>{
    'top': Module(
      name: 'top',
      attributes: const <String, String>{'top': '1'},
      ports: const {},
      cells: <String, Cell>{
        cellName: Cell(
          name: cellName,
          type: r'$add',
          parameters: const <String, String>{},
          attributes: const <String, String>{},
          portDirections: const {},
          connections: const {},
        ),
      },
      nets: const <String, Net>{},
    ),
  },
);

class _Rig {
  _Rig(this.tester, this.h, this.a, this.b);

  final WidgetTester tester;
  final WorkspaceAppHarness h;
  final TabId a;
  final TabId b;

  NetcruxWorkspaceNotifier get _notifier =>
      h.root.read(netcruxWorkspaceProvider.notifier);

  /// A context outside every tab: where the menu bar and the keyboard are.
  BuildContext get screen => tester.element(find.byType(WorkspaceScreen));

  Future<void> activate(TabId id) async {
    await tester.runAsync(() => _notifier.setActiveTab(id));
    await WorkspaceAppHarness.settle(tester);
  }

  Future<void> close(TabId id) async {
    await tester.runAsync(() => _notifier.closeTab(id));
    await WorkspaceAppHarness.settle(tester);
  }

  /// Opens Search the way a shortcut does, from outside every tab.
  Future<void> openSearch() async {
    unawaited(SearchDialog.show(screen));
    await tester.pumpAndSettle();
  }
}

Future<_Rig> _boot(WidgetTester tester) async {
  final h = await WorkspaceAppHarness.boot(
    tester,
    preferences: <String, Object>{
      ...kEulaAcceptedPrefs,
      kTelemetryConsentKey: 'disabled',
    },
  );
  final notifier = h.root.read(netcruxWorkspaceProvider.notifier);
  late TabId a;
  late TabId b;
  await tester.runAsync(() async {
    a = await notifier.openTab(
      displayName: 'a',
      payload: const NetcruxTabPayload(sourceFiles: <String>[], topModule: 'a'),
    );
    b = await notifier.openTab(
      displayName: 'b',
      payload: const NetcruxTabPayload(sourceFiles: <String>[], topModule: 'b'),
    );
  });
  await WorkspaceAppHarness.settle(tester);
  final rig = _Rig(tester, h, a, b);
  await rig.activate(a);
  return rig;
}

void main() {
  testWidgets('a tab dialog covers only its tab, not the window', (
    tester,
  ) async {
    final rig = await _boot(tester);
    await rig.openSearch();

    expect(find.byType(SearchDialog), findsOneWidget);
    final barrier = tester.getRect(find.byType(ModalBarrier).last);
    expect(barrier, tester.getRect(find.byType(CruxTabNavigatorHost)));
    expect(
      barrier.top,
      greaterThanOrEqualTo(tester.getRect(find.byType(NetcruxToolbar)).bottom),
      reason: 'the toolbar and the tab strip stay out from under the barrier',
    );
    // Nothing was pushed on the window's navigator.
    expect(Navigator.of(rig.screen, rootNavigator: true).canPop(), isFalse);

    await WorkspaceAppHarness.unmount(tester);
  });

  testWidgets('it reads the tab it belongs to and writes there', (
    tester,
  ) async {
    final rig = await _boot(tester);
    rig.h.tabs
        .containerFor(rig.a)
        .read(hierarchyTreeProvider.notifier)
        .setModel(_model('cell_in_a'));
    rig.h.tabs
        .containerFor(rig.b)
        .read(hierarchyTreeProvider.notifier)
        .setModel(_model('cell_in_b'));
    await tester.pump();

    await rig.openSearch();
    await tester.enterText(
      find.descendant(
        of: find.byType(SearchDialog),
        matching: find.byType(TextField),
      ),
      'cell',
    );
    await tester.pump(const Duration(milliseconds: 250));

    final inDialog = find.descendant(
      of: find.byType(SearchDialog),
      matching: find.textContaining('cell_in_'),
    );
    expect(inDialog, findsOneWidget);
    expect(find.text('cell_in_a'), findsOneWidget);

    await tester.tap(find.text('cell_in_a'));
    await tester.pumpAndSettle();

    expect(
      rig.h.tabs.containerFor(rig.a).read(selectedElementProvider).primary,
      isA<SelectedElementCell>().having((s) => s.cellId, 'cellId', 'cell_in_a'),
    );
    expect(
      rig.h.tabs.containerFor(rig.b).read(selectedElementProvider).primary,
      isA<SelectedElementNone>(),
    );
    expect(
      rig.h.root.read(selectedElementProvider).primary,
      isA<SelectedElementNone>(),
    );

    await WorkspaceAppHarness.unmount(tester);
  });

  testWidgets('a per-tab write while it is open does not dirty the tab mid '
      'build', (tester) async {
    final rig = await _boot(tester);
    await rig.openSearch();
    final tab = rig.h.tabs.containerFor(rig.a);

    tab.read(hierarchyTreeProvider.notifier).setModel(_model('written'));
    await tester.pump();
    tab
        .read(selectedElementProvider.notifier)
        .select(const SelectedElement.cell(cellId: 'written'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(tester.takeException(), isNull);
    expect(find.byType(SearchDialog), findsOneWidget);

    await WorkspaceAppHarness.unmount(tester);
  });

  testWidgets('it stays with its tab across a switch, and the other tab opens '
      'its own copy', (tester) async {
    final rig = await _boot(tester);
    final keyA = ActiveTab.guardKey(rig.screen, 'search');
    await rig.openSearch();
    expect(find.byType(SearchDialog), findsOneWidget);
    expect(ModalGuard.isOpen(keyA), isTrue);

    await rig.activate(rig.b);
    expect(
      find.byType(SearchDialog),
      findsNothing,
      reason: 'it went with its tab',
    );
    expect(find.byType(SearchDialog, skipOffstage: false), findsOneWidget);

    final keyB = ActiveTab.guardKey(rig.screen, 'search');
    expect(keyB, isNot(keyA));
    await rig.openSearch();
    expect(
      find.byType(SearchDialog),
      findsOneWidget,
      reason: 'a process-wide key would have swallowed Search in this tab',
    );
    expect(find.byType(SearchDialog, skipOffstage: false), findsNWidgets(2));

    await rig.activate(rig.a);
    expect(find.byType(SearchDialog), findsOneWidget);
    expect(find.byType(SearchDialog, skipOffstage: false), findsNWidgets(2));

    // Closing the one on screen frees only its key.
    Navigator.of(tester.element(find.byType(SearchDialog))).pop();
    await tester.pumpAndSettle();
    expect(ModalGuard.isOpen(keyA), isFalse);
    expect(ModalGuard.isOpen(keyB), isTrue);

    await WorkspaceAppHarness.unmount(tester);
  });

  testWidgets('closing the tab completes the dialog future and frees its '
      'key', (tester) async {
    final rig = await _boot(tester);
    final key = ActiveTab.guardKey(rig.screen, 'search');
    var completed = false;
    unawaited(
      SearchDialog.show(rig.screen).whenComplete(() => completed = true),
    );
    await tester.pumpAndSettle();
    expect(ModalGuard.isOpen(key), isTrue);
    expect(completed, isFalse);

    await rig.close(rig.a);

    expect(completed, isTrue, reason: 'the opener is not left waiting');
    expect(ModalGuard.isOpen(key), isFalse);
    expect(find.byType(SearchDialog, skipOffstage: false), findsNothing);
    expect(tester.takeException(), isNull);

    await WorkspaceAppHarness.unmount(tester);
  });

  testWidgets('with no tab open it falls back to the window', (tester) async {
    final h = await WorkspaceAppHarness.boot(
      tester,
      preferences: <String, Object>{
        ...kEulaAcceptedPrefs,
        kTelemetryConsentKey: 'disabled',
      },
    );
    final screen = tester.element(find.byType(WorkspaceScreen));
    expect(ActiveTab.navigatorFor(screen), isNull);
    expect(ActiveTab.guardKey(screen, 'search'), 'search');
    expect(h.root.read(netcruxWorkspaceProvider).value?.tabs, isEmpty);

    await WorkspaceAppHarness.unmount(tester);
  });

  group("a key typed in a tab dialog is the dialog's", () {
    Future<void> chord(
      WidgetTester tester,
      List<LogicalKeyboardKey> modifiers,
      LogicalKeyboardKey key,
    ) async {
      for (final modifier in modifiers) {
        await tester.sendKeyDownEvent(modifier);
      }
      await tester.sendKeyEvent(key);
      for (final modifier in modifiers.reversed) {
        await tester.sendKeyUpEvent(modifier);
      }
      await tester.pumpAndSettle();
    }

    testWidgets('a workspace chord does not fire behind it', (tester) async {
      final rig = await _boot(tester);
      await rig.openSearch();

      // Modifier chords pass through a text field on purpose, so before the
      // dialog's keys were fenced Ctrl+Shift+P opened the palette over the
      // search dialog.
      await chord(tester, <LogicalKeyboardKey>[
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.shiftLeft,
      ], LogicalKeyboardKey.keyP);

      expect(ModalGuard.isOpen('commandPalette'), isFalse);
      expect(find.byType(SearchDialog), findsOneWidget);

      await WorkspaceAppHarness.unmount(tester);
    });

    testWidgets('the same chord fires once the dialog is closed', (
      tester,
    ) async {
      final rig = await _boot(tester);
      await rig.openSearch();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(SearchDialog), findsNothing);

      await tester.tap(find.byType(NetcruxToolbar));
      await tester.pump();
      await chord(tester, <LogicalKeyboardKey>[
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.shiftLeft,
      ], LogicalKeyboardKey.keyP);

      expect(ModalGuard.isOpen('commandPalette'), isTrue);

      await WorkspaceAppHarness.unmount(tester);
    });
  });
}
