// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/workspace/empty_canvas_boot_test.dart
//
// Verification driver for Open-Core Guide §4.1.6 (Empty-canvas state) — the
// cold-boot smoke. Launches the real app via `bootstrap` with no CLI args and
// asserts the workspace hydrates to zero tabs and the empty-canvas state
// renders. This is also the harness smoke test: if `bootNetcrux` can stand up
// the full `MaterialApp.router` + workspace managers under the
// `integration_test` binding on a platform, the rest of the suite can too.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:netcrux/features/workspace/widgets/empty_canvas_content.dart';

import '../helpers/app_driver.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets(
    'cold boot with no args lands on the empty-canvas state (Guide §4.1.6)',
    (tester) async {
      await bootNetcrux(tester);

      // Workspace hydrated to zero tabs.
      expect(tabCount(tester), 0, reason: 'fresh boot opens no tabs');
      expect(activeTabId(tester), isNull);

      // The empty-canvas content renders with its localized headline.
      expect(find.byType(EmptyCanvasContent), findsOneWidget);
      expect(find.text('Welcome to NetCrux'), findsOneWidget);

      // No RenderFlex overflow or other exceptions during boot.
      expect(tester.takeException(), isNull);
    },
  );
}
