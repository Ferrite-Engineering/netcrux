// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/shortcuts/netcrux_action.dart';
import 'package:netcrux/core/shortcuts/netcrux_action_context.dart';
import 'package:netcrux/core/shortcuts/shortcut_bindings_provider.dart';
import 'package:netcrux/core/shortcuts/shortcut_manager_widget.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

/// Fanin / fanout are selection-seeded, so drive the harness with a
/// context where they are enabled unless the test is exercising the
/// disabled path. Injected through the same `actionContextResolver`
/// parameter the workspace shell wires to the shared context provider.
const _enabledContext = NetcruxActionContext(
  hasOpenTab: true,
  hasNetlist: true,
  hasSelection: true,
);

Widget _app({
  required Map<NetcruxAction, VoidCallback> handlers,
  NetcruxActionContext actionContext = _enabledContext,
}) => ProviderScope(
  child: MaterialApp(
    localizationsDelegates: L10N.localizationsDelegates,
    supportedLocales: L10N.supportedLocales,
    home: ShortcutManagerWidget(
      handlers: handlers,
      actionContextResolver: () => actionContext,
      child: const Focus(autofocus: true, child: SizedBox.expand()),
    ),
  ),
);

void main() {
  group('ShortcutManagerWidget — conflict precedence', () {
    testWidgets(
      'a freshly remapped (customized) action wins the chord it collides with',
      (tester) async {
        var faninFired = false;
        var fanoutFired = false;
        await tester.pumpWidget(
          _app(
            handlers: {
              NetcruxAction.showFanin: () => faninFired = true,
              NetcruxAction.showFanout: () => fanoutFired = true,
            },
          ),
        );
        await tester.pump();

        // showFanin holds '[' by default. Remap showFanout ONTO '[', creating a
        // collision where showFanout is the customized interloper.
        final container = ProviderScope.containerOf(
          tester.element(find.byType(ShortcutManagerWidget)),
        );
        container
            .read(shortcutBindingsProvider.notifier)
            .setBinding(
              NetcruxAction.showFanout,
              const SingleActivator(LogicalKeyboardKey.bracketLeft),
            );
        await tester.pump();

        await tester.sendKeyEvent(LogicalKeyboardKey.bracketLeft);
        await tester.pump();

        // The user's remap fires; the default owner is shadowed (does not fire).
        // Previously enum-declaration order decided this silently.
        expect(fanoutFired, isTrue);
        expect(faninFired, isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('ShortcutManagerWidget — descriptor enablement gates the keyboard', () {
    testWidgets(
      'a chord bound to a disabled action does not dispatch; the same chord '
      'dispatches once the context enables it',
      (tester) async {
        var faninFired = false;
        final handlers = {NetcruxAction.showFanin: () => faninFired = true};

        // Empty workspace: showFanin is selection-seeded and disabled.
        await tester.pumpWidget(
          _app(handlers: handlers, actionContext: const NetcruxActionContext()),
        );
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.bracketLeft);
        await tester.pump();
        expect(
          faninFired,
          isFalse,
          reason: 'the keyboard path must gate on descriptor enablement',
        );

        // Same chord, enabling context: the handler fires.
        await tester.pumpWidget(_app(handlers: handlers));
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.bracketLeft);
        await tester.pump();
        expect(faninFired, isTrue);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('a chord bound to an action hidden in the browser is inert', (
      tester,
    ) async {
      var openFired = false;
      await tester.pumpWidget(
        _app(
          handlers: {NetcruxAction.openSourceFiles: () => openFired = true},
          actionContext: const NetcruxActionContext(isBrowser: true),
        ),
      );
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyO);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(
        openFired,
        isFalse,
        reason: 'Open Source Files is always enabled but hidden in a browser',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('always-enabled actions dispatch regardless of context', (
      tester,
    ) async {
      var paletteFired = false;
      await tester.pumpWidget(
        _app(
          handlers: {
            NetcruxAction.openCommandPalette: () => paletteFired = true,
          },
          actionContext: const NetcruxActionContext(),
        ),
      );
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(paletteFired, isTrue);
      expect(tester.takeException(), isNull);
    });
  });

  group('ShortcutManagerWidget — Space and Enter reach the focused control', () {
    /// Binds [NetcruxAction.showFanin] to a bare [key], the shape a user
    /// remap can produce.
    Future<void> bindBare(WidgetTester tester, LogicalKeyboardKey key) async {
      ProviderScope.containerOf(
            tester.element(find.byType(ShortcutManagerWidget)),
          )
          .read(shortcutBindingsProvider.notifier)
          .setBinding(NetcruxAction.showFanin, SingleActivator(key));
      await tester.pump();
    }

    for (final MapEntry(key: name, value: key) in <String, LogicalKeyboardKey>{
      'Space': LogicalKeyboardKey.space,
      'Enter': LogicalKeyboardKey.enter,
    }.entries) {
      testWidgets(
        'a bare $name binding does not take the key from a focused button',
        (tester) async {
          var pressed = 0;
          var faninFired = false;
          await tester.pumpWidget(
            ProviderScope(
              child: MaterialApp(
                home: ShortcutManagerWidget(
                  handlers: {NetcruxAction.showFanin: () => faninFired = true},
                  actionContextResolver: () => _enabledContext,
                  child: Center(
                    child: TextButton(
                      autofocus: true,
                      onPressed: () => pressed++,
                      child: const Text('Go'),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          await bindBare(tester, key);

          await tester.sendKeyEvent(key);
          await tester.pumpAndSettle();

          expect(pressed, 1, reason: 'the focused button must activate');
          expect(faninFired, isFalse);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets(
      'the bare binding still fires where the focused widget does not activate',
      (tester) async {
        var faninFired = false;
        await tester.pumpWidget(
          _app(handlers: {NetcruxAction.showFanin: () => faninFired = true}),
        );
        await tester.pump();
        await bindBare(tester, LogicalKeyboardKey.space);

        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pump();

        expect(faninFired, isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('ShortcutManagerWidget — zoom aliases and Zoom to Selection', () {
    Future<List<NetcruxAction>> press(
      WidgetTester tester,
      Future<void> Function() keys,
    ) async {
      final fired = <NetcruxAction>[];
      await tester.pumpWidget(
        _app(
          handlers: {
            for (final action in const [
              NetcruxAction.zoomIn,
              NetcruxAction.zoomOut,
              NetcruxAction.zoomFitAll,
              NetcruxAction.zoomToSelection,
            ])
              action: () => fired.add(action),
          },
        ),
      );
      await tester.pump();
      await keys();
      await tester.pump();
      return fired;
    }

    Future<void> chord(
      WidgetTester tester,
      LogicalKeyboardKey key, {
      bool shift = false,
    }) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      // `+` has no key of its own on a US layout, so the simulator has no
      // physical key for it; on Swedish and German layouts it sits where US
      // has `-`, right of 0.
      await tester.sendKeyEvent(
        key,
        physicalKey: key == LogicalKeyboardKey.add
            ? PhysicalKeyboardKey.minus
            : null,
      );
      if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    }

    testWidgets('Ctrl plus = and Ctrl plus + both zoom in', (tester) async {
      expect(
        await press(tester, () => chord(tester, LogicalKeyboardKey.equal)),
        [NetcruxAction.zoomIn],
      );
      expect(
        await press(tester, () => chord(tester, LogicalKeyboardKey.add)),
        [NetcruxAction.zoomIn],
      );
      expect(
        await press(
          tester,
          () => chord(tester, LogicalKeyboardKey.equal, shift: true),
        ),
        [NetcruxAction.zoomIn],
      );
      expect(
        await press(tester, () => chord(tester, LogicalKeyboardKey.numpadAdd)),
        [NetcruxAction.zoomIn],
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the numpad minus and 0 zoom out and fit', (tester) async {
      expect(
        await press(
          tester,
          () => chord(tester, LogicalKeyboardKey.numpadSubtract),
        ),
        [NetcruxAction.zoomOut],
      );
      expect(
        await press(tester, () => chord(tester, LogicalKeyboardKey.numpad0)),
        [NetcruxAction.zoomFitAll],
      );
    });

    testWidgets('rebinding Zoom In drops its aliases', (tester) async {
      final fired = <NetcruxAction>[];
      await tester.pumpWidget(
        _app(
          handlers: {
            NetcruxAction.zoomIn: () => fired.add(NetcruxAction.zoomIn),
          },
        ),
      );
      await tester.pump();
      ProviderScope.containerOf(
            tester.element(find.byType(ShortcutManagerWidget)),
          )
          .read(shortcutBindingsProvider.notifier)
          .setBinding(
            NetcruxAction.zoomIn,
            const SingleActivator(LogicalKeyboardKey.keyK, control: true),
          );
      await tester.pump();
      await chord(tester, LogicalKeyboardKey.add);
      await tester.pump();
      expect(fired, isEmpty);
      await chord(tester, LogicalKeyboardKey.keyK);
      await tester.pump();
      expect(fired, [NetcruxAction.zoomIn]);
    });

    testWidgets('bare Z is Zoom to Selection', (tester) async {
      expect(
        await press(tester, () => tester.sendKeyEvent(LogicalKeyboardKey.keyZ)),
        [NetcruxAction.zoomToSelection],
      );
    });

    testWidgets('bare Z types into a focused text field', (tester) async {
      var fired = false;
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: ShortcutManagerWidget(
              handlers: {NetcruxAction.zoomToSelection: () => fired = true},
              actionContextResolver: () => _enabledContext,
              child: Material(
                child: TextField(controller: controller, autofocus: true),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.pump();
      expect(fired, isFalse);
    });
  });
}
