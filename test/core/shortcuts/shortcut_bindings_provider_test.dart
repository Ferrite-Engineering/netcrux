// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_keybindings/crux_keybindings.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:netcrux/core/shortcuts/keymap_presets.dart';
import 'package:netcrux/core/shortcuts/netcrux_action.dart';
import 'package:netcrux/core/shortcuts/shortcut_bindings.dart';
import 'package:netcrux/core/shortcuts/shortcut_bindings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // A bindable action to mutate in tests.
  final action = NetcruxAction.values.first;

  ProviderContainer persistentContainer(SharedPreferences prefs) =>
      ProviderContainer(
        overrides: [
          shortcutBindingsStoreProvider.overrideWithValue(
            KeyBindingsStore<NetcruxAction>(
              codec: netCruxKeymapCodec,
              prefsOverride: prefs,
            ),
          ),
        ],
      );

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('builds from defaultBindings', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(
      container.read(shortcutBindingsProvider),
      isNotEmpty,
    );
  });

  test('currentDiffs is empty until something changes', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(
      container.read(shortcutBindingsProvider.notifier).currentDiffs(),
      isEmpty,
    );
  });

  test('a rebind survives into a fresh container (relaunch path)', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    final first = persistentContainer(prefs);
    first
        .read(shortcutBindingsProvider.notifier)
        .setBinding(
          action,
          const SingleActivator(LogicalKeyboardKey.keyJ, control: true),
        );
    await settle();
    first.dispose();

    final second = persistentContainer(prefs);
    addTearDown(second.dispose);
    second.read(shortcutBindingsProvider); // trigger build + restore
    await settle();

    final restored =
        second.read(shortcutBindingsProvider)[action]! as SingleActivator;
    expect(restored.trigger, LogicalKeyboardKey.keyJ);
    expect(restored.control, isTrue);
  });

  test('unbind then relaunch keeps the action unbound', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    final first = persistentContainer(prefs);
    first.read(shortcutBindingsProvider.notifier).unbind(action);
    await settle();
    first.dispose();

    final second = persistentContainer(prefs);
    addTearDown(second.dispose);
    second.read(shortcutBindingsProvider);
    await settle();
    expect(
      second.read(shortcutBindingsProvider).containsKey(action),
      isFalse,
    );
  });

  test('resetAll clears persisted overrides', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    final first = persistentContainer(prefs);
    first.read(shortcutBindingsProvider.notifier)
      ..setBinding(
        action,
        const SingleActivator(LogicalKeyboardKey.keyJ, control: true),
      )
      ..resetAll();
    await settle();
    first.dispose();

    final second = persistentContainer(prefs);
    addTearDown(second.dispose);
    second.read(shortcutBindingsProvider);
    await settle();
    expect(
      second.read(shortcutBindingsProvider.notifier).currentDiffs(),
      isEmpty,
    );
  });

  test('importDiffs applies + persists a keymap', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    final first = persistentContainer(prefs);
    first.read(shortcutBindingsProvider.notifier).importDiffs({
      action: const KeyBinding(
        key: LogicalKeyboardKey.keyP,
        modifiers: {KeyModifier.mod, KeyModifier.shift},
      ),
    });
    await settle();
    first.dispose();

    final second = persistentContainer(prefs);
    addTearDown(second.dispose);
    second.read(shortcutBindingsProvider);
    await settle();
    final restored =
        second.read(shortcutBindingsProvider)[action]! as SingleActivator;
    expect(restored.trigger, LogicalKeyboardKey.keyP);
    expect(restored.shift, isTrue);
  });

  // After a downgrade the stored keymap is one this build cannot read. The
  // store refuses it by throwing rather than answering "no customizations",
  // precisely so the caller can decline to save over it. The launch restore
  // used to let that refusal escape as an uncaught error and then, on the
  // first rebind, save this build's diffs over the newer keymap.
  test('a keymap written by a newer build is refused and never '
      'overwritten', () async {
    const key = 'settings.shortcutBindings';
    const newer = '{"version": ${kKeymapVersion + 1}, "bindings": {}}';
    SharedPreferences.setMockInitialValues({key: newer});
    final prefs = await SharedPreferences.getInstance();
    final records = <LogRecord>[];
    Logger.root.level = Level.ALL;
    final sub = Logger.root.onRecord
        .where((r) => r.loggerName == 'netcrux.shortcuts')
        .listen(records.add);
    addTearDown(sub.cancel);

    final container = persistentContainer(prefs);
    addTearDown(container.dispose);
    container.read(shortcutBindingsProvider);
    await settle();

    container
        .read(shortcutBindingsProvider.notifier)
        .setBinding(
          action,
          const SingleActivator(LogicalKeyboardKey.keyJ, control: true),
        );
    await settle();

    expect(prefs.getString(key), newer);
    // The session still works, on this build's defaults plus the change.
    final current =
        container.read(shortcutBindingsProvider)[action]! as SingleActivator;
    expect(current.trigger, LogicalKeyboardKey.keyJ);
    expect(records, isNotEmpty);
    expect(records.first.level, Level.WARNING);
  });

  group('applyPreset', () {
    test('replaces the whole map with the supplied preset', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(shortcutBindingsProvider.notifier)
        // Diverge first so the preset visibly replaces a custom binding.
        ..setBinding(
          action,
          const SingleActivator(LogicalKeyboardKey.keyJ, control: true),
        );
      expect(
        presetForBindings(container.read(shortcutBindingsProvider)),
        isNull,
      );

      notifier.applyPreset(bindingsForPreset(KeymapPreset.netCrux));

      expect(
        presetForBindings(container.read(shortcutBindingsProvider)),
        KeymapPreset.netCrux,
      );
      // A preset equal to the defaults persists as an empty diff.
      expect(notifier.currentDiffs(), isEmpty);
    });

    test('persists as diff-from-default across a relaunch', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final first = persistentContainer(prefs);
      first.read(shortcutBindingsProvider.notifier)
        ..setBinding(
          action,
          const SingleActivator(LogicalKeyboardKey.keyJ, control: true),
        )
        ..applyPreset(bindingsForPreset(KeymapPreset.netCrux));
      await settle();
      first.dispose();

      final second = persistentContainer(prefs);
      addTearDown(second.dispose);
      second.read(shortcutBindingsProvider);
      await settle();
      expect(
        presetForBindings(second.read(shortcutBindingsProvider)),
        KeymapPreset.netCrux,
      );
      expect(
        second.read(shortcutBindingsProvider.notifier).currentDiffs(),
        isEmpty,
      );
    });
  });
}
