// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Synthesizes a NetCrux `CruxColorTheme` from the VS Code color tokens the
// extension's page shim relays over the editor-host bridge.
//
// This is a new source for the existing JSON-first theme mechanism, not a new
// mechanism. The result is an ordinary theme: its chrome tokens reach painted
// surfaces through `applyChromeTokens`, and its brightness selects the light or
// dark `NetcruxTheme` the schematic canvas and panels derive from. A token not
// set here is the transparent sentinel the chrome catalog defines, which
// `applyChromeTokens` reads as "use the base theme's value", so the function
// only sets the tokens it can derive with confidence.
//
// Where the read happens: VS Code does not hand an extension host process a
// resolved palette, and the host has no DOM. A theme's resolved colors exist
// only in the webview document, as `--vscode-*` custom properties, so the page
// shim reads a curated list and this function sees only that decoded result.

import 'package:crux_theme/crux_theme.dart';
import 'package:flutter/material.dart' show Brightness, Color;

/// Stable id of the synthesized theme. Never a built-in preset id, so
/// `builtinPresetById(kEditorHostThemeId)` is null and nothing can mistake it
/// for a preset selection.
const String kEditorHostThemeId = 'editor-host.vscode';

/// The VS Code color ids [synthesizeEditorHostTheme] reads. The page shim
/// relays exactly these, so the two lists are kept in step by a test on each
/// side.
const List<String> kEditorHostThemeColorIds = <String>[
  'editor.background',
  'editor.foreground',
  'editorWidget.background',
  'sideBar.background',
  'sideBar.foreground',
  'sideBarSectionHeader.background',
  'sideBarSectionHeader.foreground',
  'panel.border',
  'statusBar.background',
  'statusBar.foreground',
  'titleBar.activeBackground',
  'titleBar.activeForeground',
  'tab.activeBackground',
  'tab.inactiveBackground',
  'tab.activeForeground',
  'focusBorder',
];

/// Whether the VS Code theme kind [appearance] is a light one. Both
/// high-contrast kinds keep the brightness of their ordinary counterpart, so a
/// token the host omits falls back to the matching half of the base theme.
bool editorHostAppearanceIsLight(String appearance) =>
    appearance == 'light' || appearance == 'highContrastLight';

/// Builds a theme from the raw VS Code tokens of a `theme_tokens` frame.
///
/// [tokens] is keyed by VS Code's dotted color id with `#RRGGBB` or
/// `#RRGGBBAA` values; a value that does not parse is treated as absent.
CruxColorTheme synthesizeEditorHostTheme({
  required String appearance,
  required Map<String, String> tokens,
}) {
  final brightness = editorHostAppearanceIsLight(appearance)
      ? Brightness.light
      : Brightness.dark;

  Color? raw(String vscodeId) {
    final value = tokens[vscodeId];
    if (value == null) return null;
    return ThemePackCodec.tryParseColor(value);
  }

  final background =
      raw('editor.background') ??
      (brightness == Brightness.light
          ? const Color(0xFFFFFFFF)
          : const Color(0xFF1E1E1E));
  final foreground =
      raw('editor.foreground') ??
      (brightness == Brightness.light
          ? const Color(0xFF000000)
          : const Color(0xFFD4D4D4));

  final chrome = <String, Color>{
    ChromeTokens.scaffoldBackground: background,
    ChromeTokens.panelBackground: raw('sideBar.background') ?? background,
    ChromeTokens.panelHeaderBackground:
        raw('sideBarSectionHeader.background') ??
        raw('editorWidget.background') ??
        background,
    ChromeTokens.panelHeaderForeground:
        raw('sideBarSectionHeader.foreground') ??
        raw('sideBar.foreground') ??
        foreground,
    ChromeTokens.toolbarBackground:
        raw('titleBar.activeBackground') ?? background,
    ChromeTokens.toolbarIcon: raw('titleBar.activeForeground') ?? foreground,
    ChromeTokens.toolbarIconActive: raw('focusBorder') ?? foreground,
    ChromeTokens.statusBarBackground: raw('statusBar.background') ?? background,
    ChromeTokens.statusBarForeground: raw('statusBar.foreground') ?? foreground,
    ChromeTokens.splitter:
        raw('panel.border') ?? Color.lerp(background, foreground, 0.14)!,
    ChromeTokens.splitterHover: raw('focusBorder') ?? foreground,
    ChromeTokens.tabBarBackground: raw('tab.inactiveBackground') ?? background,
    ChromeTokens.tabBarSelected: raw('tab.activeBackground') ?? background,
    ChromeTokens.tabBarLabel: raw('tab.activeForeground') ?? foreground,
  };

  return CruxColorTheme(
    id: kEditorHostThemeId,
    // Never rendered: the theme is applied for the session only and the
    // preset grid enumerates the built-in presets, which never include it.
    displayName: 'VS Code',
    brightness: brightness,
    tokens: <String, Map<String, Color>>{chromeCategoryId: chrome},
  );
}
