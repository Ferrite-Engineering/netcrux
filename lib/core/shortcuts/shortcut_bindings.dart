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
