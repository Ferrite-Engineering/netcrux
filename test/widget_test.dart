// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_settings/crux_settings.dart';
import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/app.dart';
import 'package:netcrux/domain/models/app_settings.dart';
import 'package:netcrux/domain/models/workspace/netcrux_tab_payload.dart';
import 'package:netcrux/features/settings/providers/app_settings_provider.dart';
import 'package:netcrux/services/settings/netcrux_settings_codec.dart';
import 'package:netcrux/services/workspace/netcrux_pane_overrides.dart';
import 'package:netcrux/services/workspace/netcrux_tab_overrides.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_codec.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_notifier.dart';
import 'package:netcrux/shared/widgets/workspace_managers_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/app_boot_overrides.dart';

Future<Widget> _bootApp() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final root = ProviderContainer(
    overrides: [
      // The two crux_shared packages NetcruxApp mounts from
      // MaterialApp.builder ship throwing defaults; without these the app
      // fails to build with an unrelated-looking provider exception.
      ...netcruxAppTestOverrides(),
      settingsServiceProvider.overrideWithValue(
        SettingsService<AppSettings>(
          const NetcruxSettingsCodec(),
          prefsOverride: prefs,
        ),
      ),
      // Use an in-memory workspace service so the test never touches the
      // host's getApplicationSupportDirectory().
      netcruxWorkspaceProvider.overrideWith(
        () => NetcruxWorkspaceNotifier(
          service: WorkspaceService<NetcruxTabPayload>(
            codec: const NetcruxWorkspaceCodec(),
            directoryFactory: () async =>
                Directory.systemTemp.createTempSync('netcrux_widget_test_'),
            logger: (_) {},
          ),
          autoSaveDebounce: const Duration(milliseconds: 50),
        ),
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
  return UncontrolledProviderScope(
    container: root,
    child: WorkspaceManagersScope(
      tabContainerManager: tabs,
      paneContainerManager: panes,
      child: const NetcruxApp(),
    ),
  );
}

void main() {
  testWidgets('NetcruxApp boots and renders the workspace empty-canvas state', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(await _bootApp());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // The empty-canvas state renders its headline. (There is no in-window
    // title AppBar — the OS window chrome carries the app name.)
    expect(find.text('Welcome to NetCrux'), findsOneWidget);
  });

  testWidgets(
    'workspace body fills the screen (regression: Stack 0x0 collapse)',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(await _bootApp());
      await tester.pumpAndSettle();

      // Before the fix the workspace body was a Stack whose only
      // non-positioned child was the invisible 0x0 CXP emitter, collapsing
      // the Stack — and the Positioned.fill PaneHost — to 0x0 (a black
      // screen on launch). The PaneHost must fill the Scaffold body.
      final paneHostSize = tester.getSize(
        find.byType(PaneHost<NetcruxTabPayload>),
      );
      expect(paneHostSize.width, greaterThan(1000));
      expect(paneHostSize.height, greaterThan(500));
    },
  );

  testWidgets(
    'NetcruxApp uses Material 3 dark theme by default',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(await _bootApp());
      await tester.pumpAndSettle();

      final BuildContext context = tester.element(find.byType(Scaffold));
      final theme = Theme.of(context);
      expect(theme.useMaterial3, isTrue);
      expect(theme.brightness, Brightness.dark);
    },
  );

  testWidgets(
    'NetcruxApp wires high-contrast light and dark themes into MaterialApp',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(await _bootApp());
      await tester.pumpAndSettle();

      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      // Both accessibility themes are supplied so the OS "increase contrast"
      // setting hardens the chrome instead of falling back to the base theme.
      expect(app.highContrastTheme, isNotNull);
      expect(app.highContrastDarkTheme, isNotNull);
      expect(app.highContrastTheme!.brightness, Brightness.light);
      expect(app.highContrastDarkTheme!.brightness, Brightness.dark);
      // The hardened outline distinguishes the high-contrast dark theme from
      // the base dark theme.
      expect(
        app.highContrastDarkTheme!.colorScheme.outline,
        isNot(app.darkTheme!.colorScheme.outline),
      );
    },
  );
}
