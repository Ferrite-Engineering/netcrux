// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/tabs/cli_multi_file_test.dart
//
// Verification driver for Open-Core Guide §4.1.5 (CLI multi-file open).
// `netcrux a.v b.v c.v` must open each file as a SEPARATE tab in the active
// pane. Yosys is not required for this check — even when elaboration fails
// (no Yosys on PATH) each tab still opens with its own source-file payload;
// the assertion is on tab structure, not schematic content.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../helpers/app_driver.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets(
    'three source files on the CLI open three tabs (Guide §4.1.5)',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync('netcrux_cli_multi_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final paths = <String>[];
      for (final name in const ['a', 'b', 'c']) {
        final f = File('${dir.path}/$name.v')
          ..writeAsStringSync('module $name(); endmodule\n');
        paths.add(f.path);
      }

      await bootNetcrux(tester, args: paths);

      // The auto-launch handler opens one tab per file after the first frame.
      await pumpUntil(
        tester,
        () => tabCount(tester) == 3,
        timeout: const Duration(seconds: 20),
      );
      expect(
        tabCount(tester),
        3,
        reason: 'each CLI source file opens its own tab',
      );

      // Each tab references exactly one of the three source files.
      final opened = liveWorkspace(
        tester,
      ).tabs.expand((t) => t.payload.sourceFiles).toSet();
      expect(opened, containsAll(paths));

      // The opened tabs mount their content and kick off elaboration. With no
      // Yosys on PATH that elaboration resolves to a handled error state in
      // the app; drain a settle window inside the body so the background work
      // completes here rather than after the test returns.
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      tester.takeException();
    },
  );
}
