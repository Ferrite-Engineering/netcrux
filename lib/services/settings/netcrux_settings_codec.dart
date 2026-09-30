// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_settings/crux_settings.dart';
import 'package:netcrux/domain/enums/yosys_path_mode.dart';
import 'package:netcrux/domain/models/app_settings.dart';
import 'package:netcrux/domain/models/panel_layout_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Concrete [SettingsCodec] for netcrux's [AppSettings].
///
/// Delegates the [CoreSettings] portion to [CoreSettingsCodec] (preserving
/// the cross-suite `settings.*` key namespace) and adds load/save for
/// netcrux-specific recent-files lists under the `netcrux.*` namespace so
/// they cannot collide with anything WaveCrux or another suite product
/// might persist.
class NetcruxSettingsCodec implements SettingsCodec<AppSettings> {
  /// Const constructor — codec is stateless.
  const NetcruxSettingsCodec();

  static const _kRecentProjectPaths = 'netcrux.recentProjectPaths';
  static const _kRecentSourceFilePaths = 'netcrux.recentSourceFilePaths';
  static const _kRecentWorkspacePaths = 'netcrux.recentWorkspacePaths';
  static const _kYosysPathMode = 'netcrux.yosysPathMode';
  static const _kYosysCustomPath = 'netcrux.yosysCustomPath';
  static const _kCxpServerEnabled = 'netcrux.cxpServerEnabled';
  static const _kCxpServerPort = 'netcrux.cxpServerPort';
  static const _kCxpEditorCommand = 'netcrux.cxpEditorCommand';
  static const _kRequestAttentionOnCrossProbe =
      'netcrux.requestAttentionOnCrossProbe';
  static const _kBroadcastSelectionOnCrossProbe =
      'netcrux.broadcastSelectionOnCrossProbe';
  static const _kAutoCheckForUpdates = 'netcrux.autoCheckForUpdates';
  static const _kPanelHierarchyVisible =
      'netcrux.panelLayout.hierarchyTreeVisible';
  static const _kPanelInspectorVisible = 'netcrux.panelLayout.inspectorVisible';
  static const _kPanelDiagnosticsVisible =
      'netcrux.panelLayout.diagnosticsVisible';
  static const _kPanelHierarchyWidth = 'netcrux.panelLayout.hierarchyTreeWidth';
  static const _kPanelInspectorWidth = 'netcrux.panelLayout.inspectorWidth';
  static const _kPanelDiagnosticsHeight =
      'netcrux.panelLayout.diagnosticsHeight';

  @override
  Future<AppSettings> load(SharedPreferences prefs) async {
    final core = await const CoreSettingsCodec().load(prefs);
    final projectPaths = prefs.getStringList(_kRecentProjectPaths) ?? const [];
    final sourceFilePaths =
        prefs.getStringList(_kRecentSourceFilePaths) ?? const [];
    final workspacePaths =
        prefs.getStringList(_kRecentWorkspacePaths) ?? const [];
    final modeName = prefs.getString(_kYosysPathMode);
    final yosysMode = _decodeYosysMode(modeName);
    final yosysCustomPath = prefs.getString(_kYosysCustomPath) ?? '';
    final cxpServerEnabled = prefs.getBool(_kCxpServerEnabled) ?? true;
    final cxpServerPort =
        prefs.getInt(_kCxpServerPort) ?? AppSettings.defaultCxpServerPort;
    final cxpEditorCommand =
        prefs.getString(_kCxpEditorCommand) ??
        AppSettings.defaultCxpEditorCommand;
    final requestAttentionOnCrossProbe =
        prefs.getBool(_kRequestAttentionOnCrossProbe) ?? true;
    final broadcastSelectionOnCrossProbe =
        prefs.getBool(_kBroadcastSelectionOnCrossProbe) ?? true;
    final autoCheckForUpdates = prefs.getBool(_kAutoCheckForUpdates) ?? true;
    final panelLayout = _readPanelLayout(prefs);
    return AppSettings(
      core: core,
      recentProjectPaths: List.unmodifiable(
        projectPaths.take(AppSettings.recentPathsLimit),
      ),
      recentSourceFilePaths: List.unmodifiable(
        sourceFilePaths.take(AppSettings.recentPathsLimit),
      ),
      recentWorkspacePaths: List.unmodifiable(
        workspacePaths.take(AppSettings.recentPathsLimit),
      ),
      yosysPathMode: yosysMode,
      yosysCustomPath: yosysCustomPath,
      cxpServerEnabled: cxpServerEnabled,
      cxpServerPort: cxpServerPort,
      cxpEditorCommand: cxpEditorCommand,
      requestAttentionOnCrossProbe: requestAttentionOnCrossProbe,
      broadcastSelectionOnCrossProbe: broadcastSelectionOnCrossProbe,
      panelLayout: panelLayout,
      autoCheckForUpdates: autoCheckForUpdates,
    );
  }

  @override
  Future<void> save(SharedPreferences prefs, AppSettings settings) async {
    await const CoreSettingsCodec().save(prefs, settings.core);
    await Future.wait([
      prefs.setStringList(
        _kRecentProjectPaths,
        settings.recentProjectPaths.toList(),
      ),
      prefs.setStringList(
        _kRecentSourceFilePaths,
        settings.recentSourceFilePaths.toList(),
      ),
      prefs.setStringList(
        _kRecentWorkspacePaths,
        settings.recentWorkspacePaths.toList(),
      ),
      prefs.setString(_kYosysPathMode, settings.yosysPathMode.name),
      prefs.setString(_kYosysCustomPath, settings.yosysCustomPath),
      prefs.setBool(_kCxpServerEnabled, settings.cxpServerEnabled),
      prefs.setInt(_kCxpServerPort, settings.cxpServerPort),
      prefs.setString(_kCxpEditorCommand, settings.cxpEditorCommand),
      prefs.setBool(
        _kRequestAttentionOnCrossProbe,
        settings.requestAttentionOnCrossProbe,
      ),
      prefs.setBool(
        _kBroadcastSelectionOnCrossProbe,
        settings.broadcastSelectionOnCrossProbe,
      ),
      prefs.setBool(_kAutoCheckForUpdates, settings.autoCheckForUpdates),
    ]);
    await _writePanelLayout(prefs, settings.panelLayout);
  }

  /// Reads the persisted [PanelLayoutState]. Missing visibility keys fall
  /// back to the model defaults; missing size keys stay `null` so the
  /// `IdeController` uses its own pane-size defaults.
  PanelLayoutState _readPanelLayout(SharedPreferences prefs) {
    const defaults = PanelLayoutState();
    return PanelLayoutState(
      hierarchyTreeVisible:
          prefs.getBool(_kPanelHierarchyVisible) ??
          defaults.hierarchyTreeVisible,
      inspectorVisible:
          prefs.getBool(_kPanelInspectorVisible) ?? defaults.inspectorVisible,
      diagnosticsVisible:
          prefs.getBool(_kPanelDiagnosticsVisible) ??
          defaults.diagnosticsVisible,
      hierarchyTreeWidth: prefs.getDouble(_kPanelHierarchyWidth),
      inspectorWidth: prefs.getDouble(_kPanelInspectorWidth),
      diagnosticsHeight: prefs.getDouble(_kPanelDiagnosticsHeight),
    );
  }

  /// Persists [layout]. Visibility flags are always written; a `null` size
  /// removes its key so the next load falls through to the panes default
  /// rather than a stale pixel value.
  Future<void> _writePanelLayout(
    SharedPreferences prefs,
    PanelLayoutState layout,
  ) async {
    await Future.wait<void>([
      prefs.setBool(_kPanelHierarchyVisible, layout.hierarchyTreeVisible),
      prefs.setBool(_kPanelInspectorVisible, layout.inspectorVisible),
      prefs.setBool(_kPanelDiagnosticsVisible, layout.diagnosticsVisible),
      _writeNullableDouble(
        prefs,
        _kPanelHierarchyWidth,
        layout.hierarchyTreeWidth,
      ),
      _writeNullableDouble(prefs, _kPanelInspectorWidth, layout.inspectorWidth),
      _writeNullableDouble(
        prefs,
        _kPanelDiagnosticsHeight,
        layout.diagnosticsHeight,
      ),
    ]);
  }

  Future<void> _writeNullableDouble(
    SharedPreferences prefs,
    String key,
    double? value,
  ) {
    return value == null ? prefs.remove(key) : prefs.setDouble(key, value);
  }

  YosysPathMode _decodeYosysMode(String? name) {
    if (name == null) return YosysPathMode.autoDetect;
    for (final mode in YosysPathMode.values) {
      if (mode.name == name) return mode;
    }
    // Forward-compat: future builds may add new modes that this build
    // doesn't recognize. Fall back to autoDetect rather than crashing.
    return YosysPathMode.autoDetect;
  }
}
