// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/remote_control/cxp_server_lifecycle_test.dart
//
// Verification driver for Open-Core Guide §6.1 (CXP server lifecycle). With
// the CXP setting on (the default) the app starts the CXP runtime at boot;
// flipping the Settings → CXP Cross-Probe toggle tears it down and back up.
// This drives the real shared `cruxCxpRuntimeProvider` + `cruxCxpSettingsProvider`
// through a live app rather than a bare ProviderContainer.

import 'package:crux_cxp_ui/crux_cxp_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../helpers/app_driver.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets(
    'CXP server starts at boot and toggles with the setting (Guide §6.1)',
    (tester) async {
      await bootNetcrux(tester);
      final root = rootContainer(tester);

      // Default settings enable the server — the runtime provider resolves to
      // a live CruxCxpRuntime.
      final runtime = await root.read(cruxCxpRuntimeProvider.future);
      expect(
        runtime,
        isNotNull,
        reason: 'the CXP setting defaults to on → the runtime is constructed',
      );
      // Either it bound a port (isAvailable) or it degraded gracefully with a
      // reason — never a hard crash. On a clean macOS test host it binds.
      expect(
        runtime!.isAvailable || runtime.unavailableReason != null,
        isTrue,
        reason: 'server either runs or records why it could not bind',
      );

      // Disable CXP — the runtime tears down to null.
      await root
          .read(cruxCxpSettingsProvider.notifier)
          .setEnabled(enabled: false);
      final disabled = await root.read(cruxCxpRuntimeProvider.future);
      expect(
        disabled,
        isNull,
        reason: 'disabling the setting stops the server',
      );

      // Re-enable — a fresh runtime is constructed.
      await root
          .read(cruxCxpSettingsProvider.notifier)
          .setEnabled(enabled: true);
      final reenabled = await root.read(cruxCxpRuntimeProvider.future);
      expect(
        reenabled,
        isNotNull,
        reason: 're-enabling the setting restarts the server',
      );

      expect(tester.takeException(), isNull);
    },
  );
}
