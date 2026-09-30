// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// LOCALE_SWEEP_EXEMPT: pure layout/visibility regression test (restore bars
// appear for hidden regions and reopen them); renders icons and keys, no
// localized copy is asserted.
import 'package:crux_dock/crux_dock.dart';
import 'package:crux_settings/crux_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/app_settings.dart';
import 'package:netcrux/features/settings/providers/app_settings_provider.dart';
import 'package:netcrux/features/viewer/providers/panel_layout_provider.dart';
import 'package:netcrux/features/workspace/widgets/netcrux_docks.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/settings/netcrux_settings_codec.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<ProviderContainer> pump(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsServiceProvider.overrideWithValue(
            SettingsService<AppSettings>(
              const NetcruxSettingsCodec(),
              prefsOverride: prefs,
            ),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: L10N.localizationsDelegates,
          supportedLocales: L10N.supportedLocales,
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                container = ProviderScope.containerOf(context);
                return const NetcruxDockRestoreBars(
                  child: ColoredBox(
                    color: Colors.black,
                    child: Center(child: Text('CENTER')),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await container.read(appSettingsProvider.future);
    await tester.pump();
    return container;
  }

  testWidgets('a bar appearing or vanishing keeps the wrapped layout mounted', (
    tester,
  ) async {
    // The wrapper used to pick a different widget type for each combination
    // of collapsed regions, so every dock toggle rebuilt the whole IDE layout
    // beneath it -- discarding the pane scope, dock scroll positions, and the
    // show/hide animation. Every transition below, including several regions
    // flipping in the same frame, must leave the child's element where it is.
    final container = await pump(tester);
    final notifier = container.read(panelLayoutProvider.notifier);
    await notifier.setHierarchyTreeVisible(visible: true);
    await notifier.setInspectorVisible(visible: true);
    await notifier.setDiagnosticsVisible(visible: true);
    await tester.pump();
    final center = tester.element(find.text('CENTER'));

    final combinations = [
      for (final left in [true, false])
        for (final right in [true, false])
          for (final bottom in [true, false]) (left, right, bottom),
    ];
    for (final (left, right, bottom) in [
      ...combinations,
      ...combinations.reversed,
    ]) {
      await notifier.setHierarchyTreeVisible(visible: left);
      await notifier.setInspectorVisible(visible: right);
      await notifier.setDiagnosticsVisible(visible: bottom);
      await tester.pump();
      expect(
        find.byType(CruxDockRestoreBar),
        findsNWidgets([left, right, bottom].where((v) => !v).length),
      );
      expect(
        tester.element(find.text('CENTER')),
        same(center),
        reason: 'left=$left right=$right bottom=$bottom rebuilt the child',
      );
    }
  });
}
