// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_settings/crux_settings.dart';
import 'package:crux_workspace/crux_workspace.dart';
import 'package:crux_yosys/crux_yosys.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/app.dart';
import 'package:netcrux/core/cli/cli_launch_intent.dart';
import 'package:netcrux/core/cli/cli_launch_intent_provider.dart';
import 'package:netcrux/domain/models/app_settings.dart';
import 'package:netcrux/domain/models/custom_cell_symbol/cell_symbol_geometry.dart';
import 'package:netcrux/domain/models/layout/bounding_box.dart';
import 'package:netcrux/domain/models/layout/edge_route.dart';
import 'package:netcrux/domain/models/layout/netlist_layout.dart';
import 'package:netcrux/domain/models/layout/node_position.dart';
import 'package:netcrux/domain/models/netlist/module.dart';
import 'package:netcrux/domain/models/workspace/netcrux_tab_payload.dart';
import 'package:netcrux/features/remote/providers/cxp_server_provider.dart';
import 'package:netcrux/features/settings/providers/app_settings_provider.dart';
import 'package:netcrux/services/layout/elk_layout_service.dart';
import 'package:netcrux/services/layout/elk_layout_service_provider.dart';
import 'package:netcrux/services/remote/cxp/netcrux_cxp_server.dart';
import 'package:netcrux/services/settings/netcrux_settings_codec.dart';
import 'package:netcrux/services/workspace/netcrux_pane_overrides.dart';
import 'package:netcrux/services/workspace/netcrux_tab_overrides.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_codec.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_notifier.dart';
import 'package:netcrux/services/workspace/tab_container_manager_holder.dart';
import 'package:netcrux/services/yosys/yosys_availability_provider.dart';
import 'package:netcrux/shared/widgets/workspace_managers_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_boot_overrides.dart';

/// Lays every cell out in a row without elkjs, which has no JS runtime under
/// `flutter test` — and whose real isolate would outlive the test.
class RowLayoutService extends ElkLayoutService {
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

/// No CXP server: a real one binds a socket and writes a discovery manifest.
class _NullCxpServerHost extends CxpServerHost {
  @override
  Future<NetcruxCxpServer?> build() async => null;
}

/// The real `NetcruxApp`, booted the way `bootstrap()` wires it, for tests
/// that drive a launch path end to end and read what landed in the tab.
class WorkspaceAppHarness {
  WorkspaceAppHarness._(this.root, this.tabs);

  /// The root container.
  final ProviderContainer root;

  /// The per-tab container manager.
  final TabContainerManager tabs;

  /// The active tab's container. Fails the test when no tab is open.
  ProviderContainer get activeTab {
    final id = root.read(netcruxWorkspaceProvider).value?.activeTabId;
    expect(id, isNotNull, reason: 'a tab must have been opened');
    return tabs.containerFor(id!);
  }

  /// Boots the app with [intent] as the launch intent. [overrides] spread
  /// last, so they win. The workspace saved in [workspaceDirectory] is
  /// restored when one is given; otherwise nothing is. No CXP server starts,
  /// layout is [RowLayoutService], and Yosys is reported missing unless an
  /// override says otherwise. [preferences] seeds the mock
  /// `SharedPreferences`; pass [kEulaAcceptedPrefs] in it for a test that taps
  /// through the app, or the agreement's barrier swallows the taps.
  /// [sourcePollInterval] is the source files' poll (see
  /// `sourceFilePollIntervalProvider`); off unless a test is about reloading.
  static Future<WorkspaceAppHarness> boot(
    WidgetTester tester, {
    CliLaunchIntent intent = const CliLaunchIntent.empty(),
    List<Override> overrides = const <Override>[],
    Directory? workspaceDirectory,
    Map<String, Object> preferences = const <String, Object>{},
    Duration? sourcePollInterval,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues(preferences);
    final prefs = await SharedPreferences.getInstance();
    final root = ProviderContainer(
      overrides: <Override>[
        ...netcruxAppTestOverrides(sourcePollInterval: sourcePollInterval),
        cliLaunchIntentProvider.overrideWithValue(intent),
        cxpServerHostProvider.overrideWith(_NullCxpServerHost.new),
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
                  workspaceDirectory ??
                  Directory.systemTemp.createTempSync('netcrux_harness_ws_'),
              logger: (_) {},
            ),
            autoSaveDebounce: const Duration(milliseconds: 50),
            // Restores exactly when the test supplied a workspace to restore.
            restoreGate: () async => workspaceDirectory != null,
          ),
        ),
        yosysAvailabilityProvider.overrideWith(
          (ref) async => const YosysAvailability.notFound(reason: 'test stub'),
        ),
        elkLayoutServiceProvider.overrideWithValue(RowLayoutService()),
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
    await settle(tester);
    return WorkspaceAppHarness._(root, tabs);
  }

  /// Lets post-frame launch handlers run their real file reads to completion.
  static Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Unmounts the app and runs out the snackbar and autosave timers it left,
  /// which the test binding otherwise reports as pending.
  static Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 30));
  }
}
