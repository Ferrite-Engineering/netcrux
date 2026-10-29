// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/cli/cli_launch_intent.dart';
import 'package:netcrux/features/project/providers/current_project_provider.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_notifier.dart';
import 'package:path/path.dart' as p;

import '../../../helpers/workspace_app_harness.dart';

/// A source path typed on the command line is relative to the directory the
/// app was started in. Kept as typed, Save Project As wrote it verbatim and
/// the project then read it against its own folder: `netcrux_pro
/// design/top.v` saved into `design/` reopened as `design/design/top.v`.
void main() {
  testWidgets('a relative command-line source opens as an absolute path', (
    tester,
  ) async {
    final dir = Directory(
      Directory.systemTemp
          .createTempSync('netcrux_cli_relative_')
          .resolveSymbolicLinksSync(),
    );
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File(p.join(dir.path, 'top.v'))
      ..writeAsStringSync(
        'module top(input a, output y); assign y = a; endmodule\n',
      );
    final typed = p.relative(file.path);
    expect(p.isAbsolute(typed), isFalse);

    final h = await WorkspaceAppHarness.boot(
      tester,
      intent: CliLaunchIntent.openSourceFiles(<String>[typed]),
    );
    await WorkspaceAppHarness.settle(tester);

    final tab = h.root.read(netcruxWorkspaceProvider).value!.tabs.single;
    expect(tab.payload.sourceFiles, <String>[file.path]);
    expect(
      h.activeTab.read(currentProjectProvider).sourceFiles,
      <String>[file.path],
    );
  });
}
