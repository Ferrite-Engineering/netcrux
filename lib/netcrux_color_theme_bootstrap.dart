// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_theme/crux_theme.dart';
import 'package:flutter/material.dart' show Color;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:netcrux/core/theme/editor_host_theme_synthesizer.dart';
import 'package:netcrux/features/settings/providers/app_settings_provider.dart';
import 'package:netcrux/services/host_bridge/host_bridge_messages.dart'
    show HostBridgeThemeTokens;
import 'package:netcrux/services/host_bridge/host_theme_tokens_provider.dart';

/// Riverpod override that wires NetCrux persistence into `crux_theme`'s
/// `cruxColorThemeProvider`. Mirrors the WaveCrux reference notifier so
/// the suite presents a uniform theming surface across all four apps —
/// preset selection writes to `AppSettings.core.activeThemeName` /
/// `core.themeOverrides`, and the in-memory theme rebuilds from those
/// settings whenever the app boots.
class NetcruxCruxColorThemeNotifier extends CruxColorThemeNotifier {
  /// Creates a notifier seeded with the Crux Dark built-in preset so
  /// reads that race the first settings hydration still observe a
  /// sensible theme.
  NetcruxCruxColorThemeNotifier()
    : super(initial: builtinPresets()[cruxDarkPresetId]!);

  /// The theme an editor host last applied, or null when none has. Kept so a
  /// settings hydration that rebuilds this notifier does not replace the
  /// host's colors with the persisted preset.
  CruxColorTheme? _hostTheme;

  @override
  CruxColorTheme build() {
    final host = _hostTheme;
    if (host != null) return host;
    final settings = ref.watch(appSettingsProvider).value;
    if (settings == null) return initial;
    // Resolved through `builtinPresetById` rather than a raw map lookup
    // so a persisted id from before the presets were de-branded
    // (`wavecrux-dark` / `wavecrux-light`) migrates to its current id
    // instead of silently falling back to the seed theme.
    final base = builtinPresetById(settings.core.activeThemeName) ?? initial;
    if (settings.core.themeOverrides.isEmpty) return base;
    final parsed = _parseOverrides(settings.core.themeOverrides);
    if (parsed.isEmpty) return base;
    return base.mergeTokens(parsed);
  }

  @override
  void activate(CruxColorTheme theme) {
    _hostTheme = null;
    super.activate(theme);
    _persistDerivedFromTheme(theme);
  }

  /// Applies [theme] for this session only: nothing is written to the
  /// persisted settings.
  ///
  /// The editor-host bridge calls this, not [activate]. When an editor drives
  /// this build the active theme is a live synthesis of the editor's own color
  /// theme, not a preset the user chose. Persisting it would overwrite the
  /// user's preset and overrides with a value that only makes sense inside
  /// that one editor window.
  void applyEphemeral(CruxColorTheme theme) {
    _hostTheme = theme;
    super.activate(theme);
  }

  @override
  void applyOverrides(Map<String, Color> overrides) {
    if (overrides.isEmpty) return;
    super.applyOverrides(overrides);
    _persistDerivedFromTheme(state);
  }

  void _persistDerivedFromTheme(CruxColorTheme theme) {
    // The host's theme is never a user choice, so it is never persisted.
    if (_hostTheme != null) return;
    final baseline = builtinPresetById(theme.id);

    final overrides = <String, String>{};
    if (baseline != null) {
      for (final categoryEntry in theme.tokens.entries) {
        final baselineCategory =
            baseline.tokens[categoryEntry.key] ?? const <String, Color>{};
        for (final tokenEntry in categoryEntry.value.entries) {
          final baselineValue = baselineCategory[tokenEntry.key];
          if (baselineValue == null ||
              baselineValue.toARGB32() != tokenEntry.value.toARGB32()) {
            final dotted = CruxColorTheme.dottedId(
              categoryEntry.key,
              tokenEntry.key,
            );
            overrides[dotted] = ThemePackCodec.encodeColor(tokenEntry.value);
          }
        }
      }
    }

    final notifier = ref.read(appSettingsProvider.notifier);
    // Fire-and-forget: the in-memory state already reflects the new
    // theme; on-disk writes are best-effort and any error surfaces
    // via the SettingsService.
    unawaited(notifier.setActiveThemeName(theme.id));
    unawaited(notifier.setThemeOverrides(overrides));
  }

  static Map<String, Color> _parseOverrides(Map<String, String> raw) {
    final out = <String, Color>{};
    for (final entry in raw.entries) {
      final color = ThemePackCodec.tryParseColor(entry.value);
      if (color != null) out[entry.key] = color;
    }
    return out;
  }
}

/// The single override every NetCrux bootstrap spreads into its
/// [ProviderScope] before `runApp`.
final Override netcruxCruxColorThemeOverride = cruxColorThemeProvider
    .overrideWith(NetcruxCruxColorThemeNotifier.new);

/// Applies the colors an editor host sends to [container]'s theme, now and on
/// every later change.
///
/// Applied for this session only, through
/// [NetcruxCruxColorThemeNotifier.applyEphemeral] and never `activate`: the
/// editor's colors must follow every live change of its theme, but must not
/// overwrite the preset the user chose for the standalone app. Without a host
/// the tokens never arrive and this does nothing.
void bindEditorHostTheme(ProviderContainer container) {
  container.listen<HostBridgeThemeTokens?>(hostThemeTokensProvider, (
    _,
    tokens,
  ) {
    final notifier = container.read(cruxColorThemeProvider.notifier);
    if (tokens == null || notifier is! NetcruxCruxColorThemeNotifier) return;
    notifier.applyEphemeral(
      synthesizeEditorHostTheme(
        appearance: tokens.appearance,
        tokens: tokens.tokens,
      ),
    );
  });
}
