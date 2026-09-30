// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_keybindings/crux_keybindings.dart';
import 'package:flutter/widgets.dart';
import 'package:netcrux/core/shortcuts/netcrux_action.dart';
import 'package:netcrux/core/shortcuts/shortcut_bindings.dart';

/// A selectable keyboard-binding preset.
///
/// A preset is a *named, complete* binding map the user can load wholesale from
/// Settings → Keyboard Shortcuts. Loading one replaces all bindings (persisted
/// as the usual diff-from-default), after which the user can still tweak
/// individual rows — at which point the active preset reads as "Custom".
///
/// Presets are an additive convenience layered on the existing
/// `.crux-keymap` import/export. NetCrux currently ships only its own
/// defaults ([netCrux]); migration presets for other schematic/netlist
/// viewers are a content decision that needs verified accelerator research
/// (the way WaveCrux's GTKWave preset was verified against `gtkwave/src/
/// menu.c`) and can be added here later without touching the mechanism.
enum KeymapPreset {
  /// NetCrux's own platform-aware defaults ([defaultBindings]).
  netCrux,
}

/// Returns the complete resolved binding map for [preset].
///
/// The result is a full `NetcruxAction → ShortcutActivator` map (same shape as
/// [defaultBindings]); apply it via `ShortcutBindings.applyPreset`.
Map<NetcruxAction, ShortcutActivator> bindingsForPreset(KeymapPreset preset) {
  switch (preset) {
    case KeymapPreset.netCrux:
      return defaultBindings();
  }
}

/// Identifies which preset [bindings] exactly matches, or `null` ("Custom")
/// when the user has diverged from every shipped preset.
///
/// Compares activators *by value* via [KeyBindingResolver.activatorsEqual] —
/// Flutter's [SingleActivator] has no `==`, so identity/`mapEquals` comparison
/// would never match two independently-built default maps.
KeymapPreset? presetForBindings(
  Map<NetcruxAction, ShortcutActivator> bindings,
) {
  for (final preset in KeymapPreset.values) {
    if (_bindingsEqual(bindingsForPreset(preset), bindings)) return preset;
  }
  return null;
}

/// Value equality for two resolved binding maps (same keys, activators equal by
/// trigger + modifiers).
bool _bindingsEqual(
  Map<NetcruxAction, ShortcutActivator> a,
  Map<NetcruxAction, ShortcutActivator> b,
) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (!b.containsKey(entry.key)) return false;
    if (!KeyBindingResolver.activatorsEqual(entry.value, b[entry.key])) {
      return false;
    }
  }
  return true;
}
