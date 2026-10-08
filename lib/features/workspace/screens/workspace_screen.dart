// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/core/cli/cli_arg_parser.dart';
import 'package:netcrux/core/cli/cli_launch_intent.dart';
import 'package:netcrux/core/cli/cli_launch_intent_provider.dart';
import 'package:netcrux/core/shortcuts/netcrux_action.dart';
import 'package:netcrux/core/shortcuts/shortcut_manager_widget.dart';
import 'package:netcrux/core/web/web_launch_params_provider.dart';
import 'package:netcrux/domain/enums/netcrux_design_source.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/project/netcrux_project.dart';
import 'package:netcrux/domain/models/session/netcrux_session.dart';
import 'package:netcrux/domain/models/workspace/netcrux_tab_payload.dart';
import 'package:netcrux/features/diagnostics/widgets/pane_render_stats_popover.dart';
import 'package:netcrux/features/project/providers/current_project_provider.dart';
import 'package:netcrux/features/project/providers/loaded_netlist_provider.dart';
import 'package:netcrux/features/remote/providers/cxp_attention_bridge.dart';
import 'package:netcrux/features/remote/widgets/cxp_inbound_listener.dart';
import 'package:netcrux/features/remote/widgets/cxp_outbound_emitter.dart';
import 'package:netcrux/features/settings/providers/app_settings_provider.dart';
import 'package:netcrux/features/viewer/widgets/netcrux_status_bar.dart';
import 'package:netcrux/features/viewer/widgets/netcrux_toolbar.dart';
import 'package:netcrux/features/workspace/providers/netcrux_action_context_provider.dart';
import 'package:netcrux/features/workspace/services/active_tab_container.dart';
import 'package:netcrux/features/workspace/services/web_deep_link.dart';
import 'package:netcrux/features/workspace/services/workspace_action_dispatcher.dart';
import 'package:netcrux/features/workspace/widgets/browser_empty_canvas_content.dart';
import 'package:netcrux/features/workspace/widgets/empty_canvas_content.dart';
import 'package:netcrux/features/workspace/widgets/netcrux_viewer_tab_bar_strings.dart';
import 'package:netcrux/features/workspace/widgets/project_tab_content.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/file_open/crux_project_resolution.dart';
import 'package:netcrux/services/file_open/file_open_service.dart';
import 'package:netcrux/services/file_open/file_open_service_provider.dart';
import 'package:netcrux/services/file_open/incoming_document_service_provider.dart';
import 'package:netcrux/services/project/netcrux_project_file.dart';
import 'package:netcrux/services/project/netcrux_project_path_resolver.dart';
import 'package:netcrux/services/session/session_controller.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_notifier.dart';
import 'package:netcrux/services/workspace/workspace_recovery_provider.dart';
import 'package:netcrux/services/yosys/prebuilt_netlist_loader_provider.dart';
import 'package:netcrux/shared/platform/reveal_tab_file.dart';
import 'package:netcrux/shared/widgets/workspace_managers_scope.dart';
import 'package:path/path.dart' as p;

/// Anchor context for menu-bar action dispatch, mounted on
/// [WorkspaceScreen]'s Scaffold — i.e. BELOW the `Actions` widget
/// `ShortcutManagerWidget` installs.
///
/// `NetcruxApp._dispatchFromMenu` fires a `NetcruxActionIntent` up from a
/// context, and the menu bar mounts above the router. Neither candidate it
/// had worked: primary focus right after launch sits on the route's modal
/// focus scope, ABOVE the screen's `Actions`, and `rootNavigatorKey`'s
/// context is the Navigator's own — also above the routes. So the walk-up
/// resolved nothing and every menu selection but Quit silently no-oped —
/// including View > Command Palette, the recovery path when the palette's
/// shortcut is unbound.
///
/// Declared HERE rather than beside `rootNavigatorKey` in `app_router.dart`:
/// the layer matrix (`docs/ARCHITECTURE.md` §6.2) forbids a layer importing a
/// composition-root file, so the key has to
/// live in the layer that mounts it and be read by `app.dart` — which wires
/// layers by definition. Putting it in app_router.dart is what the static
/// import-layering guard rejects.
final GlobalKey workspaceActionsAnchorKey = GlobalKey(
  debugLabel: 'netcrux_workspace_actions_anchor',
);

/// The single home-route widget of the workspace model.
///
/// Replaces the legacy `ProjectScreen` route and the `WelcomeScreen`
/// route. Renders:
///
/// * The outer [`IdeLayout`] (chrome — toolbar / status bar / panel
///   splitters). Left, right, and bottom panes host the hierarchy,
///   inspector, and diagnostics drawer wrapped in [`ActiveTabScope`] so
///   each one reads the active tab's per-tab providers.
/// * The center pane hosts [`PaneHost<NetcruxTabPayload>`] — one or two
///   panes, each with its own [`ViewerTabBar`] + [`IndexedStack`] of
///   [`ProjectTabContent`] tabs.
/// * The empty-canvas state — rendered by `PaneHost` when
///   `workspace.tabs.isEmpty` — is the [`EmptyCanvasContent`] widget
///   wired to the file-open / new-tab / workspace-open flows below.
///
/// On first build, consumes the [`cliLaunchIntentProvider`] and applies
/// the launch intent to the workspace (open project → new tab; open
/// source files → new tab; empty → unchanged). After that, each document
/// macOS opens in the running app (`incomingDocumentServiceProvider`) is
/// applied the same way, as the launch intent that path would have been.
class WorkspaceScreen extends ConsumerStatefulWidget {
  /// Creates the workspace screen.
  const WorkspaceScreen({super.key});

  @override
  ConsumerState<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends ConsumerState<WorkspaceScreen> {
  bool _autoLaunchHandled = false;

  /// Documents macOS opens while the app runs (Finder double-click, "Open
  /// With", a drop on the Dock icon). Null until the launch intent has been
  /// applied, so a document never races the launch.
  StreamSubscription<String>? _openedDocuments;

  /// Opens arriving documents one at a time, in arrival order, as the
  /// command line opens its files one tab at a time.
  Future<void> _openedDocumentQueue = Future<void>.value();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _handleAutoLaunch());
  }

  @override
  void dispose() {
    unawaited(_openedDocuments?.cancel());
    super.dispose();
  }

  Future<void> _handleAutoLaunch() async {
    if (!mounted || _autoLaunchHandled) return;
    _autoLaunchHandled = true;
    await _surfaceWorkspaceRecoveryNotice();
    if (!mounted) return;
    await _applyLaunchIntent(ref.read(cliLaunchIntentProvider));
    if (!mounted) return;
    _listenForOpenedDocuments();
  }

  /// Routes each document macOS opens from now on through the same flow as
  /// that path on the command line, including the checks a project file's
  /// contents go through on the way in.
  void _listenForOpenedDocuments() {
    _openedDocuments ??= ref
        .read(incomingDocumentServiceProvider)
        .documents
        .listen((path) {
          _openedDocumentQueue = _openedDocumentQueue.then((_) async {
            if (!mounted) return;
            await _applyLaunchIntent(
              const CliArgParser().parseOpenedDocument(path),
            );
          });
        });
  }

  /// Applies one launch intent: the command line's, the document macOS
  /// launched the app with, or a document opened while it runs.
  Future<void> _applyLaunchIntent(CliLaunchIntent intent) async {
    switch (intent) {
      case EmptyCliLaunch():
        // Cold-launch path: workspace.json has been auto-loaded by
        // [NetcruxWorkspaceNotifier.build] but the per-tab
        // [currentProjectProvider] notifiers haven't been pushed.
        // Without hydration each restored tab comes up with an empty
        // project, the elaboration pipeline never starts, and the
        // canvas paints the "Open Project…" empty state instead of
        // the design the user left behind. Wait for the workspace to
        // settle first so the tab containers exist before we read
        // them.
        await ref.read(netcruxWorkspaceProvider.future);
        if (!mounted) return;
        await _hydrateActiveTabFromWorkspace();
        // The browser build's deep link: `?json=` names the netlist to show.
        // A no-op everywhere else — desktop never overrides the params.
        await _openWebLaunchNetlist();
      case OpenProjectCliLaunch(:final path):
        await _openProjectByPath(path);
      case OpenSourceFilesCliLaunch(:final paths):
        // Open each source file as a separate tab in the active pane
        // (one tab per file).
        for (final path in paths) {
          await _openSourceFilesByPaths(<String>[path]);
        }
      case OpenSessionCliLaunch(:final path):
        await _openSessionByPath(path);
      case OpenWorkspaceCliLaunch(:final path):
        await _confirmAndOpenWorkspace(path);
    }
  }

  /// If the workspace restore quarantined a corrupt `workspace.json`,
  /// tell the user with a localized notice. Awaits the workspace load first
  /// so the recovery signal (recorded inside `NetcruxWorkspaceNotifier.build`)
  /// is settled before we read it.
  Future<void> _surfaceWorkspaceRecoveryNotice() async {
    await ref.read(netcruxWorkspaceProvider.future);
    if (!mounted) return;
    final recovery = ref.read(workspaceRecoveryNoticeProvider);
    if (recovery == null) return;
    showCruxErrorSnack(context, L10N.of(context).workspaceRestoreCorrupted);
    ref.read(workspaceRecoveryNoticeProvider.notifier).acknowledge();
  }

  /// Confirms replacing the current workspace with the one at [path].
  /// Shows the localized "replace current workspace?" dialog before
  /// dispatching to [_openWorkspaceByPath]. Used by both the
  /// `--workspace` CLI flag and any future File → Open Workspace…
  /// flow that wants to honour the confirmation rule.
  Future<void> _confirmAndOpenWorkspace(String path) async {
    if (!mounted) return;
    final l10n = L10N.of(context);
    // The suite-standard destructive confirm — replacing the workspace
    // discards the current tab set, so it gets the error-colored verb
    // button rather than a generic "OK".
    final confirmed = await confirmCruxDestructiveAction(
      context,
      title: l10n.workspaceOpenWorkspaceTitle,
      body: l10n.workspaceLoadFromCliConfirm,
      confirmLabel: l10n.workspaceReplaceConfirmButton,
      cancelLabel: l10n.commonCancel,
    );
    if (!confirmed || !mounted) return;
    await _openWorkspaceByPath(path);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final scope = WorkspaceManagersScope.of(context);

    // The desktop menu bar is NOT mounted here — it wraps every route from
    // `MaterialApp.builder` (see `NetcruxApp._buildAppChrome`). On
    // Windows/Linux it draws the frameless window's title bar and caption
    // buttons, so mounting it inside this screen meant navigating to
    // /settings took the menu bar and the only way to close the window with
    // it. Menu items dispatch back into this screen through
    // `NetcruxActionIntent`, the same path the keyboard uses.
    //
    // Keep the settings→attention bridge alive for the shell's
    // lifetime so the `requestAttentionOnCrossProbe` preference is mirrored
    // into the global window-attention backend.
    ref.watch(cxpAttentionBridgeProvider);
    return ShortcutManagerWidget(
      // Single source of truth: every NetcruxAction's keyboard handler
      // routes through `_dispatchAction`, the same path the menu bar
      // and command palette use. The map is built over the full
      // `NetcruxAction.values` set so every bound keyboard activator
      // (Cmd+W close project, Cmd+Q, F1 about, Cmd+E exports, Cmd+S
      // session save, etc.) resolves to a handler rather than
      // silently no-op'ing on a missing entry.
      handlers: <NetcruxAction, VoidCallback>{
        for (final action in NetcruxAction.values)
          action: () => _dispatchAction(context, action),
      },
      // The keyboard surface gates on the same descriptor enablement
      // the menu bar / palette / toolbar render, resolved at keypress
      // time from the shared context provider.
      actionContextResolver: () => ref.read(netcruxActionContextProvider),
      child: Scaffold(
        // The menu bar mounts above the router and dispatches by firing a
        // NetcruxActionIntent up from a context. This key is that context:
        // it sits below the `Actions` widget ShortcutManagerWidget installs
        // just above, so a walk-up from here always reaches the handler even
        // when nothing inside the workspace holds focus. See
        // `workspaceActionsAnchorKey`.
        key: workspaceActionsAnchorKey,
        // No in-window title AppBar: the OS window chrome already shows the
        // app name, so a second "NetCrux" bar just wasted a row of vertical
        // space. The action toolbar and the tab strip are the top of the
        // workspace (VS Code style).
        // CxpInboundListener wraps the body so every CXP inbound
        // request_highlight / request_open_source flows through one
        // handler that targets the active tab via the workspace
        // managers scope.
        //
        // The IDE chrome (hierarchy / inspector / diagnostics panels and
        // their resizers) is now mounted per-tab inside `ProjectTabContent`
        // via `NetcruxIdeLayout`, not as outer chrome here. `PaneHost`
        // renders the chrome-free empty-canvas state when the workspace has
        // zero tabs — so a fresh launch shows the full-width "open a
        // project" prompt with no stray pane separator. This matches the
        // WaveCrux / LintCrux / SimCrux workspace-shell model.
        body: CxpInboundListener(
          // Keyboard regions (F6 / Shift+F6) and lost-focus recovery. Inside
          // the `Actions` ShortcutManagerWidget installs, so focus it restores
          // is always within reach of the screen's shortcut handler: focus
          // stranded on a bare scope after a native file dialog, or after the
          // focused control was rebuilt away, leaves every screen shortcut
          // dead and a screen reader silent.
          child: CruxFocusRegionScope(
            child: Column(
              children: <Widget>[
                // Tier-1 action toolbar — open-core frequent actions,
                // full-width above the tab strip. Dispatches through the same
                // `_dispatchAction` the menu bar and command palette use, so
                // it is the third action-discovery surface
                // without re-implementing any behaviour. Always visible (the
                // file-open buttons are useful on the empty canvas too). The
                // toolbar names itself, so its region carries no label.
                CruxFocusRegion(
                  child: NetcruxToolbar(
                    onAction: (action) => _dispatchAction(context, action),
                  ),
                ),
                Expanded(
                  child: Stack(
                    children: <Widget>[
                      Positioned.fill(
                        child: _buildPaneHost(l10n, scope),
                      ),
                      // Invisible, always-mounted CXP outbound emitter for the
                      // ACTIVE tab. It broadcasts NotifySelection to peers.
                      // It stays at the workspace level —
                      // following the active tab via `ActiveTabCxpEmitter` —
                      // rather than per-tab, because `PaneHost` keeps every
                      // tab's content alive in an `IndexedStack`; a per-tab
                      // emitter would make background tabs broadcast their
                      // selection too. Workspace-level keeps "emit the focused
                      // tab's selection only", independent of which panels
                      // are open. The emitter takes the active tab's container
                      // directly — no `UncontrolledProviderScope` sibling of
                      // PaneHost (see ActiveTabCxpEmitter's doc for the
                      // setState-during-build hazard that scope caused).
                      //
                      // MUST be `Positioned` (zero-size): a Stack derives its
                      // size from its NON-positioned children, so a bare 0×0
                      // child here would collapse the whole Stack to 0×0 and
                      // the PaneHost would render nothing (black screen).
                      // With both children positioned the Stack fills the
                      // Scaffold body.
                      const Positioned(
                        width: 0,
                        height: 0,
                        child: ActiveTabCxpEmitter(),
                      ),
                    ],
                  ),
                ),
                // With tabs open, `ProjectTabContent` mounts the real
                // `NetcruxStatusBar` at the bottom of each tab. With none,
                // that bar has nowhere to live and the window used to simply
                // lose its bottom edge — while WaveCrux and LintCrux kept
                // theirs on the same empty canvas. The idle bar reads nothing,
                // so it stays clear of the per-tab-scope hazard
                // `active_tab_container.dart` documents. It is the bottom-chrome
                // keyboard region while no tab is open.
                if (ref.watch(
                  netcruxWorkspaceProvider.select(
                    (ws) => ws.value?.tabs.isEmpty ?? true,
                  ),
                ))
                  CruxFocusRegion(child: NetcruxStatusBar.idle(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The tab panes, or the start screen while no tab is open.
  Widget _buildPaneHost(L10N l10n, WorkspaceManagersScope scope) =>
      PaneHost<NetcruxTabPayload>(
        provider: netcruxWorkspaceProvider,
        tabs: scope.tabContainerManager,
        panes: scope.paneContainerManager,
        strings: NetcruxViewerTabBarStrings(l10n),
        // Only show the tab-strip scroll chevrons when the strip actually
        // overflows — with a single tab they were inert arrows at each end of
        // the bar that did nothing.
        autoHideScrollChevrons: true,
        // Canonical (WaveCrux) tab-chip shape: filename + X only. No leading
        // drag handle (whole-chip drag still reorders) and no "+" new-tab
        // button — the "+" only opens an empty, unpopulatable tab; File > Open
        // is how you get a populated tab.
        useDragHandle: false,
        // Full-path hover tooltip + monospace context-menu header + platform
        // Reveal (suite tab-bar canon).
        tabFilePath: (tab) => tab.payload.projectFilePath,
        onRevealTab: revealTabFile,
        tabContentBuilder: (ctx, tab) => const ProjectTabContent(),
        // Per-pane render-stats affordance. The builder runs inside
        // the pane's own provider scope, so the button resolves that pane's
        // stats without being told which pane it belongs to. It hides itself
        // when diagnostics are off.
        paneTrailingActionsBuilder: (_, _) => const PaneRenderStatsButton(),
        // The start screen is the primary region: where lost focus goes back
        // to while no tab is open. It is not inside a `CruxIdeLayout` (that
        // mounts per tab), so it needs its own region. `EmptyCanvasState`
        // names itself after its title, so the region carries no label.
        emptyCanvasContent: CruxFocusRegion(
          primary: true,
          // The browser can open a netlist and nothing else, and keeps no
          // recents worth listing, so it gets its own start screen.
          child: ref.watch(hdlElaborationSupportedProvider)
              ? EmptyCanvasContent(
                  onOpenProject: _onOpenProjectPressed,
                  onOpenSourceFiles: _onOpenSourceFilesPressed,
                  onOpenWorkspace: _onOpenWorkspacePressed,
                  onPickRecentProject: _openProjectByPath,
                  onPickRecentSourceFile: (path) =>
                      _openSourceFilesByPaths(<String>[path]),
                  onPickRecentWorkspace: _openWorkspaceByPath,
                  onClearRecent: _clearRecent,
                )
              : BrowserEmptyCanvasContent(
                  onOpenNetlistJson: _onOpenNetlistJsonPressed,
                ),
        ),
      );

  // ---------------------------------------------------------------------------
  // File-open flows
  // ---------------------------------------------------------------------------

  Future<void> _onOpenProjectPressed() async {
    final l10n = L10N.of(context);
    final service = ref.read(fileOpenServiceProvider);
    final FileOpenResult result;
    try {
      result = await service.pickProject(
        dialogTitle: l10n.filePickerProjectDialogTitle,
      );
    } on Object catch (e) {
      if (!mounted) return;
      showCruxErrorSnack(context, l10n.filePickerFailed('$e'));
      return;
    }
    if (result.isCancelled) return;
    await _openProjectByPath(result.paths.single);
  }

  Future<void> _onOpenSourceFilesPressed() async {
    final l10n = L10N.of(context);
    final service = ref.read(fileOpenServiceProvider);
    final FileOpenResult result;
    try {
      result = await service.pickSourceFiles(
        dialogTitle: l10n.filePickerSourcesDialogTitle,
      );
    } on Object catch (e) {
      if (!mounted) return;
      showCruxErrorSnack(context, l10n.filePickerFailed('$e'));
      return;
    }
    if (result.isCancelled) return;
    await _openSourceFilesByPaths(result.paths);
  }

  Future<void> _onOpenNetlistJsonPressed() async {
    final l10n = L10N.of(context);
    final service = ref.read(fileOpenServiceProvider);
    final FileOpenResult result;
    try {
      result = await service.pickNetlistJson(
        dialogTitle: l10n.filePickerNetlistDialogTitle,
      );
    } on Object catch (e) {
      if (!mounted) return;
      showCruxErrorSnack(context, l10n.filePickerFailed('$e'));
      return;
    }
    if (result.isCancelled || !mounted) return;
    final location = result.paths.single;
    // Remembered with the recent source files, which reopen through the same
    // single-source path. A browser upload is a `blob:` URL that dies with
    // the page, so only a desktop path is worth remembering.
    if (ref.read(hdlElaborationSupportedProvider)) {
      await ref.read(appSettingsProvider.notifier).recordRecentSourceFiles(
        <String>[location],
      );
      if (!mounted) return;
    }
    await _openDesignTab(
      recentPath: null,
      displayName: NetcruxProject.locationLabel(location),
      project: NetcruxProject.create(sourceFiles: <String>[location]),
      source: NetcruxDesignSource.netlistJson,
    );
  }

  /// Opens the netlist a web viewer URL names (`?json=`), then applies its
  /// `#scope=` / `#sig=` hints once it has loaded.
  ///
  /// A fetch that fails — most often a server that does not allow
  /// cross-origin requests — leaves the tab on its error view and says why
  /// in a snackbar.
  Future<void> _openWebLaunchNetlist() async {
    final params = ref.read(webLaunchParamsProvider);
    final url = params.jsonUrl;
    if (url == null || !mounted) return;
    final l10n = L10N.of(context);
    await _openDesignTab(
      recentPath: null,
      displayName: NetcruxProject.locationLabel(url),
      project: NetcruxProject.create(sourceFiles: <String>[url]),
      source: NetcruxDesignSource.rtl,
    );
    if (!mounted) return;
    final tab = ref.activeTabContainerOrNull(context);
    if (tab == null) return;
    final NetlistModel? model;
    try {
      model = await tab.read(loadedNetlistProvider.future);
    } on Object {
      if (!mounted) return;
      showCruxErrorSnack(context, l10n.webNetlistLoadFailed(url));
      return;
    }
    if (model == null || !mounted) return;
    WebDeepLink.fromLaunchParams(params).applyTo(tab, model);
  }

  Future<void> _onOpenWorkspacePressed() async {
    final l10n = L10N.of(context);
    final service = ref.read(fileOpenServiceProvider);
    final FileOpenResult result;
    try {
      result = await service.pickWorkspace(
        dialogTitle: l10n.workspaceOpenWorkspaceTitle,
      );
    } on Object catch (e) {
      if (!mounted) return;
      showCruxErrorSnack(context, l10n.filePickerFailed('$e'));
      return;
    }
    if (result.isCancelled) return;
    await _openWorkspaceByPath(result.paths.single);
  }

  Future<void> _openProjectByPath(String rawPath) async {
    if (!mounted) return;
    final l10n = L10N.of(context);

    // A `<design>.crux-project` manifest, or a design directory holding one,
    // is swapped for what it names before the ordinary open flow runs, so tab
    // reuse and elaboration behave exactly as they do for a directly-opened
    // design. NetCrux is the one product that can act on either half of a
    // manifest: a pre-built netlist, or `design.sources` (with `design.top`)
    // it elaborates itself. Recents record the manifest file, so reopening it
    // re-reads what it names.
    switch (const CruxProjectResolver().resolve(rawPath)) {
      case final ManifestUnusable unusable:
        showCruxErrorSnack(context, _manifestUnusableMessage(l10n, unusable));
      case ManifestAmbiguous(:final directory, :final candidates):
        showCruxErrorSnack(
          context,
          l10n.cruxProjectAmbiguous(
            directory,
            candidates.map(p.basename).join(', '),
          ),
        );
      case ManifestNetlist(
        :final manifestPath,
        :final netlistPath,
        :final displayName,
        :final legacyRenameTo,
      ):
        await _openDesignTab(
          recentPath: manifestPath,
          displayName: displayName,
          project: NetcruxProject.create(sourceFiles: <String>[netlistPath]),
          source: NetcruxDesignSource.project,
          projectFilePath: manifestPath,
        );
        _noticeLegacyManifestName(legacyRenameTo);
      case ManifestSources(
        :final manifestPath,
        :final sources,
        :final top,
        :final displayName,
        :final legacyRenameTo,
      ):
        await _openDesignTab(
          recentPath: manifestPath,
          displayName: displayName,
          project: NetcruxProject.create(
            sourceFiles: sources,
            topModule: top ?? '',
          ),
          source: NetcruxDesignSource.project,
          projectFilePath: manifestPath,
        );
        _noticeLegacyManifestName(legacyRenameTo);
      case NotAManifest(:final path)
          when _hasSuffix(path, NetcruxSession.fileExtension):
        await _openSessionByPath(path);
      case NotAManifest(:final path)
          when _hasSuffix(path, kNetcruxProjectExtension):
        await ref.read(appSettingsProvider.notifier).recordRecentProject(path);
        final NetcruxProject project;
        try {
          project = await _readNetcruxProject(path);
        } on NetcruxProjectVersionException catch (e) {
          if (!mounted) return;
          showCruxErrorSnack(
            context,
            l10n.projectLoadUnknownVersion(e.version),
          );
          return;
        } on Object catch (e) {
          if (!mounted) return;
          showCruxErrorSnack(context, l10n.projectLoadFailed(e.toString()));
          return;
        }
        // The project itself is what gets pushed into the tab, not one
        // rebuilt from the payload's source list: the elaboration knobs a
        // project file carries (defines, include paths, extra Yosys
        // commands, structural lowering) have no home on the tab payload.
        await _openDesignTab(
          recentPath: null,
          displayName: p.basenameWithoutExtension(path),
          project: project,
          source: NetcruxDesignSource.project,
          projectFilePath: path,
        );
      case NotAManifest(:final path):
        await _openDesignTab(
          recentPath: path,
          displayName: p.basename(path),
          project: NetcruxProject.create(sourceFiles: <String>[path]),
          source: NetcruxDesignSource.rtl,
        );
    }
  }

  /// Whether [path] ends in `.<extension>`, ignoring case — the command line
  /// routes `Demo.NetCrux-Project` here, so the branch has to agree.
  static bool _hasSuffix(String path, String extension) =>
      path.toLowerCase().endsWith('.$extension');

  /// Reads a `.netcrux-project` file with its relative paths anchored to the
  /// project's own directory — a committed project file carries relative
  /// paths so it can travel between checkouts.
  static Future<NetcruxProject> _readNetcruxProject(String path) async {
    final project = await const NetcruxProjectFileReader().read(path);
    return resolveProjectPaths(project, p.dirname(path));
  }

  /// The localized explanation for a manifest path NetCrux cannot open.
  static String _manifestUnusableMessage(L10N l10n, ManifestUnusable u) =>
      switch (u.reason) {
        ManifestUnusableReason.invalid => l10n.cruxProjectInvalid(u.detail),
        ManifestUnusableReason.netlistMissing => l10n.cruxProjectNetlistMissing(
          u.detail,
        ),
        ManifestUnusableReason.nothingToOpen => l10n.cruxProjectNothingToOpen(
          u.detail,
        ),
        ManifestUnusableReason.noManifestInDirectory =>
          l10n.cruxProjectNoneInDirectory(
            u.detail,
            suggestedCruxProjectFileName(u.detail),
          ),
      };

  /// Tells the user, once for this open, that the design they just opened
  /// was read from the legacy bare `.crux-project` file name and what to
  /// rename it to. A no-op for a named manifest ([renameTo] is null).
  void _noticeLegacyManifestName(String? renameTo) {
    if (renameTo == null || !mounted) return;
    showCruxInfoSnack(
      context,
      L10N.of(context).cruxProjectLegacyFileName(renameTo),
    );
  }

  /// Opens [project] in a tab (focusing an existing tab for the same design)
  /// and pushes it into that tab's elaboration pipeline.
  ///
  /// [recentPath] is recorded in recents first when non-null. [projectFilePath]
  /// is the project or manifest the design came from, when it came from one.
  Future<void> _openDesignTab({
    required String? recentPath,
    required String displayName,
    required NetcruxProject project,
    required NetcruxDesignSource source,
    String? projectFilePath,
  }) async {
    if (recentPath != null) {
      await ref
          .read(appSettingsProvider.notifier)
          .recordRecentProject(recentPath);
    }
    if (!mounted) return;
    await ref
        .read(netcruxWorkspaceProvider.notifier)
        .openTab(
          displayName: displayName,
          payload: NetcruxTabPayload(
            sourceFiles: project.sourceFiles,
            topModule: project.topModule,
            projectFilePath: projectFilePath,
          ),
        );
    if (!mounted) return;
    // The opened (or focused) tab is now active.
    ref
        .activeTabContainerOrNull(context)
        ?.read(currentProjectProvider.notifier)
        .setProject(project, source: source);
  }

  /// Opens the `.netcrux` session at [path]: a tab for the session's design,
  /// then the session's view state restored into it.
  ///
  /// The session is read before any tab exists, because the tab's source list
  /// is the session's — a session is never itself an elaboration input.
  Future<void> _openSessionByPath(String path) async {
    if (!mounted) return;
    final l10n = L10N.of(context);
    final messenger = ScaffoldMessenger.of(context);
    await ref.read(appSettingsProvider.notifier).recordRecentProject(path);
    final NetcruxSession session;
    try {
      session = await SessionController.readSession(path);
    } on NetcruxSessionVersionException catch (e) {
      if (!mounted) return;
      showCruxErrorSnack(context, l10n.sessionLoadUnknownVersion(e.version));
      return;
    } on Object catch (e) {
      if (!mounted) return;
      showCruxErrorSnack(context, l10n.sessionLoadFailed(e.toString()));
      return;
    }
    if (!mounted) return;
    await ref
        .read(netcruxWorkspaceProvider.notifier)
        .openTab(
          displayName: p.basenameWithoutExtension(path),
          payload: NetcruxTabPayload(
            sourceFiles: session.sourceFilePaths,
            topModule: session.topModule,
          ),
        );
    if (!mounted) return;
    final container = ref.activeTabContainerOrNull(context);
    if (container == null) return;
    await SessionController(
      container: container,
      messenger: messenger,
      l10n: l10n,
    ).apply(session);
  }

  Future<void> _openSourceFilesByPaths(List<String> paths) async {
    if (paths.isEmpty || !mounted) return;
    await ref.read(appSettingsProvider.notifier).recordRecentSourceFiles(paths);
    if (!mounted) return;
    final displayName = paths.length == 1
        ? p.basename(paths.first)
        : '${paths.length} files';
    await ref
        .read(netcruxWorkspaceProvider.notifier)
        .openTab(
          displayName: displayName,
          payload: NetcruxTabPayload(sourceFiles: paths),
        );
    if (!mounted) return;
    final container = ref.activeTabContainerOrNull(context);
    container?.read(currentProjectProvider.notifier).setSourceFiles(paths);
  }

  Future<void> _openWorkspaceByPath(String path) async {
    if (!mounted) return;
    final l10n = L10N.of(context);
    await ref.read(appSettingsProvider.notifier).recordRecentWorkspace(path);
    if (!mounted) return;
    try {
      await ref.read(netcruxWorkspaceProvider.notifier).loadFrom(path);
      // After load, hydrate each tab's currentProjectProvider so the
      // elaboration pipeline restarts.
      await _hydrateActiveTabFromWorkspace();
    } on Object catch (e) {
      if (!mounted) return;
      showCruxErrorSnack(context, l10n.projectLoadFailed(e.toString()));
    }
  }

  /// Pushes each restored tab's design into its pipeline.
  ///
  /// A tab opened from a `.netcrux-project` is re-read from that file: the
  /// payload carries only its sources and top module, and rebuilding the
  /// project from those silently dropped its defines, include paths, extra
  /// Yosys commands and lowering, so the restored tab elaborated a different
  /// design. When the file cannot be read any more, the payload is the best
  /// there is.
  Future<void> _hydrateActiveTabFromWorkspace() async {
    final ws = ref.read(netcruxWorkspaceProvider).value;
    if (ws == null) return;
    if (!mounted) return;
    final scope = WorkspaceManagersScope.of(context);
    for (final tab in ws.tabs) {
      final container = scope.tabContainerManager.containerFor(tab.id);
      final payload = tab.payload;
      final projectFile = payload.projectFilePath;
      if (projectFile != null &&
          _hasSuffix(projectFile, kNetcruxProjectExtension)) {
        try {
          final project = await _readNetcruxProject(projectFile);
          if (!mounted) return;
          container
              .read(currentProjectProvider.notifier)
              .setProject(project, source: NetcruxDesignSource.project);
          continue;
        } on Object {
          if (!mounted) return;
        }
      }
      if (payload.sourceFiles.isEmpty) continue;
      container
          .read(currentProjectProvider.notifier)
          .setProject(
            NetcruxProject.create(
              sourceFiles: payload.sourceFiles,
              topModule: payload.topModule,
            ),
            source: projectFile == null
                ? NetcruxDesignSource.rtl
                : NetcruxDesignSource.project,
          );
    }
  }

  Future<void> _clearRecent() async {
    await ref.read(appSettingsProvider.notifier).clearRecentFiles();
  }

  // ---------------------------------------------------------------------------
  // Action dispatch
  // ---------------------------------------------------------------------------

  /// The exhaustive [NetcruxAction] switch and every dispatch-only
  /// handler live in [WorkspaceActionDispatcher]; the screen keeps this
  /// thin delegation so the
  /// three discovery surfaces wired in [build] keep routing through one
  /// name. The two file-open flows shared with [EmptyCanvasContent] are
  /// injected as callbacks.
  late final WorkspaceActionDispatcher _dispatcher = WorkspaceActionDispatcher(
    ref: ref,
    openProject: _onOpenProjectPressed,
    openSourceFiles: _onOpenSourceFilesPressed,
    openNetlistJson: _onOpenNetlistJsonPressed,
    openWorkspaceFlow: _onOpenWorkspacePressed,
  );

  void _dispatchAction(BuildContext context, NetcruxAction action) =>
      _dispatcher.dispatch(context, action);
}
