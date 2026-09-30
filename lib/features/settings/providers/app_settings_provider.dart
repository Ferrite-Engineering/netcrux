// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_settings/crux_settings.dart';
import 'package:netcrux/domain/enums/yosys_path_mode.dart';
import 'package:netcrux/domain/models/app_settings.dart';
import 'package:netcrux/domain/models/panel_layout_state.dart';
import 'package:netcrux/services/settings/netcrux_settings_codec.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'app_settings_provider.g.dart';

/// Provides the [SettingsService] that owns NetCrux's persistent settings.
///
/// Test code can override this provider with a service that points at a
/// stub `SharedPreferences` instance (`SharedPreferences.setMockInitialValues({})`
/// in setUp + `SettingsService(codec, prefsOverride: prefs)` here).
@Riverpod(keepAlive: true)
SettingsService<AppSettings> settingsService(Ref ref) {
  return const SettingsService<AppSettings>(NetcruxSettingsCodec());
}

/// Active [AppSettings]. Notifier loads from disk on first read and saves
/// after every mutation. Mutations go through dedicated methods so the
/// surface stays small as more settings land.
@Riverpod(keepAlive: true)
class AppSettingsNotifier extends _$AppSettingsNotifier {
  @override
  Future<AppSettings> build() async {
    final service = ref.watch(settingsServiceProvider);
    return service.load();
  }

  /// Records [path] at the top of the recent-projects list, evicting any
  /// existing entry for the same path. Trims the list to
  /// [AppSettings.recentPathsLimit].
  Future<void> recordRecentProject(String path) async {
    await _update(
      (current) {
        final dedup = [
          path,
          ...current.recentProjectPaths.where((p) => p != path),
        ];
        return current.copyWith(
          recentProjectPaths: List.unmodifiable(
            dedup.take(AppSettings.recentPathsLimit),
          ),
        );
      },
    );
  }

  /// Records [paths] at the top of the recent-source-files list, evicting
  /// any existing entry for the same path. Trims the list to
  /// [AppSettings.recentPathsLimit].
  Future<void> recordRecentSourceFiles(Iterable<String> paths) async {
    if (paths.isEmpty) return;
    await _update(
      (current) {
        final seen = paths.toSet();
        final dedup = [
          ...paths,
          ...current.recentSourceFilePaths.where((p) => !seen.contains(p)),
        ];
        return current.copyWith(
          recentSourceFilePaths: List.unmodifiable(
            dedup.take(AppSettings.recentPathsLimit),
          ),
        );
      },
    );
  }

  /// Records [path] at the top of the recent-workspaces list, evicting any
  /// existing entry for the same path. Trims the list to
  /// [AppSettings.recentPathsLimit]. Used by the Open Workspace / Save
  /// Workspace As… flow.
  Future<void> recordRecentWorkspace(String path) async {
    await _update(
      (current) {
        final dedup = [
          path,
          ...current.recentWorkspacePaths.where((p) => p != path),
        ];
        return current.copyWith(
          recentWorkspacePaths: List.unmodifiable(
            dedup.take(AppSettings.recentPathsLimit),
          ),
        );
      },
    );
  }

  /// Clears all recent-files entries (project, source-file, and workspace
  /// lists).
  Future<void> clearRecentFiles() async {
    await _update(
      (current) => current.copyWith(
        recentProjectPaths: const [],
        recentSourceFilePaths: const [],
        recentWorkspacePaths: const [],
      ),
    );
  }

  /// Updates the auto-reload mode.
  /// Persists the UI language ([CoreSettings.locale]); `app.dart` watches
  /// it and rebuilds `MaterialApp.locale`, so the switch applies live.
  Future<void> setLocale(String locale) async {
    await _update(
      (current) => current.copyWith(
        core: current.core.copyWith(locale: locale),
      ),
    );
  }

  Future<void> setAutoReloadMode(AutoReloadMode mode) async {
    await _update(
      (current) => current.copyWith(
        core: current.core.copyWith(autoReloadMode: mode),
      ),
    );
  }

  /// Sets the active color-theme preset id (e.g. `crux-dark`,
  /// `solarized-dark`). Wired through `cruxColorThemeProvider` by the
  /// NetCrux notifier override — the in-memory theme rebuilds from the
  /// persisted name + overrides on the next read.
  Future<void> setActiveThemeName(String name) async {
    await _update(
      (current) => current.copyWith(
        core: current.core.copyWith(activeThemeName: name),
      ),
    );
  }

  /// Replaces the flat token-path override map fed into the
  /// `cruxColorThemeProvider` bridge. Pass an empty map to clear all
  /// overrides.
  Future<void> setThemeOverrides(Map<String, String> overrides) async {
    await _update(
      (current) => current.copyWith(
        core: current.core.copyWith(
          themeOverrides: Map<String, String>.unmodifiable(overrides),
        ),
      ),
    );
  }

  /// Switches the Yosys path-resolution strategy
  /// ([YosysPathMode.autoDetect] / [YosysPathMode.bundled] /
  /// [YosysPathMode.custom]). Settings → Engines → Yosys writes
  /// through this method; the elaboration backend listens via
  /// `effectiveYosysExecutableProvider`.
  Future<void> setYosysPathMode(YosysPathMode mode) async {
    await _update(
      (current) => current.copyWith(yosysPathMode: mode),
    );
  }

  /// Updates the user-supplied custom Yosys executable path. Used
  /// only when [YosysPathMode.custom] is active. Empty string clears
  /// the field; the Settings UI surfaces an empty-path validation
  /// error in that case.
  Future<void> setYosysCustomPath(String path) async {
    await _update(
      (current) => current.copyWith(yosysCustomPath: path),
    );
  }

  /// Enables or disables the CXP peer cross-probe server. The
  /// `cxpServerProvider` watches this flag and starts/stops the
  /// underlying [`LocalCxpServer`](package:crux_cxp) accordingly.
  Future<void> setCxpServerEnabled({required bool enabled}) async {
    await _update(
      (current) => current.copyWith(cxpServerEnabled: enabled),
    );
  }

  /// Updates the CXP server's bind port. The `cxpServerProvider`
  /// re-binds on the next launch (or on the next manual restart from
  /// Settings → CXP Cross-Probe).
  Future<void> setCxpServerPort(int port) async {
    await _update(
      (current) => current.copyWith(cxpServerPort: port),
    );
  }

  /// Enables or disables requesting user attention (bouncing the dock /
  /// flashing the taskbar) when a peer sends a cross-probe. The
  /// `cxpAttentionBridge` mirrors this flag; it never steals focus.
  Future<void> setRequestAttentionOnCrossProbe({required bool enabled}) async {
    await _update(
      (current) => current.copyWith(requestAttentionOnCrossProbe: enabled),
    );
  }

  /// Enables or disables automatic broadcast of the active schematic
  /// selection to connected CXP peers on selection change (live cross-probe).
  /// The `CxpOutboundEmitterController` reads this flag; when off, only
  /// explicit sends ("Send selection" / "Open in WaveCrux") share.
  Future<void> setBroadcastSelectionOnCrossProbe({
    required bool enabled,
  }) async {
    await _update(
      (current) => current.copyWith(broadcastSelectionOnCrossProbe: enabled),
    );
  }

  /// Updates the editor invocation command honoured by the CXP
  /// `request_open_source` handler. Tokens `{file}` and `{line}` are
  /// substituted at invocation time. Empty string disables shell-out.
  Future<void> setCxpEditorCommand(String command) async {
    await _update(
      (current) => current.copyWith(cxpEditorCommand: command),
    );
  }

  /// Enables or disables the automatic update check (launch, periodic, and
  /// on-resume). `autoUpdateCheckEnabledProvider` reads the flag; the manual
  /// "Check for Updates" action ignores it and always runs.
  Future<void> setAutoCheckForUpdates({required bool enabled}) async {
    await _update(
      (current) => current.copyWith(autoCheckForUpdates: enabled),
    );
  }

  /// Enables or disables rehydrating the persisted workspace document at
  /// launch. Read by `NetcruxWorkspaceNotifier.shouldRestoreOnLaunch` before
  /// the document is loaded; turning it off leaves `workspace.json` on disk,
  /// so turning it back on restores the session that was there. Surfaced in
  /// Settings → General.
  Future<void> setRestoreTabsOnLaunch({required bool enabled}) async {
    await _update(
      (current) => current.copyWith(
        core: current.core.copyWith(restoreTabsOnLaunch: enabled),
      ),
    );
  }

  /// Enables or disables the diagnostics surfaces in release builds
  /// (Settings → Advanced). Debug and profile builds ignore the flag —
  /// see `diagnosticsEnabledProvider`.
  Future<void> setDiagnosticsEnabled({required bool enabled}) async {
    await _update(
      (current) => current.copyWith(
        core: current.core.copyWith(diagnosticsEnabled: enabled),
      ),
    );
  }

  /// Persists a new [PanelLayoutState]. Called by `PanelLayoutNotifier`
  /// whenever the user toggles a side panel or drag-resizes a splitter.
  Future<void> updatePanelLayout(PanelLayoutState layout) async {
    await _update((current) => current.copyWith(panelLayout: layout));
  }

  /// Helper: load current state (resolving the async load if needed), apply
  /// [mutator], persist, and refresh the notifier state.
  Future<void> _update(
    AppSettings Function(AppSettings current) mutator,
  ) async {
    final service = ref.read(settingsServiceProvider);
    final current = state.value ?? const AppSettings.defaults();
    final updated = mutator(current);
    if (updated == current) return;
    state = AsyncData(updated);
    await service.save(updated);
  }
}
