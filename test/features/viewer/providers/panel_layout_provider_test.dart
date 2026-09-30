// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_settings/crux_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/app_settings.dart';
import 'package:netcrux/domain/models/panel_layout_state.dart';
import 'package:netcrux/features/settings/providers/app_settings_provider.dart';
import 'package:netcrux/features/viewer/providers/panel_layout_provider.dart';
import 'package:netcrux/services/settings/netcrux_settings_codec.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _makeContainer() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      settingsServiceProvider.overrideWithValue(
        SettingsService<AppSettings>(
          const NetcruxSettingsCodec(),
          prefsOverride: prefs,
        ),
      ),
    ],
  );
  // Resolve the async settings load so the panel-layout notifier seeds from
  // the persisted state rather than the loading-state defaults.
  await container.read(appSettingsProvider.future);
  return container;
}

void main() {
  group('PanelLayoutNotifier', () {
    test('seeds from the model defaults on an empty store', () async {
      final container = await _makeContainer();
      addTearDown(container.dispose);
      final state = container.read(panelLayoutProvider);
      expect(state, const PanelLayoutState());
      expect(state.hierarchyTreeVisible, isTrue);
      expect(state.inspectorVisible, isFalse);
      expect(state.diagnosticsVisible, isFalse);
    });

    test('toggleInspector flips visibility and persists to settings', () async {
      final container = await _makeContainer();
      addTearDown(container.dispose);
      final notifier = container.read(panelLayoutProvider.notifier);

      await notifier.toggleInspector();

      expect(container.read(panelLayoutProvider).inspectorVisible, isTrue);
      // The change is mirrored into AppSettings (and so to disk).
      expect(
        container.read(appSettingsProvider).value!.panelLayout.inspectorVisible,
        isTrue,
      );
    });

    test(
      'toggleHierarchyTree and toggleDiagnostics flip their panes',
      () async {
        final container = await _makeContainer();
        addTearDown(container.dispose);
        final notifier = container.read(panelLayoutProvider.notifier);

        await notifier.toggleHierarchyTree();
        await notifier.toggleDiagnostics();

        final state = container.read(panelLayoutProvider);
        expect(state.hierarchyTreeVisible, isFalse);
        expect(state.diagnosticsVisible, isTrue);
      },
    );

    test('set*Visible mirrors drag-to-collapse exactly', () async {
      final container = await _makeContainer();
      addTearDown(container.dispose);
      final notifier = container.read(panelLayoutProvider.notifier);

      await notifier.setHierarchyTreeVisible(visible: false);

      expect(container.read(panelLayoutProvider).hierarchyTreeVisible, isFalse);
    });

    test('set*Width persists drag-resize sizes', () async {
      final container = await _makeContainer();
      addTearDown(container.dispose);
      final notifier = container.read(panelLayoutProvider.notifier);

      await notifier.setHierarchyTreeWidth(280);
      await notifier.setInspectorWidth(320);
      await notifier.setDiagnosticsHeight(220);

      final state = container.read(panelLayoutProvider);
      expect(state.hierarchyTreeWidth, 280);
      expect(state.inspectorWidth, 320);
      expect(state.diagnosticsHeight, 220);
    });

    test(
      'persisted layout reloads in a fresh container against the same store',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final prefs = await SharedPreferences.getInstance();
        final service = SettingsService<AppSettings>(
          const NetcruxSettingsCodec(),
          prefsOverride: prefs,
        );

        final first = ProviderContainer(
          overrides: [settingsServiceProvider.overrideWithValue(service)],
        );
        await first.read(appSettingsProvider.future);
        await first.read(panelLayoutProvider.notifier).toggleInspector();
        first.dispose();

        // A second container over the same SharedPreferences sees the saved
        // visibility once its settings finish loading.
        final second = ProviderContainer(
          overrides: [settingsServiceProvider.overrideWithValue(service)],
        );
        addTearDown(second.dispose);
        await second.read(appSettingsProvider.future);
        expect(second.read(panelLayoutProvider).inspectorVisible, isTrue);
      },
    );
  });
}
