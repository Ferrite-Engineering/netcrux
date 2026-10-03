// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_keybindings/crux_keybindings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:netcrux/core/shortcuts/netcrux_action.dart';

/// The cross-suite [KeymapCodec] configured for NetCrux's action set and schema
/// id. Shared by the persistence store and the keymap Export/Import flow.
final KeymapCodec<NetcruxAction> netCruxKeymapCodec = KeymapCodec(
  actions: NetcruxAction.values,
  schema: 'netcrux.keymap',
);

/// Platform-aware default key bindings for every [NetcruxAction].
///
/// Uses Cmd (meta) on macOS / iOS — including iPad Magic Keyboard — and
/// Ctrl on Linux / Windows. Mirrors the WaveCrux convention so an engineer
/// switching between WaveCrux and NetCrux on the same machine encounters
/// the same modifier scheme.
Map<NetcruxAction, ShortcutActivator> defaultBindings() {
  final isMac =
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.iOS;
  SingleActivator mod(LogicalKeyboardKey key, {bool shift = false}) =>
      SingleActivator(
        key,
        meta: isMac,
        control: !isMac,
        shift: shift,
      );

  return <NetcruxAction, ShortcutActivator>{
    // ── file ──────────────────────────────────────────────────────────────
    NetcruxAction.openProject: mod(LogicalKeyboardKey.keyO),
    NetcruxAction.openSourceFiles: mod(LogicalKeyboardKey.keyO, shift: true),
    // closeTab: Cmd/Ctrl+W — the universal "close" convention and the sole
    // owner of this chord, matching WaveCrux and LintCrux (suite
    // keyboard-parity pass). closeProject moves to Cmd/Ctrl+Shift+W.
    NetcruxAction.closeTab: mod(LogicalKeyboardKey.keyW),
    NetcruxAction.closeProject: mod(LogicalKeyboardKey.keyW, shift: true),
    NetcruxAction.quit: mod(LogicalKeyboardKey.keyQ),
    // ── view ──────────────────────────────────────────────────────────────
    NetcruxAction.zoomIn: mod(LogicalKeyboardKey.equal),
    NetcruxAction.zoomOut: mod(LogicalKeyboardKey.minus),
    NetcruxAction.zoomFitAll: mod(LogicalKeyboardKey.digit0),
    // Bare Z, the key WaveCrux gives Zoom to Selection. Nothing else in
    // NetCrux binds Z, and bare keys never reach a focused text field (see
    // ShortcutManagerWidget). macOS shows no bare-letter accelerator in the
    // native menu, so the menu item there carries no key; the toolbar
    // tooltip, the command palette and the in-window menus on Windows and
    // Linux show it.
    NetcruxAction.zoomToSelection: const SingleActivator(
      LogicalKeyboardKey.keyZ,
    ),
    NetcruxAction.toggleHierarchyTree: mod(LogicalKeyboardKey.digit1),
    NetcruxAction.toggleInspector: mod(LogicalKeyboardKey.digit2),
    NetcruxAction.toggleDiagnosticsPanel: mod(LogicalKeyboardKey.digit3),
    // Cmd/Ctrl+Shift+K — theme toggle, matching WaveCrux and LintCrux
    // (suite keyboard-parity pass; toggleTheme previously shipped with no
    // default binding). No collision: no other binding uses Shift+K.
    NetcruxAction.toggleTheme: mod(LogicalKeyboardKey.keyK, shift: true),
    // ── navigate ──────────────────────────────────────────────────────────
    NetcruxAction.jumpToTop: mod(LogicalKeyboardKey.home),
    NetcruxAction.popOutScope: mod(LogicalKeyboardKey.bracketLeft),
    NetcruxAction.showFanin: const SingleActivator(
      LogicalKeyboardKey.bracketLeft,
    ),
    NetcruxAction.showFanout: const SingleActivator(
      LogicalKeyboardKey.bracketRight,
    ),
    NetcruxAction.clearOverlay: const SingleActivator(
      LogicalKeyboardKey.escape,
    ),
    // ── search / palette ──────────────────────────────────────────────────
    NetcruxAction.openSearch: mod(LogicalKeyboardKey.keyF),
    NetcruxAction.openCommandPalette: mod(LogicalKeyboardKey.keyP, shift: true),
    // ── cross-probe ───────────────────────────────────────────────────────
    // Cmd/Ctrl+Shift+X — the suite-wide Cross-Probe panel default
    // (the same chord in WaveCrux, SimCrux and LintCrux).
    // No collision: no other NetCrux binding uses Shift+X or X.
    NetcruxAction.showCrossProbePanel: mod(
      LogicalKeyboardKey.keyX,
      shift: true,
    ),
    // ── tools / help ──────────────────────────────────────────────────────
    // Tab cycling — Ctrl+Tab / Ctrl+Shift+Tab on every platform, matching
    // LintCrux and SimCrux (and browsers / VS Code). Not Cmd-based on macOS:
    // Cmd+Tab is the OS app switcher.
    NetcruxAction.nextTab: const SingleActivator(
      LogicalKeyboardKey.tab,
      control: true,
    ),
    NetcruxAction.previousTab: const SingleActivator(
      LogicalKeyboardKey.tab,
      control: true,
      shift: true,
    ),
    NetcruxAction.openSettings: mod(LogicalKeyboardKey.comma),
    NetcruxAction.openAbout: const SingleActivator(LogicalKeyboardKey.f1),
    // ── file (export / session) ──────────────────────────────────────────
    NetcruxAction.exportPng: mod(LogicalKeyboardKey.keyE, shift: true),
    NetcruxAction.exportSvg: const SingleActivator(
      LogicalKeyboardKey.keyE,
      alt: true,
    ),
    NetcruxAction.exportJson: const SingleActivator(
      LogicalKeyboardKey.keyJ,
      alt: true,
    ),
    NetcruxAction.saveSession: mod(LogicalKeyboardKey.keyS),
    NetcruxAction.openSession: mod(LogicalKeyboardKey.keyL),
    // ── file (project import) ────────────────────────────────────────────
    // Cmd/Ctrl+I — "I for Import", mirroring WaveCrux's importGtkwSession.
    // Cmd/Ctrl+Shift+I belongs to openTabDiagnostics, WaveCrux's suite-wide Tab Diagnostics
    // chord.
    NetcruxAction.importFilelist: mod(LogicalKeyboardKey.keyI),
    // ── diagnostics ───────────────────────────────────────────────────────
    // Cmd/Ctrl+Shift+I — "Inspect tab", the WaveCrux Tab Diagnostics
    // binding, and Cmd/Ctrl+Shift+M — "Memory", the WaveCrux App
    // Diagnostics binding (both match WaveCrux's
    // shortcut_bindings.dart).
    NetcruxAction.openTabDiagnostics: mod(LogicalKeyboardKey.keyI, shift: true),
    NetcruxAction.openAppDiagnostics: mod(LogicalKeyboardKey.keyM, shift: true),
    // ── split-pane ───────────────────────────────────────────────────────
    // Cmd/Ctrl+\ — mirrors WaveCrux. closePane / focusOtherPane /
    // moveTabToOtherPane are command-palette-only because their
    // VSCode-equivalent chords (Cmd+K W / Cmd+K →) require chord
    // handling that the current ShortcutManager doesn't support; the
    // chord-binding pass is a follow-on cleanup.
    NetcruxAction.splitPaneRight: mod(LogicalKeyboardKey.backslash),
  };
}

/// Extra activators that fire an action alongside its default binding.
///
/// A binding names a character, not a key position. Zoom In's default is
/// Cmd/Ctrl plus `=`, which is unshifted on a US layout; on Swedish, German
/// and most Nordic and European layouts `=` is Shift+0 and `+` has a key of
/// its own. So Zoom In also answers to Cmd/Ctrl plus `+` (with or without
/// Shift, which is how a US layout types it) and to Cmd/Ctrl plus numpad `+`,
/// the way browsers and VS Code accept them. Zoom Out and Zoom to Fit take
/// their numpad keys the same way.
///
/// Aliases are not bindings: they are not persisted, not listed in
/// `Settings > Keyboard Shortcuts`, and apply only while the action still
/// holds its default activator (see [activatorsWithAliases]). Rebinding Zoom
/// In therefore moves it entirely to the new key.
Map<NetcruxAction, List<ShortcutActivator>> defaultBindingAliases() {
  final isMac =
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.iOS;
  SingleActivator mod(LogicalKeyboardKey key, {bool shift = false}) =>
      SingleActivator(
        key,
        meta: isMac,
        control: !isMac,
        shift: shift,
      );
  return <NetcruxAction, List<ShortcutActivator>>{
    NetcruxAction.zoomIn: <ShortcutActivator>[
      mod(LogicalKeyboardKey.add),
      mod(LogicalKeyboardKey.add, shift: true),
      mod(LogicalKeyboardKey.equal, shift: true),
      mod(LogicalKeyboardKey.numpadAdd),
    ],
    NetcruxAction.zoomOut: <ShortcutActivator>[
      mod(LogicalKeyboardKey.numpadSubtract),
    ],
    NetcruxAction.zoomFitAll: <ShortcutActivator>[
      mod(LogicalKeyboardKey.numpad0),
    ],
  };
}

/// The activator-to-action table the keyboard surface installs: every entry
/// of [effective] (the conflict-resolved bindings), plus the
/// [defaultBindingAliases] of each action whose effective activator is still
/// its default.
///
/// An alias never takes a chord another action holds: a user who binds
/// Cmd/Ctrl+Shift+= to something else keeps it, and Zoom In simply loses
/// that alias.
Map<ShortcutActivator, NetcruxAction> activatorsWithAliases(
  Map<NetcruxAction, ShortcutActivator> effective,
) {
  final result = <ShortcutActivator, NetcruxAction>{
    for (final entry in effective.entries) entry.value: entry.key,
  };
  final defaults = defaultBindings();
  bool taken(ShortcutActivator candidate) => result.keys.any(
    (activator) => KeyBindingResolver.activatorsEqual(activator, candidate),
  );
  for (final entry in defaultBindingAliases().entries) {
    final action = entry.key;
    final current = effective[action];
    if (current == null ||
        !KeyBindingResolver.activatorsEqual(current, defaults[action])) {
      continue;
    }
    for (final alias in entry.value) {
      if (!taken(alias)) result[alias] = action;
    }
  }
  return result;
}
