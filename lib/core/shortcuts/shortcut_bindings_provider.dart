// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_keybindings/crux_keybindings.dart';
import 'package:flutter/widgets.dart';
import 'package:logging/logging.dart';
import 'package:netcrux/core/shortcuts/netcrux_action.dart';
import 'package:netcrux/core/shortcuts/shortcut_bindings.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'shortcut_bindings_provider.g.dart';

final _log = Logger('netcrux.shortcuts');

/// Provides the [KeyBindingsStore] used to persist customizations, configured
/// with NetCrux's action set + schema (`netCruxKeymapCodec`).
///
/// Override in tests to inject a `SharedPreferences`-backed store.
@Riverpod(keepAlive: true)
KeyBindingsStore<NetcruxAction> shortcutBindingsStore(Ref ref) =>
    KeyBindingsStore<NetcruxAction>(codec: netCruxKeymapCodec);

/// Manages the active key bindings for every [NetcruxAction].
///
/// Seeded synchronously from [defaultBindings] so consumers never see a null
/// map, then persisted customizations are overlaid asynchronously once they
/// load from [KeyBindingsStore]. Customizations are stored as **diffs from
/// default** (see [currentDiffs]).
@Riverpod(keepAlive: true)
class ShortcutBindings extends _$ShortcutBindings {
  bool _disposed = false;

  /// Set when the stored keymap was written by a newer build. Every save is
  /// then skipped for the rest of the session: this build's diffs would
  /// replace a keymap it cannot read, wiping the user's bindings for the day
  /// they upgrade again.
  bool _storedKeymapIsNewer = false;

  @override
  Map<NetcruxAction, ShortcutActivator> build() {
    ref.onDispose(() => _disposed = true);
    unawaited(_restore());
    return defaultBindings();
  }

  Future<void> _restore() async {
    final Map<NetcruxAction, KeyBinding?> diffs;
    try {
      diffs = await ref.read(shortcutBindingsStoreProvider).load();
    } on KeymapSchemaVersionException catch (e) {
      // The store answers every other failure with "no customizations"; this
      // one it refuses loudly so the caller can decline to overwrite it.
      _storedKeymapIsNewer = true;
      _log.warning(
        'Stored keyboard shortcuts come from a newer NetCrux (${e.message}); '
        'running on defaults and leaving them unsaved this session',
      );
      return;
    }
    if (_disposed || diffs.isEmpty) return;
    state = KeyBindingResolver.resolve(defaultBindings(), diffs);
  }

  /// The current customizations as diffs against the platform defaults
  /// (including explicit unbinds). Persisted and written by keymap Export.
  Map<NetcruxAction, KeyBinding?> currentDiffs() => KeyBindingResolver.diff(
    NetcruxAction.values,
    state,
    defaultBindings(),
  );

  void _persist() {
    if (_storedKeymapIsNewer) return;
    unawaited(ref.read(shortcutBindingsStoreProvider).save(currentDiffs()));
  }

  /// Sets a custom binding for [action], replacing the current activator.
  void setBinding(NetcruxAction action, ShortcutActivator activator) {
    state = Map<NetcruxAction, ShortcutActivator>.of(state)
      ..[action] = activator;
    _persist();
  }

  /// Removes any binding for [action] (an explicit unbind). No-op when the
  /// action is already unbound.
  void unbind(NetcruxAction action) {
    if (!state.containsKey(action)) return;
    state = Map<NetcruxAction, ShortcutActivator>.of(state)..remove(action);
    _persist();
  }

  /// Resets [action] to its platform default (or unbinds it if it has none).
  void reset(NetcruxAction action) {
    final updated = Map<NetcruxAction, ShortcutActivator>.of(state);
    final defaultActivator = defaultBindings()[action];
    if (defaultActivator == null) {
      updated.remove(action);
    } else {
      updated[action] = defaultActivator;
    }
    state = updated;
    _persist();
  }

  /// Resets every binding to its default and clears persisted overrides.
  void resetAll() {
    state = defaultBindings();
    _persist();
  }

  /// Replaces all customizations with [diffs] (keymap Import).
  void importDiffs(Map<NetcruxAction, KeyBinding?> diffs) {
    state = KeyBindingResolver.resolve(defaultBindings(), diffs);
    _persist();
  }

  /// Replaces all bindings with a named preset's complete map (selected in
  /// Settings → Keyboard Shortcuts).
  ///
  /// The delta from the platform defaults is persisted via [currentDiffs], so a
  /// preset that equals the defaults stores nothing and one that diverges
  /// stores only its overrides — identical to the Import path. The user can
  /// still edit individual rows afterward.
  void applyPreset(Map<NetcruxAction, ShortcutActivator> preset) {
    state = Map<NetcruxAction, ShortcutActivator>.of(preset);
    _persist();
  }
}
