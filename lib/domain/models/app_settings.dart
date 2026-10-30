// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_settings/crux_settings.dart';
import 'package:meta/meta.dart';
import 'package:netcrux/domain/enums/yosys_path_mode.dart';
import 'package:netcrux/domain/models/panel_layout_state.dart';
import 'package:netcrux/domain/models/schematic/scope_layout_gate.dart';

/// NetCrux's per-product application settings.
///
/// Composes [CoreSettings] (the cross-suite shared subset — theme,
/// locale, auto-save interval, plugin governance, etc.) via has-a and
/// adds NetCrux-specific fields on top. Mirrors WaveCrux's settings
/// composition.
///
/// The four CXP settings (server on or off, port, attention request, selection
/// broadcast) are not here: the shared lifecycle owns and saves them
/// (`cruxCxpSettingsProvider`).
@immutable
class AppSettings {
  /// Creates a fully-specified [AppSettings].
  const AppSettings({
    required this.core,
    required this.recentProjectPaths,
    required this.recentSourceFilePaths,
    required this.recentWorkspacePaths,
    required this.yosysPathMode,
    required this.yosysCustomPath,
    this.cxpEditorCommand = defaultCxpEditorCommand,
    this.panelLayout = const PanelLayoutState(),
    this.autoCheckForUpdates = true,
    this.layoutCellLimit = kDefaultLayoutCellLimit,
  });

  /// Standard defaults. Composes [CoreSettings.defaults] with empty recent-
  /// files lists. Other fields fall back to the suite-wide defaults.
  const AppSettings.defaults()
    : core = const CoreSettings.defaults(),
      recentProjectPaths = const <String>[],
      recentSourceFilePaths = const <String>[],
      recentWorkspacePaths = const <String>[],
      yosysPathMode = YosysPathMode.autoDetect,
      yosysCustomPath = '',
      cxpEditorCommand = defaultCxpEditorCommand,
      panelLayout = const PanelLayoutState(),
      autoCheckForUpdates = true,
      layoutCellLimit = kDefaultLayoutCellLimit;

  /// The cross-suite shared settings (theme, locale, plugin governance, …).
  final CoreSettings core;

  /// Absolute paths to recently opened `.netcrux` project files, most-recent
  /// first. Capped at [recentPathsLimit] on insertion.
  final List<String> recentProjectPaths;

  /// Absolute paths to recently opened Verilog/VHDL source files, most-
  /// recent first. Capped at [recentPathsLimit] on insertion.
  final List<String> recentSourceFilePaths;

  /// Absolute paths to recently opened `.netcrux-workspace` named-workspace
  /// files, most-recent first. Capped at [recentPathsLimit] on insertion.
  /// Populated by the workspace open / save-as flow; surfaced on the
  /// empty-canvas state alongside the recent-projects / recent-sources
  /// lists.
  final List<String> recentWorkspacePaths;

  /// Strategy NetCrux uses to locate the Yosys binary. See
  /// [YosysPathMode]; effective resolution lives in
  /// `effectiveYosysExecutableProvider`.
  final YosysPathMode yosysPathMode;

  /// User-supplied absolute path to the Yosys executable; consulted only
  /// when [yosysPathMode] is [YosysPathMode.custom]. Empty string means
  /// "no path entered yet" — the Settings UI surfaces a validation error
  /// in that state rather than falling through to the default.
  final String yosysCustomPath;

  /// Shell command template used to honour `request_open_source` from
  /// remote peers. The first segment is the executable; later segments
  /// are arguments. The literal tokens `{file}` and `{line}` are
  /// substituted at invocation time with the path and 1-based line
  /// number. Default [defaultCxpEditorCommand] is `code -g {file}:{line}`
  /// — the VS Code CLI form that is correct on macOS/Linux/Windows when
  /// `code` is on `PATH`. Empty string disables shell-out and the
  /// handler responds with `honored: false`.
  final String cxpEditorCommand;

  /// Visibility and size state for the workspace IDE layout's side panels
  /// (hierarchy tree, inspector, diagnostics drawer). Driven by
  /// `panelLayoutProvider` at runtime and rehydrated on launch via
  /// [NetcruxSettingsCodec].
  final PanelLayoutState panelLayout;

  /// When true, NetCrux checks the public version manifest for a newer
  /// release at launch, once per `CruxUpdateConfig.checkInterval`, and on app
  /// resume. Defaults to enabled — an engineer running a stale beta build is
  /// the failure mode the check exists to prevent. Turning it off suppresses
  /// only the *automatic* checks; the manual "Check for Updates" action always
  /// runs. Surfaced in Settings → General and read by
  /// `autoUpdateCheckEnabledProvider`.
  final bool autoCheckForUpdates;

  /// The largest scope, in cells, that NetCrux lays out when it is opened,
  /// entered or restored. A larger scope shows its size and waits for the
  /// user to lay it out anyway or to look at part of it in a cone view.
  /// `0` lays every scope out without asking. Defaults to
  /// [kDefaultLayoutCellLimit]. Surfaced in Settings, Engines and read by
  /// `scopeLayoutGateProvider`.
  final int layoutCellLimit;

  /// Forwarder for [CoreSettings.restoreTabsOnLaunch] — whether the persisted
  /// `workspace.json` is rehydrated at launch.
  ///
  /// Lives on [CoreSettings] (suite-shared key `settings.restoreTabsOnLaunch`)
  /// rather than in NetCrux's own `netcrux.*` namespace, because every product
  /// in the suite answers the same question and a user who flips it with
  /// `defaults write` expects one key, not four. Read by
  /// `NetcruxWorkspaceNotifier.shouldRestoreOnLaunch`, which is consulted
  /// *before* the document is loaded; declining leaves the file on disk, so
  /// turning the preference back on restores the session that was there.
  bool get restoreTabsOnLaunch => core.restoreTabsOnLaunch;

  /// Maximum number of entries retained per recent-files list. Older
  /// entries are evicted on insertion.
  static const int recentPathsLimit = 10;

  /// Default editor invocation. VS Code is the most-likely available
  /// editor across NetCrux's macOS / Linux / Windows targets; engineers
  /// using vim, sublime, or emacs configure their own command via
  /// Settings → Editors.
  static const String defaultCxpEditorCommand = 'code -g {file}:{line}';

  /// Returns a copy with overridden fields. Omitted fields retain their
  /// current values.
  AppSettings copyWith({
    CoreSettings? core,
    List<String>? recentProjectPaths,
    List<String>? recentSourceFilePaths,
    List<String>? recentWorkspacePaths,
    YosysPathMode? yosysPathMode,
    String? yosysCustomPath,
    String? cxpEditorCommand,
    PanelLayoutState? panelLayout,
    bool? autoCheckForUpdates,
    int? layoutCellLimit,
  }) {
    return AppSettings(
      core: core ?? this.core,
      recentProjectPaths: recentProjectPaths ?? this.recentProjectPaths,
      recentSourceFilePaths:
          recentSourceFilePaths ?? this.recentSourceFilePaths,
      recentWorkspacePaths: recentWorkspacePaths ?? this.recentWorkspacePaths,
      yosysPathMode: yosysPathMode ?? this.yosysPathMode,
      yosysCustomPath: yosysCustomPath ?? this.yosysCustomPath,
      cxpEditorCommand: cxpEditorCommand ?? this.cxpEditorCommand,
      panelLayout: panelLayout ?? this.panelLayout,
      autoCheckForUpdates: autoCheckForUpdates ?? this.autoCheckForUpdates,
      layoutCellLimit: layoutCellLimit ?? this.layoutCellLimit,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! AppSettings) return false;
    if (other.core != core) return false;
    if (other.yosysPathMode != yosysPathMode) return false;
    if (other.yosysCustomPath != yosysCustomPath) return false;
    if (other.cxpEditorCommand != cxpEditorCommand) return false;
    if (other.panelLayout != panelLayout) return false;
    if (other.autoCheckForUpdates != autoCheckForUpdates) return false;
    if (other.layoutCellLimit != layoutCellLimit) return false;
    if (!_listEquals(other.recentProjectPaths, recentProjectPaths)) {
      return false;
    }
    if (!_listEquals(other.recentSourceFilePaths, recentSourceFilePaths)) {
      return false;
    }
    if (!_listEquals(other.recentWorkspacePaths, recentWorkspacePaths)) {
      return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    core,
    yosysPathMode,
    yosysCustomPath,
    Object.hashAll(recentProjectPaths),
    Object.hashAll(recentSourceFilePaths),
    Object.hashAll(recentWorkspacePaths),
    cxpEditorCommand,
    panelLayout,
    autoCheckForUpdates,
    layoutCellLimit,
  );

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
