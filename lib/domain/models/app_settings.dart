// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_settings/crux_settings.dart';
import 'package:meta/meta.dart';
import 'package:netcrux/domain/enums/yosys_path_mode.dart';
import 'package:netcrux/domain/models/panel_layout_state.dart';

/// NetCrux's per-product application settings.
///
/// Composes [CoreSettings] (the cross-suite shared subset — theme,
/// locale, auto-save interval, plugin governance, etc.) via has-a and
/// adds NetCrux-specific fields on top. Mirrors WaveCrux's settings
/// composition.
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
    this.cxpServerEnabled = true,
    this.cxpServerPort = defaultCxpServerPort,
    this.cxpEditorCommand = defaultCxpEditorCommand,
    this.requestAttentionOnCrossProbe = true,
    this.broadcastSelectionOnCrossProbe = true,
    this.panelLayout = const PanelLayoutState(),
    this.autoCheckForUpdates = true,
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
      cxpServerEnabled = true,
      cxpServerPort = defaultCxpServerPort,
      cxpEditorCommand = defaultCxpEditorCommand,
      requestAttentionOnCrossProbe = true,
      broadcastSelectionOnCrossProbe = true,
      panelLayout = const PanelLayoutState(),
      autoCheckForUpdates = true;

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

  /// When true, the CXP peer cross-probe server starts at app launch and
  /// writes a discovery manifest so other Crux apps can find this
  /// NetCrux instance. Defaults to enabled — cross-probe is a
  /// suite-defining capability and should "just work" out of the box.
  final bool cxpServerEnabled;

  /// TCP port the CXP server binds to on localhost (`127.0.0.1`). Default
  /// is [defaultCxpServerPort] (`54323`), distinct from WaveCrux's CXP
  /// port (`54322`) so multiple Crux apps run side-by-side without
  /// collision. Set to `0` to let the OS pick a free port (useful in
  /// tests).
  final int cxpServerPort;

  /// Shell command template used to honour `request_open_source` from
  /// remote peers. The first segment is the executable; later segments
  /// are arguments. The literal tokens `{file}` and `{line}` are
  /// substituted at invocation time with the path and 1-based line
  /// number. Default [defaultCxpEditorCommand] is `code -g {file}:{line}`
  /// — the VS Code CLI form that is correct on macOS/Linux/Windows when
  /// `code` is on `PATH`. Empty string disables shell-out and the
  /// handler responds with `honored: false`.
  final String cxpEditorCommand;

  /// Whether an actionable inbound cross-probe (a honored highlight, opened
  /// source, or opened artifact) requests the user's attention — a portable
  /// dock bounce / taskbar flash that never steals focus. The
  /// settings→lifecycle bridge swaps the global
  /// `windowAttentionRequester` between the method-channel backend and a no-op
  /// on this flag, so turning it off makes `requestUserAttention()` silent.
  /// Defaults to enabled.
  final bool requestAttentionOnCrossProbe;

  /// When true, NetCrux announces the active schematic selection to every
  /// connected CXP peer as it changes (live cross-probe), via
  /// `CxpOutboundEmitterController`. When false, no automatic `notify_selection`
  /// broadcast is emitted on selection change — only explicit sends (the
  /// cross-probe panel's "Send selection" and "Open in WaveCrux") still share.
  /// Defaults to enabled: live cross-probe is the suite-defining behaviour and
  /// should work out of the box.
  final bool broadcastSelectionOnCrossProbe;

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

  /// Default port for the NetCrux CXP server. Distinct from WaveCrux's
  /// 54322 and from LintCrux/SimCrux when they ship — every product
  /// gets its own default so a developer running all four locally has
  /// no port collision out of the box.
  static const int defaultCxpServerPort = 54323;

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
    bool? cxpServerEnabled,
    int? cxpServerPort,
    String? cxpEditorCommand,
    bool? requestAttentionOnCrossProbe,
    bool? broadcastSelectionOnCrossProbe,
    PanelLayoutState? panelLayout,
    bool? autoCheckForUpdates,
  }) {
    return AppSettings(
      core: core ?? this.core,
      recentProjectPaths: recentProjectPaths ?? this.recentProjectPaths,
      recentSourceFilePaths:
          recentSourceFilePaths ?? this.recentSourceFilePaths,
      recentWorkspacePaths: recentWorkspacePaths ?? this.recentWorkspacePaths,
      yosysPathMode: yosysPathMode ?? this.yosysPathMode,
      yosysCustomPath: yosysCustomPath ?? this.yosysCustomPath,
      cxpServerEnabled: cxpServerEnabled ?? this.cxpServerEnabled,
      cxpServerPort: cxpServerPort ?? this.cxpServerPort,
      cxpEditorCommand: cxpEditorCommand ?? this.cxpEditorCommand,
      requestAttentionOnCrossProbe:
          requestAttentionOnCrossProbe ?? this.requestAttentionOnCrossProbe,
      broadcastSelectionOnCrossProbe:
          broadcastSelectionOnCrossProbe ?? this.broadcastSelectionOnCrossProbe,
      panelLayout: panelLayout ?? this.panelLayout,
      autoCheckForUpdates: autoCheckForUpdates ?? this.autoCheckForUpdates,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! AppSettings) return false;
    if (other.core != core) return false;
    if (other.yosysPathMode != yosysPathMode) return false;
    if (other.yosysCustomPath != yosysCustomPath) return false;
    if (other.cxpServerEnabled != cxpServerEnabled) return false;
    if (other.cxpServerPort != cxpServerPort) return false;
    if (other.cxpEditorCommand != cxpEditorCommand) return false;
    if (other.requestAttentionOnCrossProbe != requestAttentionOnCrossProbe) {
      return false;
    }
    if (other.broadcastSelectionOnCrossProbe !=
        broadcastSelectionOnCrossProbe) {
      return false;
    }
    if (other.panelLayout != panelLayout) return false;
    if (other.autoCheckForUpdates != autoCheckForUpdates) return false;
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
    cxpServerEnabled,
    cxpServerPort,
    cxpEditorCommand,
    requestAttentionOnCrossProbe,
    broadcastSelectionOnCrossProbe,
    panelLayout,
    autoCheckForUpdates,
  );

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
