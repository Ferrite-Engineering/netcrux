// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/remote_control/cxp_server_lifecycle_test.dart
//
// Verification driver for Open-Core Guide §6.1 (CXP server lifecycle). With
// `cxpServerEnabled = true` (the default) the app starts the CXP server at
// boot; flipping the Settings → Remote Control toggle tears it down and back
// up. This drives the real `cxpServerHostProvider` + `appSettingsProvider`
// through a live app rather than a bare ProviderContainer.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:netcrux/features/remote/providers/cxp_server_provider.dart';
import 'package:netcrux/features/settings/providers/app_settings_provider.dart';

import '../helpers/app_driver.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets(
    'CXP server starts at boot and toggles with the setting (Guide §6.1)',
    (tester) async {
      await bootNetcrux(tester);
      final root = rootContainer(tester);

      // Default settings enable the server — the host provider resolves to a
      // live NetcruxCxpServer.
      final server = await root.read(cxpServerHostProvider.future);
      expect(
        server,
        isNotNull,
        reason: 'cxpServerEnabled defaults to true → server is constructed',
      );
      // Either it bound a port (isAvailable) or it degraded gracefully with a
      // reason — never a hard crash. On a clean macOS test host it binds.
      expect(
        server!.isRunning || server.unavailableReason != null,
        isTrue,
        reason: 'server either runs or records why it could not bind',
      );

      // Disable CXP — the host tears down to null.
      await root
          .read(appSettingsProvider.notifier)
          .setCxpServerEnabled(enabled: false);
      final disabled = await root.read(cxpServerHostProvider.future);
      expect(
        disabled,
        isNull,
        reason: 'disabling the setting stops the server',
      );

      // Re-enable — a fresh server is constructed.
      await root
          .read(appSettingsProvider.notifier)
          .setCxpServerEnabled(enabled: true);
      final reenabled = await root.read(cxpServerHostProvider.future);
      expect(
        reenabled,
        isNotNull,
        reason: 're-enabling the setting restarts the server',
      );

      expect(tester.takeException(), isNull);
    },
  );
}
