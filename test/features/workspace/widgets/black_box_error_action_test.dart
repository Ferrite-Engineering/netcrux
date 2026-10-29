// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_settings/crux_settings.dart';
import 'package:crux_telemetry/crux_telemetry.dart';
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
import 'package:netcrux/domain/models/workspace/netcrux_tab_payload.dart';
import 'package:netcrux/features/project/providers/current_project_provider.dart';
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
import 'package:netcrux/services/yosys/yosys_runner_provider.dart';
import 'package:netcrux/shared/widgets/workspace_managers_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/app_boot_overrides.dart';

/// The schematic error view's "Show missing modules as black boxes", in the
/// running app: a design whose elaboration stops on a missing module shows
/// the action, and the action turns the option on for the tab's project
/// (which elaborates again, now without `-check`) and in the tab's payload
/// (so it survives a restart).

class _Picker extends FileOpenService {
  _Picker(this.paths);

  final List<String> paths;

  @override
  Future<FileOpenResult> pickSourceFiles({required String dialogTitle}) async {
    return FileOpenResult(paths);
  }
}

/// Fails as `hierarchy -check` does on a missing module; elaborates an
/// empty top once the request allows undefined modules.
class _Runner extends YosysRunner {
  final List<YosysRunRequest> requests = <YosysRunRequest>[];

  @override
  Future<YosysRunResult> run(
    YosysRunRequest request, {
    Duration? timeout,
    Future<void>? cancelSignal,
    void Function(String line)? onStderrLine,
  }) async {
    requests.add(request);
    if (!request.allowUndefinedModules) {
      return const YosysRunFailure(
        exitCode: 1,
        stdout: '',
        stderr:
            r"ERROR: Module `\INV' referenced in module `\top' in cell "
            r"`\u1' is not part of the design.",
        kind: YosysFailureKind.nonZeroExit,
      );
    }
    return const YosysRunSuccess(
      rawJson:
          '{"creator":"fake","modules":{"top":{"attributes":{"top":"1"},'
          '"ports":{},"cells":{},"netnames":{}}}}',
      stdout: '',
      stderr: '',
    );
  }
}

/// Alternates real time (for file I/O) with fake-clock frames until [done]
/// holds, failing after about five seconds.
Future<void> _settleUntil(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 250 && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(done(), isTrue, reason: 'the elaboration did not settle');
}

void main() {
  testWidgets('the missing-module action turns black boxes on for the tab', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final dir = Directory.systemTemp.createTempSync('netcrux_black_box_ui_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final src = File('${dir.path}/top.v')
      ..writeAsStringSync('module top(); endmodule\n');
    final runner = _Runner();

    // Both first-launch dialogs answered, so nothing sits over the canvas.
    SharedPreferences.setMockInitialValues(<String, Object>{
      ...kEulaAcceptedPrefs,
      kTelemetryConsentKey: 'disabled',
    });
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
                  Directory.systemTemp.createTempSync('netcrux_black_box_ws_'),
              logger: (_) {},
            ),
            autoSaveDebounce: const Duration(milliseconds: 50),
          ),
        ),
        fileOpenServiceProvider.overrideWithValue(_Picker(<String>[src.path])),
        yosysAvailabilityProvider.overrideWith(
          (ref) async => const YosysAvailability.available(
            executablePath: '/fake/yosys',
            versionString: 'Yosys fake',
          ),
        ),
        yosysRunnerProvider.overrideWith((ref) => runner),
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
    await tester.pumpAndSettle();

    tester
        .widget<ShortcutManagerWidget>(find.byType(ShortcutManagerWidget))
        .handlers[NetcruxAction.openSourceFiles]!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final tabId = root.read(netcruxWorkspaceProvider).value!.activeTabId!;
    final tab = tabs.containerFor(tabId);
    final action = find.byKey(
      const ValueKey<String>('showMissingModulesAsBlackBoxes'),
    );
    // The elaboration does real file I/O (cache-key stats) between steps
    // that run on the fake clock, so let both advance until it settles.
    await _settleUntil(tester, () => action.evaluate().isNotEmpty);
    expect(action, findsOneWidget);
    expect(
      find.textContaining('which no source file or cell library defines'),
      findsOneWidget,
    );
    expect(runner.requests.single.allowUndefinedModules, isFalse);

    await tester.tap(action);
    await tester.pump();
    await _settleUntil(
      tester,
      () => tab.read(loadedNetlistProvider).hasValue,
    );

    expect(tab.read(currentProjectProvider).blackBoxMissingModules, isTrue);
    expect(runner.requests.last.allowUndefinedModules, isTrue);
    final payload = root
        .read(netcruxWorkspaceProvider)
        .value!
        .tabs
        .singleWhere((t) => t.id == tabId)
        .payload;
    expect(payload.blackBoxMissingModules, isTrue);
    expect(action, findsNothing);
    // Let the workspace autosave debounce run out before the tree goes.
    await tester.pump(const Duration(seconds: 1));
    debugDefaultTargetPlatformOverride = null;
  });
}
