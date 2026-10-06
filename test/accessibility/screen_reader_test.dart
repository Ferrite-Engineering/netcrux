// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// What a screen reader user hears in the workspace, asserted.
//
// The first external NVDA pass (Windows 11, NVDA 2026.1, on WaveCrux) heard
// FLUTTERVIEW at launch, bare "text" Tab stops and controls announced under
// two names, while every automated guard was green. The same shared chrome
// builds this screen, so the same checks run here. The transcripts under
// `goldens/` are what the focus walk records; a change in what is announced
// shows up as a diff there. Rewrite them with
// `flutter test --update-goldens test/accessibility` and read the diff before
// committing it.

import 'dart:io';

import 'package:crux_a11y/crux_a11y_testing.dart';
import 'package:crux_settings/crux_settings.dart';
import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:crux_workspace/crux_workspace.dart';
import 'package:crux_yosys/crux_yosys.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/app.dart';
import 'package:netcrux/core/shortcuts/netcrux_action.dart';
import 'package:netcrux/core/shortcuts/shortcut_manager_widget.dart';
import 'package:netcrux/domain/models/app_settings.dart';
import 'package:netcrux/domain/models/custom_cell_symbol/cell_symbol_geometry.dart';
import 'package:netcrux/domain/models/layout/bounding_box.dart';
import 'package:netcrux/domain/models/layout/edge_route.dart';
import 'package:netcrux/domain/models/layout/netlist_layout.dart';
import 'package:netcrux/domain/models/layout/node_position.dart';
import 'package:netcrux/domain/models/netlist/module.dart';
import 'package:netcrux/domain/models/workspace/netcrux_tab_payload.dart';
import 'package:netcrux/features/project/providers/loaded_netlist_provider.dart';
import 'package:netcrux/features/settings/providers/app_settings_provider.dart';
import 'package:netcrux/features/workspace/screens/workspace_screen.dart';
import 'package:netcrux/services/file_open/file_open_service.dart';
import 'package:netcrux/services/file_open/file_open_service_provider.dart';
import 'package:netcrux/services/layout/elk_layout_service.dart';
import 'package:netcrux/services/layout/elk_layout_service_provider.dart';
import 'package:netcrux/services/settings/netcrux_settings_codec.dart';
import 'package:netcrux/services/workspace/netcrux_pane_overrides.dart';
import 'package:netcrux/services/workspace/netcrux_tab_overrides.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_codec.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_notifier.dart';
import 'package:netcrux/services/workspace/tab_container_manager_holder.dart';
import 'package:netcrux/services/yosys/prebuilt_netlist_loader_provider.dart';
import 'package:netcrux/services/yosys/yosys_availability_provider.dart';
import 'package:netcrux/services/yosys/yosys_json_parser.dart';
import 'package:netcrux/shared/widgets/workspace_managers_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/app_boot_overrides.dart';

// ── harness ─────────────────────────────────────────────────────────────────

/// A file picker that hands back [paths] without a platform dialog.
class _FakePickerService extends FileOpenService {
  _FakePickerService(this.paths);

  final List<String> paths;

  @override
  Future<FileOpenResult> pickSourceFiles({required String dialogTitle}) async =>
      FileOpenResult(paths);
}

/// A top module holding one instance of an empty module, so the Hierarchy
/// tree has a parent row and a child row — the shape that shows it is one
/// Tab stop rather than one per row.
const String _designJson = '''
{"creator": "fake yosys", "modules": {
  "top": {"attributes": {"top": "1"}, "ports": {}, "netnames": {},
    "cells": {"u_core": {"type": "core", "parameters": {}, "attributes": {},
      "port_directions": {}, "connections": {}}}},
  "core": {"attributes": {}, "ports": {}, "cells": {}, "netnames": {}}}}
''';

/// Lays every cell out in a row without elkjs, which has no JS runtime under
/// `flutter test`.
class _RowLayoutService extends ElkLayoutService {
  @override
  Future<NetlistLayout> layout(
    Module module, {
    CellSymbolGeometries symbols = CellSymbolGeometries.none,
  }) async => NetlistLayout(
    nodes: <NodePosition>[
      for (final (i, name) in module.cells.keys.indexed)
        NodePosition(
          id: name,
          bounds: BoundingBox(x: 40 + i * 120.0, y: 40, width: 80, height: 40),
        ),
    ],
    edges: const <EdgeRoute>[],
    bounds: BoundingBox(
      x: 0,
      y: 0,
      width: 80 + module.cells.length * 120.0,
      height: 120,
    ),
  );
}

/// Nothing under the dialog is a Tab stop.
///
/// This is the failure the fix closed: the dialog covered the window, its
/// barrier dropped the semantics of everything beneath, and focus stayed on
/// the start screen's Open Project button. Tab then walked controls a screen
/// reader announced as nothing, and the dialog could not be answered from the
/// keyboard at all.
void _expectNothingBehindTheDialog(FocusWalk walk) {
  expect(
    walk.stops.map((s) => s.line).where((l) => l.contains('Open Project')),
    isEmpty,
    reason: 'focus escaped the first-launch dialog to the screen behind it',
  );
}

/// What an installation looks like once the two first-launch dialogs have
/// been answered: the agreement accepted, and the usage-statistics question
/// declined. That is the state every screen below the dialogs is reached in,
/// and the default for the walks that are about those screens.
const _answeredFirstLaunch = <String, Object>{
  ...kEulaAcceptedPrefs,
  // `TelemetryConsentState.disabled.name`, spelled out because a default
  // argument has to be const and `.name` is not.
  kTelemetryConsentKey: 'disabled',
};

/// Boots the real app — menu bar, window chrome, workspace screen — on an
/// empty in-memory workspace. [preferences] is what this installation has
/// already answered; the default is [_answeredFirstLaunch]. Returns the tab
/// manager so a test can reach the tab it opens.
Future<TabContainerManager> _pumpApp(
  WidgetTester tester, {
  List<Override> overrides = const <Override>[],
  Map<String, Object> preferences = _answeredFirstLaunch,
}) async {
  await tester.binding.setSurfaceSize(const Size(1600, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final workspaceDir = Directory.systemTemp.createTempSync('netcrux_a11y_ws_');
  addTearDown(() => workspaceDir.deleteSync(recursive: true));

  SharedPreferences.setMockInitialValues(preferences);
  final prefs = await SharedPreferences.getInstance();
  final root = ProviderContainer(
    overrides: <Override>[
      ...netcruxAppTestOverrides(),
      settingsServiceProvider.overrideWithValue(
        SettingsService<AppSettings>(
          const NetcruxSettingsCodec(),
          prefsOverride: prefs,
        ),
      ),
      netcruxWorkspaceProvider.overrideWith(
        () => NetcruxWorkspaceNotifier(
          service: WorkspaceService<NetcruxTabPayload>(
            codec: const NetcruxWorkspaceCodec(),
            directoryFactory: () async => workspaceDir,
            logger: (_) {},
          ),
          autoSaveDebounce: const Duration(milliseconds: 50),
        ),
      ),
      ...overrides,
    ],
  );
  addTearDown(root.dispose);
  final tabs = TabContainerManager(
    rootContainer: root,
    overridesFactory: netcruxTabOverridesFactory,
  );
  addTearDown(tabs.dispose);
  final panes = PaneContainerManager(
    rootContainer: root,
    overridesFactory: netcruxPaneOverridesFactory,
  );
  addTearDown(panes.dispose);
  // The wiring bootstrap performs: the root-scope action-flags mirror
  // resolves tab containers through the holder, and the managers reconcile
  // against workspace shape transitions.
  root.read(tabContainerManagerHolderProvider).manager = tabs;
  root.read(netcruxWorkspaceProvider.notifier)
    ..addScopeReconciler(tabs)
    ..addScopeReconciler(panes);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: root,
      child: WorkspaceManagersScope(
        tabContainerManager: tabs,
        paneContainerManager: panes,
        child: const NetcruxApp(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return tabs;
}

/// Opens [source] as a tab through the shell's own Open Source Files handler
/// and hands the tab an elaborated design, standing in for Yosys.
Future<void> _openDesign(
  WidgetTester tester,
  TabContainerManager tabs,
  File source,
) async {
  tester
      .widget<ShortcutManagerWidget>(find.byType(ShortcutManagerWidget))
      .handlers[NetcruxAction.openSourceFiles]!();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));

  final root = ProviderScope.containerOf(
    tester.element(find.byType(WorkspaceScreen)),
    listen: false,
  );
  final activeTabId = root.read(netcruxWorkspaceProvider).value?.activeTabId;
  expect(activeTabId, isNotNull, reason: '${source.path} must open a tab');
  tabs
      .containerFor(activeTabId!)
      .read(loadedNetlistProvider.notifier)
      .setModel(const YosysJsonParser().parse(_designJson));
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

// ── tests ───────────────────────────────────────────────────────────────────

void main() {
  const goldens = 'test/accessibility/goldens';

  // The two dialogs a first launch shows, before any of the walks below are
  // reachable. Each covers the whole window, and a keyboard or screen-reader
  // user has to be able to answer it: focus starts inside, Tab stays inside,
  // and everything it lands on is named. NetCrux's own screens are not
  // reachable behind either, so the walk is the dialog and nothing else.
  testWidgets(
    'a first launch puts focus in the licence agreement and keeps it there',
    (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpApp(tester, preferences: const <String, Object>{});

      // Focus opens on the agreement itself, so a screen reader starts by
      // reading what is being agreed to.
      expectFocusAnnounced(
        tester,
        named: 'Agreement text',
        context: 'first launch',
      );
      final walk = await walkFocus(tester);
      expectCleanFocusWalk(walk, context: 'the licence agreement');
      // Accept is not a stop until the box is ticked — it is disabled, and a
      // disabled button is not focusable.
      const acceptBox =
          'I have read and accept the End User License Agreement. '
          'check box not checked';
      expect(
        walk.stops.map((s) => s.line),
        containsAll(<String>[acceptBox, 'Decline and quit button']),
      );
      _expectNothingBehindTheDialog(walk);
      expectFocusWalkGolden(walk, '$goldens/first_launch_agreement.txt');
      handle.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'the usage-statistics disclosure takes focus and keeps it',
    (tester) async {
      final handle = tester.ensureSemantics();
      // The agreement is answered; the disclosure is not, which is the second
      // half of a first launch.
      await _pumpApp(tester, preferences: kEulaAcceptedPrefs);

      // Focus opens on the disclosure's own text: what is collected is read
      // before the switch that decides it.
      expectFocusAnnounced(
        tester,
        named: 'Anonymous usage and error counts',
        context: 'first launch, after the agreement',
      );
      final walk = await walkFocus(tester);
      expectCleanFocusWalk(walk, context: 'the usage-statistics disclosure');
      // The switch and the one button that answers the question are both
      // reachable, and the switch says which way it is set.
      expect(
        walk.stops.map((s) => s.line),
        containsAll(<String>[
          'Send anonymous usage statistics switch on',
          'Continue button',
        ]),
      );
      _expectNothingBehindTheDialog(walk);
      expectFocusWalkGolden(walk, '$goldens/first_launch_disclosure.txt');
      handle.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'launch puts focus on Open Project, so something is announced',
    (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpApp(tester);

      expectFocusAnnounced(tester, named: 'Open Project', context: 'launch');
      final walk = await walkFocus(tester);
      expectCleanFocusWalk(walk, context: 'start screen');
      expectFocusWalkGolden(walk, '$goldens/start_screen.txt');
      handle.dispose();
    },
    // The NVDA pass ran on Windows, where the frameless window draws its own
    // title bar and menus; walk the screen a Windows user gets.
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'F6 and Shift+F6 move between the toolbar and the start screen',
    (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpApp(tester);

      // The idle status bar holds nothing focusable, so from the start
      // screen the next region with a control is the toolbar.
      await tester.sendKeyEvent(LogicalKeyboardKey.f6);
      await tester.pump();
      expect(
        describeFocus(tester).line,
        '[Toolbar grouping] Open Project… (Ctrl+O) button',
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.f6);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expectFocusAnnounced(tester, named: 'Open Project…', context: 'Shift+F6');
      expect(
        describeFocus(tester).line,
        '[Welcome to NetCrux grouping] Open Project… button',
      );
      handle.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'the browser start screen offers one named action, announced at launch',
    (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpApp(
        tester,
        overrides: <Override>[
          hdlElaborationSupportedProvider.overrideWithValue(false),
        ],
      );

      expectFocusAnnounced(
        tester,
        named: 'Open Netlist JSON',
        context: 'browser launch',
      );
      final walk = await walkFocus(tester);
      expectCleanFocusWalk(walk, context: 'browser start screen');
      expectFocusWalkGolden(walk, '$goldens/browser_start_screen.txt');
      handle.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'with a design open, every Tab stop is named',
    (tester) async {
      final handle = tester.ensureSemantics();
      final dir = Directory.systemTemp.createTempSync('netcrux_a11y_src_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final source = File('${dir.path}/top.v')
        ..writeAsStringSync('module top(); endmodule\n');
      final tabs = await _pumpApp(
        tester,
        overrides: <Override>[
          fileOpenServiceProvider.overrideWithValue(
            _FakePickerService(<String>[source.path]),
          ),
          // No subprocess: elaboration never starts, and the design is
          // handed to the tab directly.
          yosysAvailabilityProvider.overrideWith(
            (ref) async =>
                const YosysAvailability.notFound(reason: 'test stub'),
          ),
          elkLayoutServiceProvider.overrideWithValue(_RowLayoutService()),
        ],
      );
      await _openDesign(tester, tabs, source);

      // The canvas takes focus when the tab opens and names what it shows.
      expectFocusAnnounced(
        tester,
        named: 'Schematic: 1 cell,',
        context: 'design opened',
      );
      final walk = await walkFocus(tester);
      expectCleanFocusWalk(walk, context: 'workspace with a design open');
      expect(
        walk.stops.map((s) => s.line),
        containsAll(<String>[
          // One spoken name for the strip, not its terse visible caption.
          'Statistics button collapsed',
          // The close button says which tab it closes.
          '[top.v button] Close top.v button',
        ]),
      );
      // The Hierarchy tree is one Tab stop: the selected parent row, with its
      // state. The child row is reached with the arrow keys, not Tab.
      expect(
        walk.stops.map((s) => s.line).where((l) => l.contains('cell button')),
        <String>['top 1 cell button expanded selected'],
      );
      expectFocusWalkGolden(walk, '$goldens/design_open.txt');
      handle.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}
