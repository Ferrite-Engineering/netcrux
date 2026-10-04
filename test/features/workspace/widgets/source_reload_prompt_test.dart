// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/cli/cli_launch_intent.dart';
import 'package:netcrux/domain/models/workspace/netcrux_tab_payload.dart';
import 'package:netcrux/features/project/providers/current_project_provider.dart';
import 'package:netcrux/services/reload/source_file_watcher_provider.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_notifier.dart';
import 'package:path/path.dart' as p;

import '../../../helpers/app_boot_overrides.dart';
import '../../../helpers/workspace_app_harness.dart';

/// A real directory watch that goes deaf once it has delivered its first
/// burst, for every watch opened through it afterwards as well.
///
/// That is what `dart:io`'s macOS directory watch has been measured to do
/// (crux-shared#25): it stops delivering for the rest of the process, with no
/// error and no done event, and a new watch hears nothing either. NetCrux
/// showed one reload prompt and then never another.
class _GoesDeafAfterFirstBurst {
  DateTime? _firstEvent;

  bool get _deaf =>
      _firstEvent != null &&
      DateTime.now().difference(_firstEvent!) >
          const Duration(milliseconds: 300);

  Stream<FileSystemEvent> call(String path) =>
      Directory(File(path).parent.path).watch().where((event) {
        if (event.path != path || _deaf) return false;
        _firstEvent ??= DateTime.now();
        return true;
      });
}

/// How the tabs are laid out when the source is touched.
enum _Layout {
  /// The touched design alone.
  oneTab,

  /// A second design opened first, in the same pane.
  twoTabs,

  /// The two designs split into two panes.
  split,

  /// The split restored from `workspace.json` at launch.
  restoredSplit,
}

void main() {
  late Directory dir;
  setUp(
    () => dir = Directory(
      Directory.systemTemp
          .createTempSync('netcrux_reload_prompt_')
          .resolveSymbolicLinksSync(),
    ),
  );
  tearDown(() => dir.deleteSync(recursive: true));

  final prompt = find.textContaining('source file changed');

  /// Runs `touch` on [path] the way a user does from Terminal, then gives the
  /// watcher, its poll and the snackbar time to act.
  Future<void> touch(WidgetTester tester, String path) async {
    await tester.runAsync(() async {
      if (Platform.isWindows) {
        // No `touch` on Windows; a new modification time is the same change.
        File(path).setLastModifiedSync(DateTime.now());
      } else {
        final result = await Process.run('touch', <String>[path]);
        expect(result.exitCode, 0);
      }
      await Future<void>.delayed(const Duration(milliseconds: 1500));
    });
    await WorkspaceAppHarness.settle(tester);
    // A poll interval, the debounce, and a prompt replacing one still on
    // screen waiting out the old one's exit.
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
  }

  File source(String name) =>
      File(p.join(dir.path, '$name.v'))..writeAsStringSync(
        'module $name(input a, input b, output y); assign y = a & b; '
        'endmodule\n',
      );

  void writeRestoredSplit(Directory wsDir, File back, File front) {
    const backPane = '942ec454-bf8a-46fb-8899-a7c54187ee28';
    const frontPane = 'f0eae380-1757-404e-9565-32b87c8973e7';
    const backTab = '8fb6c128-7ce9-4f67-9a85-ef22b362e509';
    const frontTab = 'f25678c3-bab6-4876-a961-58aefad1832c';
    File(p.join(wsDir.path, 'workspace.json')).writeAsStringSync(
      jsonEncode(<String, Object?>{
        'version': 1,
        'tabs': <Object?>[
          <String, Object?>{
            'id': backTab,
            'displayName': 'vexriscv.v',
            'paneId': backPane,
            'sourceFiles': <String>[back.path],
          },
          <String, Object?>{
            'id': frontTab,
            'displayName': 'picorv32.v',
            'paneId': frontPane,
            'sourceFiles': <String>[front.path],
          },
        ],
        'panes': <Object?>[
          <String, Object?>{'id': backPane, 'activeTabId': backTab},
          <String, Object?>{'id': frontPane, 'activeTabId': frontTab},
        ],
        'activePaneId': frontPane,
        'extras': <String, Object?>{},
      }),
    );
  }

  for (final layout in _Layout.values) {
    for (final tapReload in <bool>[false, true]) {
      testWidgets('${layout.name}: every touch raises the reload prompt '
          '(${tapReload ? 'Reload tapped' : 'prompt left alone'})', (
        tester,
      ) async {
        final back = source('vexriscv');
        final front = source('picorv32');
        Directory? wsDir;
        if (layout == _Layout.restoredSplit) {
          wsDir = Directory(p.join(dir.path, 'ws'))..createSync();
          writeRestoredSplit(wsDir, back, front);
        }
        final h = await WorkspaceAppHarness.boot(
          tester,
          workspaceDirectory: wsDir,
          intent: switch (layout) {
            _Layout.restoredSplit => const CliLaunchIntent.empty(),
            _Layout.oneTab => CliLaunchIntent.openSourceFiles(<String>[
              front.path,
            ]),
            _ => CliLaunchIntent.openSourceFiles(<String>[back.path]),
          },
          overrides: [
            sourceFileWatchFactoryProvider.overrideWithValue(
              _GoesDeafAfterFirstBurst().call,
            ),
          ],
          sourcePollInterval: kSourceFilePollInterval,
          preferences: <String, Object>{
            ...kEulaAcceptedPrefs,
            kTelemetryConsentKey: 'disabled',
            // AutoReloadMode.prompt.
            'settings.autoReloadMode': 0,
          },
        );
        if (layout == _Layout.twoTabs || layout == _Layout.split) {
          await tester.runAsync(
            () => h.root
                .read(netcruxWorkspaceProvider.notifier)
                .openTab(
                  displayName: 'picorv32.v',
                  payload: NetcruxTabPayload(sourceFiles: [front.path]),
                ),
          );
          h.activeTab.read(currentProjectProvider.notifier).setSourceFiles(
            <String>[front.path],
          );
          await WorkspaceAppHarness.settle(tester);
        }
        if (layout == _Layout.split) {
          await tester.runAsync(
            () =>
                h.root.read(netcruxWorkspaceProvider.notifier).splitPaneRight(),
          );
          await WorkspaceAppHarness.settle(tester);
        }
        expect(h.activeTab.read(currentProjectProvider).sourceFiles, <String>[
          front.path,
        ]);
        expect(prompt, findsNothing);

        SnackBar? previous;
        for (var round = 1; round <= 3; round++) {
          await touch(tester, front.path);
          expect(prompt, findsOneWidget, reason: 'touch $round');
          final shown = tester.widget<SnackBar>(find.byType(SnackBar));
          expect(
            shown,
            isNot(same(previous)),
            reason: 'touch $round raised a prompt of its own',
          );
          previous = shown;
          if (tapReload) {
            await tester.tap(find.text('Reload'));
            await WorkspaceAppHarness.settle(tester);
            await tester.pump(const Duration(seconds: 2));
            expect(prompt, findsNothing, reason: 'Reload dismisses the prompt');
          }
        }

        // Close every design, so no watcher's poll outlives the test.
        for (final tab in h.root.read(netcruxWorkspaceProvider).value!.tabs) {
          h.tabs
              .containerFor(tab.id)
              .read(currentProjectProvider.notifier)
              .clear();
        }
        await WorkspaceAppHarness.unmount(tester);
      });
    }
  }
}
