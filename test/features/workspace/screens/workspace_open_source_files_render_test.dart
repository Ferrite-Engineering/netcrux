// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_settings/crux_settings.dart';
import 'package:crux_workspace/crux_workspace.dart';
import 'package:crux_yosys/crux_yosys.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/app.dart';
import 'package:netcrux/core/shortcuts/netcrux_action.dart';
import 'package:netcrux/core/shortcuts/shortcut_manager_widget.dart';
import 'package:netcrux/domain/models/app_settings.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/workspace/netcrux_tab_payload.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/project/providers/loaded_netlist_provider.dart';
import 'package:netcrux/features/settings/providers/app_settings_provider.dart';
import 'package:netcrux/services/file_open/file_open_service.dart';
import 'package:netcrux/services/file_open/file_open_service_provider.dart';
import 'package:netcrux/services/settings/netcrux_settings_codec.dart';
import 'package:netcrux/services/workspace/netcrux_pane_overrides.dart';
import 'package:netcrux/services/workspace/netcrux_tab_overrides.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_codec.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_notifier.dart';
import 'package:netcrux/services/workspace/tab_container_manager_holder.dart';
import 'package:netcrux/services/yosys/yosys_availability_provider.dart';
import 'package:netcrux/services/yosys/yosys_json_parser.dart';
import 'package:netcrux/shared/widgets/workspace_managers_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/app_boot_overrides.dart';

/// Regression tests for the blank-render bug after "Open Source Files…":
/// the elaborated netlist reached the per-tab container (the status bar
/// showed "File … · Top … · N cells") but the hierarchy panel stayed on
/// its "Open a design" placeholder and the schematic canvas stayed blank,
/// because `ProjectTabContent`'s `loadedNetlistProvider` →
/// `hierarchyTreeProvider.setModel` bridge was edge-triggered and the
/// netlist had already resolved BEFORE the tab content's first build
/// registered the listener (elaboration-cache hit: the root-scope
/// action-flags mirror starts the pipeline the moment the tab is created,
/// and the cache resolves it within a few event-loop turns — before the
/// first frame that mounts the tab content).
///
/// Both tests drive the REAL production flow end-to-end: the workspace
/// shell's openSourceFiles action → (faked) file picker → `openTab` +
/// `setSourceFiles` → the netlist resolving — then assert the active
/// tab's hierarchy tree actually received the model.
class _FakePickerService extends FileOpenService {
  _FakePickerService(this.paths);

  final List<String> paths;

  @override
  Future<FileOpenResult> pickSourceFiles({required String dialogTitle}) async {
    return FileOpenResult(paths);
  }
}

const String _fakeRawJson =
    '{"creator":"fake yosys","modules":{"top":{"attributes":{"top":"1"}, '
    '"ports":{},"cells":{},"netnames":{}}}}';

/// Everything a scenario needs from the booted app harness.
class _Harness {
  _Harness(this.root, this.tabs);

  final ProviderContainer root;
  final TabContainerManager tabs;
}

Future<_Harness> _bootApp(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1400, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final dir = Directory.systemTemp.createTempSync('netcrux_render_test_');
  addTearDown(() => dir.deleteSync(recursive: true));
  final src = File('${dir.path}/top.v')
    ..writeAsStringSync('module top(); endmodule\n');

  SharedPreferences.setMockInitialValues(<String, Object>{});
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
            directoryFactory: () async =>
                Directory.systemTemp.createTempSync('netcrux_render_ws_'),
            logger: (_) {},
          ),
          autoSaveDebounce: const Duration(milliseconds: 50),
        ),
      ),
      fileOpenServiceProvider.overrideWithValue(
        _FakePickerService(<String>[src.path]),
      ),
      // Deterministic pipeline: the real elaboration never runs (no
      // subprocess, no isolate); each scenario injects the parsed model
      // directly — the same per-tab AsyncData transition a real yosys run
      // (or a cache hit) produces, at the exact moment under test.
      yosysAvailabilityProvider.overrideWith(
        (ref) async => const YosysAvailability.notFound(reason: 'test stub'),
      ),
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
  // Mirror bootstrap's wiring exactly: the root-scope active-tab
  // action-flags mirror resolves tab containers through the holder,
  // and the managers reconcile against workspace shape transitions.
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
  return _Harness(root, tabs);
}

/// Fires the shell's openSourceFiles action through the same handler the
/// toolbar / menu / keyboard use.
void _openSourceFiles(WidgetTester tester) {
  final shortcuts = tester.widget<ShortcutManagerWidget>(
    find.byType(ShortcutManagerWidget),
  );
  shortcuts.handlers[NetcruxAction.openSourceFiles]!();
}

ProviderContainer _activeTabContainer(_Harness h) {
  final activeTabId = h.root.read(netcruxWorkspaceProvider).value?.activeTabId;
  expect(activeTabId, isNotNull, reason: 'a tab must have been opened');
  return h.tabs.containerFor(activeTabId!);
}

void _expectHierarchyHasModel(ProviderContainer tab, NetlistModel model) {
  final tree = tab.read(hierarchyTreeProvider);
  expect(
    tree.model,
    same(model),
    reason: 'hierarchyTreeProvider.setModel must receive the netlist',
  );
  expect(tree.selected, isNotNull);
  expect(tree.selected!.resolve(model)?.name, 'top');
}

void main() {
  testWidgets(
    'netlist resolving BEFORE the tab content first build still populates '
    'the hierarchy (cache-hit regression)',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final h = await _bootApp(tester);

      _openSourceFiles(tester);
      // Drain the async open flow (picker → openTab → setSourceFiles)
      // WITHOUT pumping a frame, then resolve the netlist — mimicking an
      // elaboration-cache hit completing before the new tab's content
      // ever builds (the native picker's dismissal delays the next
      // Flutter frame in the real app).
      await tester.binding.delayed(const Duration(milliseconds: 200));
      final tabContainer = _activeTabContainer(h);
      final model = const YosysJsonParser().parse(_fakeRawJson);
      tabContainer.read(loadedNetlistProvider.notifier).setModel(model);

      // FIRST frame for the tab content — it must pick up the
      // already-resolved netlist even though its listener registered
      // after the transition.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      _expectHierarchyHasModel(tabContainer, model);
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'netlist resolving after the tab content mounts populates the hierarchy',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final h = await _bootApp(tester);

      _openSourceFiles(tester);
      // Let openTab + setSourceFiles land and the tab content mount.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      final tabContainer = _activeTabContainer(h);
      // "Elaboration completes": push the parsed model into the ACTIVE
      // tab's loadedNetlistProvider, exactly where the yosys pipeline
      // publishes its result.
      final model = const YosysJsonParser().parse(_fakeRawJson);
      tabContainer.read(loadedNetlistProvider.notifier).setModel(model);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      _expectHierarchyHasModel(tabContainer, model);
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
