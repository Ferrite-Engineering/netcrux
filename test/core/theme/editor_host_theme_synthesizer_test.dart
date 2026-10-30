// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:ui' show Color;

import 'package:crux_theme/crux_theme.dart';
import 'package:flutter/material.dart' show Brightness;
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/theme/editor_host_theme_synthesizer.dart';

Color? _chrome(CruxColorTheme theme, String token) =>
    theme.color(chromeCategoryId, token);

void main() {
  test('chrome follows the editor colors it is given', () {
    final theme = synthesizeEditorHostTheme(
      appearance: 'dark',
      tokens: const <String, String>{
        'editor.background': '#102030',
        'editor.foreground': '#aabbcc',
        'sideBar.background': '#112233',
        'statusBar.background': '#007acc',
        'tab.activeBackground': '#223344',
        'panel.border': '#445566',
      },
    );
    expect(theme.id, kEditorHostThemeId);
    expect(theme.brightness, Brightness.dark);
    expect(
      _chrome(theme, ChromeTokens.scaffoldBackground),
      const Color(0xFF102030),
    );
    expect(
      _chrome(theme, ChromeTokens.panelBackground),
      const Color(0xFF112233),
    );
    expect(
      _chrome(theme, ChromeTokens.statusBarBackground),
      const Color(0xFF007ACC),
    );
    expect(
      _chrome(theme, ChromeTokens.tabBarSelected),
      const Color(0xFF223344),
    );
    expect(_chrome(theme, ChromeTokens.splitter), const Color(0xFF445566));
  });

  test('a color the host omits falls back to its own editor colors', () {
    final theme = synthesizeEditorHostTheme(
      appearance: 'dark',
      tokens: const <String, String>{
        'editor.background': '#102030',
        'editor.foreground': '#aabbcc',
      },
    );
    expect(
      _chrome(theme, ChromeTokens.panelBackground),
      const Color(0xFF102030),
    );
    expect(
      _chrome(theme, ChromeTokens.statusBarForeground),
      const Color(0xFFAABBCC),
    );
  });

  test('a value that does not parse counts as absent', () {
    final theme = synthesizeEditorHostTheme(
      appearance: 'light',
      tokens: const <String, String>{'editor.background': 'not a color'},
    );
    expect(
      _chrome(theme, ChromeTokens.scaffoldBackground),
      const Color(0xFFFFFFFF),
    );
  });

  test('both high-contrast kinds keep their ordinary brightness', () {
    expect(editorHostAppearanceIsLight('light'), isTrue);
    expect(editorHostAppearanceIsLight('highContrastLight'), isTrue);
    expect(editorHostAppearanceIsLight('dark'), isFalse);
    expect(editorHostAppearanceIsLight('highContrast'), isFalse);
    expect(
      synthesizeEditorHostTheme(
        appearance: 'highContrastLight',
        tokens: const <String, String>{},
      ).brightness,
      Brightness.light,
    );
  });

  test('is never a built-in preset id', () {
    expect(builtinPresetById(kEditorHostThemeId), isNull);
  });
}
