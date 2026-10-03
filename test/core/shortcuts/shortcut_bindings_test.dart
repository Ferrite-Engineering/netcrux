// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_keybindings/crux_keybindings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/shortcuts/netcrux_action.dart';
import 'package:netcrux/core/shortcuts/shortcut_bindings.dart';

bool _has(
  Map<ShortcutActivator, NetcruxAction> table,
  ShortcutActivator activator,
  NetcruxAction action,
) => table.entries.any(
  (entry) =>
      entry.value == action &&
      KeyBindingResolver.activatorsEqual(entry.key, activator),
);

void main() {
  group('defaultBindings', () {
    test('binds Zoom to Selection to bare Z, the WaveCrux key', () {
      final z = defaultBindings()[NetcruxAction.zoomToSelection];
      expect(
        KeyBindingResolver.activatorsEqual(
          z,
          const SingleActivator(LogicalKeyboardKey.keyZ),
        ),
        isTrue,
      );
    });

    test('no other action holds bare Z', () {
      final holders = defaultBindings().entries.where(
        (entry) => KeyBindingResolver.activatorsEqual(
          entry.value,
          const SingleActivator(LogicalKeyboardKey.keyZ),
        ),
      );
      expect(holders.map((entry) => entry.key), [
        NetcruxAction.zoomToSelection,
      ]);
    });

    test('no alias collides with any default binding', () {
      final defaults = defaultBindings().values.toList();
      for (final aliases in defaultBindingAliases().values) {
        for (final alias in aliases) {
          expect(
            defaults.any((d) => KeyBindingResolver.activatorsEqual(d, alias)),
            isFalse,
            reason: '$alias',
          );
        }
      }
    });
  });

  group('activatorsWithAliases', () {
    test('adds the plus and numpad forms of Zoom In to the defaults', () {
      final table = activatorsWithAliases(defaultBindings());
      for (final activator in const [
        SingleActivator(LogicalKeyboardKey.equal, control: true),
        SingleActivator(LogicalKeyboardKey.add, control: true),
        SingleActivator(LogicalKeyboardKey.add, control: true, shift: true),
        SingleActivator(LogicalKeyboardKey.equal, control: true, shift: true),
        SingleActivator(LogicalKeyboardKey.numpadAdd, control: true),
      ]) {
        expect(_has(table, activator, NetcruxAction.zoomIn), isTrue);
      }
      expect(
        _has(
          table,
          const SingleActivator(
            LogicalKeyboardKey.numpadSubtract,
            control: true,
          ),
          NetcruxAction.zoomOut,
        ),
        isTrue,
      );
    });

    test('uses Cmd on macOS', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final table = activatorsWithAliases(defaultBindings());
      expect(
        _has(
          table,
          const SingleActivator(LogicalKeyboardKey.add, meta: true),
          NetcruxAction.zoomIn,
        ),
        isTrue,
      );
    });

    test('drops the aliases of an action moved off its default', () {
      final bindings = defaultBindings()
        ..[NetcruxAction.zoomIn] = const SingleActivator(
          LogicalKeyboardKey.keyK,
          control: true,
        );
      final table = activatorsWithAliases(bindings);
      expect(
        table.values.where((action) => action == NetcruxAction.zoomIn),
        hasLength(1),
      );
    });

    test('never takes a chord another action holds', () {
      const taken = SingleActivator(
        LogicalKeyboardKey.add,
        control: true,
      );
      final bindings = defaultBindings()..[NetcruxAction.openSearch] = taken;
      final table = activatorsWithAliases(bindings);
      expect(_has(table, taken, NetcruxAction.openSearch), isTrue);
      expect(_has(table, taken, NetcruxAction.zoomIn), isFalse);
    });

    test('drops the aliases of an unbound action', () {
      final bindings = defaultBindings()..remove(NetcruxAction.zoomIn);
      final table = activatorsWithAliases(bindings);
      expect(table.values, isNot(contains(NetcruxAction.zoomIn)));
    });
  });
}
