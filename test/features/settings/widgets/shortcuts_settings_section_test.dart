// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_keybindings/crux_keybindings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/shortcuts/keymap_presets.dart';
import 'package:netcrux/core/shortcuts/netcrux_action.dart';
import 'package:netcrux/core/shortcuts/shortcut_bindings.dart';
import 'package:netcrux/core/shortcuts/shortcut_bindings_provider.dart';
import 'package:netcrux/features/settings/widgets/shortcuts_settings_section.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<SharedPreferences> freshPrefs() async {
    SharedPreferences.setMockInitialValues({});
    return await SharedPreferences.getInstance();
  }

  Widget wrap(SharedPreferences prefs, {Locale locale = const Locale('en')}) =>
      ProviderScope(
        overrides: [
          shortcutBindingsStoreProvider.overrideWithValue(
            KeyBindingsStore<NetcruxAction>(
              codec: netCruxKeymapCodec,
              prefsOverride: prefs,
            ),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: L10N.localizationsDelegates,
          supportedLocales: L10N.supportedLocales,
          locale: locale,
          home: const Scaffold(
            body: SingleChildScrollView(child: ShortcutsSettingsSection()),
          ),
        ),
      );

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(
        tester.element(find.byType(ShortcutsSettingsSection)),
        listen: false,
      );

  testWidgets('renders the editor rows and controls', (tester) async {
    await tester.pumpWidget(wrap(await freshPrefs()));
    await tester.pumpAndSettle();

    expect(find.byType(KeyBindingRow), findsWidgets);
    expect(find.text('Import…'), findsOneWidget);
    expect(find.text('Export…'), findsOneWidget);
    expect(find.text('Reset all'), findsOneWidget);
  });

  testWidgets(
    "conflict warning is asymmetric: only the shadowed row says it won't "
    'fire',
    (tester) async {
      await tester.pumpWidget(wrap(await freshPrefs()));
      await tester.pumpAndSettle();

      // Remap zoomIn onto zoomOut's chord: zoomIn is the customized interloper
      // (wins); zoomOut is the default owner (shadowed).
      final zoomOut = containerOf(
        tester,
      ).read(shortcutBindingsProvider)[NetcruxAction.zoomOut]!;
      containerOf(tester)
          .read(shortcutBindingsProvider.notifier)
          .setBinding(NetcruxAction.zoomIn, zoomOut);
      await tester.pump();

      expect(find.textContaining('shadowed by'), findsOneWidget);
      expect(find.textContaining('Takes precedence over'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsWidgets);
    },
  );

  testWidgets('conflict summary banner shows the count', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(await freshPrefs()));
    await tester.pumpAndSettle();

    expect(find.textContaining('needs attention'), findsNothing);

    final zoomOut = containerOf(
      tester,
    ).read(shortcutBindingsProvider)[NetcruxAction.zoomOut]!;
    containerOf(tester)
        .read(shortcutBindingsProvider.notifier)
        .setBinding(NetcruxAction.zoomIn, zoomOut);
    await tester.pump();

    expect(find.text('1 shortcut conflict needs attention'), findsOneWidget);
  });

  testWidgets('preset dropdown defaults to NetCrux (Default)', (tester) async {
    await tester.pumpWidget(wrap(await freshPrefs()));
    await tester.pumpAndSettle();

    expect(find.text('Preset'), findsOneWidget);
    expect(find.text('NetCrux (Default)'), findsOneWidget);
    expect(find.text('Custom'), findsNothing);
  });

  testWidgets('preset dropdown shows Custom after a hand edit', (tester) async {
    await tester.pumpWidget(wrap(await freshPrefs()));
    await tester.pumpAndSettle();

    containerOf(tester)
        .read(shortcutBindingsProvider.notifier)
        .setBinding(
          NetcruxAction.zoomIn,
          const SingleActivator(LogicalKeyboardKey.keyJ, control: true),
        );
    await tester.pump();

    expect(find.text('Custom'), findsOneWidget);
  });

  testWidgets('selecting the NetCrux preset restores the defaults wholesale', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(await freshPrefs()));
    await tester.pumpAndSettle();

    final notifier = containerOf(tester).read(shortcutBindingsProvider.notifier)
      ..setBinding(
        NetcruxAction.zoomIn,
        const SingleActivator(LogicalKeyboardKey.keyJ, control: true),
      );
    await tester.pump();
    expect(find.text('Custom'), findsOneWidget);

    // Open the dropdown (showing the "Custom" hint) and pick the preset.
    // Tap the button widget, not the hint Text: the hint is rendered inside
    // the button's IndexedStack and its own center may not hit-test.
    await tester.tap(find.byType(DropdownButton<KeymapPreset>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('NetCrux (Default)').last);
    await tester.pumpAndSettle();

    expect(notifier.currentDiffs(), isEmpty);
    expect(find.text('NetCrux (Default)'), findsOneWidget);
    expect(find.text('Custom'), findsNothing);
  });

  group('locale sweep', () {
    for (final locale in const [
      Locale('en'),
      Locale('zh', 'CN'),
      Locale('ja'),
      Locale('ko'),
    ]) {
      testWidgets('renders without exceptions in $locale', (tester) async {
        await tester.pumpWidget(wrap(await freshPrefs(), locale: locale));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(KeyBindingRow), findsWidgets);
      });
    }
  });
}
