// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/shortcuts/netcrux_action.dart';
import 'package:netcrux/core/shortcuts/netcrux_action_context.dart';
import 'package:netcrux/features/command_palette/widgets/command_palette_dialog.dart';
import 'package:netcrux/features/workspace/providers/netcrux_action_context_provider.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

/// Keyboard execution in the command palette.
///
/// Enter reaches the palette by two independent routes and only one of them
/// is reproducible with `tester.sendKeyEvent`: on every platform whose engine
/// owns the focused field's text-input connection, a real Enter arrives as a
/// `TextInputAction.done` on the *text-input channel* and the framework never
/// sees a key event. That is why the shipped defect — Enter did nothing,
/// clicking the row worked — survived a green widget-test suite. Both routes
/// are driven here.
///
/// The behaviour lives in `package:crux_command_palette`;
/// [CommandPaletteDialog] is a delegating wrapper. These tests pin NetCrux's
/// end of that contract so a future wrapper change (a `Focus` of its own, an
/// intercepting shortcut) that re-breaks keyboard execution fails here.
void main() {
  /// Pumps the palette as a modal route over a host page and returns the
  /// actions it dispatched.
  Future<List<NetcruxAction>> showPalette(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
  }) async {
    final dispatched = <NetcruxAction>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          netcruxActionContextProvider.overrideWithValue(
            const NetcruxActionContext(
              hasOpenTab: true,
              hasNetlist: true,
              hasSelection: true,
            ),
          ),
        ],
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: L10N.localizationsDelegates,
          supportedLocales: L10N.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => CommandPaletteDialog.show(
                    context,
                    onAction: dispatched.add,
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return dispatched;
  }

  Future<void> typeQuery(WidgetTester tester, String query) async {
    await tester.enterText(find.byType(TextField), query);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'a text-input done action executes the highlighted row',
    (tester) async {
      final l10n = await L10N.delegate.load(const Locale('en'));
      const target = NetcruxAction.splitPaneRight;
      final dispatched = await showPalette(tester);
      await typeQuery(tester, target.label(l10n));

      // The delivery path a real Enter takes in a shipped desktop build.
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(dispatched, [target]);
      expect(find.byType(TextField), findsNothing, reason: 'palette stayed up');
    },
  );

  testWidgets('a framework Enter key event executes it too', (tester) async {
    final l10n = await L10N.delegate.load(const Locale('en'));
    const target = NetcruxAction.splitPaneRight;
    final dispatched = await showPalette(tester);
    await typeQuery(tester, target.label(l10n));

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(dispatched, [target]);
  });

  testWidgets('a platform delivering both signals dispatches once', (
    tester,
  ) async {
    final l10n = await L10N.delegate.load(const Locale('en'));
    const target = NetcruxAction.splitPaneRight;
    final dispatched = await showPalette(tester);
    await typeQuery(tester, target.label(l10n));

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(dispatched, [target]);
    // A second pop would have taken the host page with it.
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('arrow keys move the highlight, Enter runs what is shown', (
    tester,
  ) async {
    final dispatched = await showPalette(tester);
    await typeQuery(tester, 'pane');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(dispatched, hasLength(1));
    // The query field must not have absorbed the arrow key as caret motion.
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('Escape closes without dispatching', (tester) async {
    final dispatched = await showPalette(tester);
    await typeQuery(tester, 'pane');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(dispatched, isEmpty);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  group('locale sweep', () {
    for (final locale in L10N.supportedLocales) {
      testWidgets('Enter executes in ${locale.toLanguageTag()}', (
        tester,
      ) async {
        final l10n = await L10N.delegate.load(locale);
        const target = NetcruxAction.splitPaneRight;
        final dispatched = await showPalette(tester, locale: locale);
        await typeQuery(tester, target.label(l10n));

        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();

        expect(dispatched, [target]);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
