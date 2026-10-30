// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_cxp_ui/crux_cxp_ui.dart' show cruxCxpRuntimeProvider;
import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter/foundation.dart' show listEquals;
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
import 'package:netcrux/features/remote/widgets/cxp_inbound_handler_publisher.dart';
import 'package:netcrux/features/remote/widgets/cxp_outbound_emitter.dart';
import 'package:netcrux/features/viewer/widgets/netcrux_status_bar.dart';
import 'package:netcrux/features/viewer/widgets/netcrux_toolbar.dart';
import 'package:netcrux/features/workspace/providers/netcrux_action_context_provider.dart';
import 'package:netcrux/features/workspace/providers/recent_lists.dart';
import 'package:netcrux/features/workspace/services/active_tab_container.dart';
import 'package:netcrux/features/workspace/services/active_tab_navigator.dart';
import 'package:netcrux/features/workspace/services/restored_tab_project.dart';
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
import 'package:netcrux/services/filelist/filelist_reader.dart';
import 'package:netcrux/services/host_bridge/editor_host_providers.dart';
import 'package:netcrux/services/host_bridge/host_bridge_messages.dart';
import 'package:netcrux/services/host_bridge/host_netlist_blob.dart';
import 'package:netcrux/services/host_bridge/host_netlist_request_provider.dart';
import 'package:netcrux/services/project/netcrux_project_file.dart';
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

  /// Netlists an editor host sends, opened one at a time in arrival order.
  Future<void> _hostNetlistQueue = Future<void>.value();

  /// The location of the netlist the editor host's tab shows, kept so the
  /// next one can replace it and release it.
  String? _hostNetlistLocation;

  /// Whether the editor host's netlist already has a tab. A later netlist from
  /// the same host is the same document reloaded, so it replaces that tab's
  /// design instead of adding another tab.
  bool _hostNetlistTabOpen = false;

  @override
  void initState() {
    super.initState();
    // A netlist the editor host sends after this point. Not fired
    // immediately: a provider is not modified while the tree builds, and one
    // sent before the screen existed is taken after the first frame.
    ref.listenManual<HostNetlistRequest?>(hostNetlistRequestProvider, (
      _,
      next,
    ) {
      if (next != null) _takeHostNetlistRequest();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_handleAutoLaunch());
      _takeHostNetlistRequest();
    });
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
  ///
  /// Whatever the intent opens, every tab restored from the saved workspace
  /// then gets its design too. The hydration used to belong to the empty
  /// launch alone, so a launch that named a file restored the other tabs
  /// without their sources and each showed the "Open Project..." placeholder
  /// when it was switched to.
  Future<void> _applyLaunchIntent(CliLaunchIntent intent) async {
    await _openLaunchIntent(intent);
    if (!mounted) return;
    await _hydrateActiveTabFromWorkspace();
  }

  Future<void> _openLaunchIntent(CliLaunchIntent intent) async {
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
        // (one tab per file). Liberty cell libraries on the command line
        // are not designs of their own: every tab gets all of them.
        final libraries = paths.where(NetcruxProject.isLibertyPath).toList();
        final sources = paths
            .where((path) => !NetcruxProject.isLibertyPath(path))
            .toList();
        if (sources.isEmpty) {
          await _openSourceFilesByPaths(libraries);
        }
        for (final path in sources) {
          await _openSourceFilesByPaths(<String>[path, ...libraries]);
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
    // Start the shared CXP runtime with the workspace, as before, rather than
    // on the first cross-probe: discovery and the outbound connector need time
    // to finish their handshakes before anyone opens the menu. Listened, not
    // watched, so the screen does not rebuild as the server comes up.
    ref.listen(cruxCxpRuntimeProvider, (_, _) {});
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
        // CxpInboundHandlerPublisher wraps the body so every CXP inbound
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
        body: CxpInboundHandlerPublisher(
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
        // Each tab's content sits on its own navigator, so a dialog that
        // reads the tab's state is pushed there (`ActiveTab.navigatorFor`)
        // under the tab's one scope instead of a second scope over its
        // container.
        tabNavigators: ref.read(tabNavigatorsProvider),
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
    await _openDesignTab(
      recentPath: null,
      displayName: NetcruxProject.locationLabel(location),
      project: NetcruxProject.create(sourceFiles: <String>[location]),
      source: NetcruxDesignSource.netlistJson,
    );
    // Remembered with the recent source files, which reopen through the same
    // single-source path. A browser upload is a `blob:` URL that dies with
    // the page, so only a desktop path is worth remembering.
    if (mounted && ref.read(hdlElaborationSupportedProvider)) {
      ref.read(recentSources.provider.notifier).markOpened(location);
    }
  }

  /// Takes the pending netlist the editor host sent, if any, and queues it.
  void _takeHostNetlistRequest() {
    final request = ref.read(hostNetlistRequestProvider);
    if (request == null) return;
    // Cleared at once: the text can be tens of megabytes.
    ref.read(hostNetlistRequestProvider.notifier).clear();
    _hostNetlistQueue = _hostNetlistQueue.then((_) async {
      if (mounted) await _openHostNetlist(request.netlist);
    });
  }

  /// Opens the netlist an editor host sent as text, then applies its scope and
  /// signal hints once it has loaded.
  ///
  /// It takes the route a browser upload takes: a location the netlist loader
  /// fetches, with the document's name as the fragment. The first netlist gets
  /// a tab; a later one is the same document reloaded and replaces that tab's
  /// design. The editor is told how it went, so a failure is in its log and not
  /// only on a canvas it may not be looking at.
  Future<void> _openHostNetlist(HostBridgeOpenNetlist netlist) async {
    await ref.read(netcruxWorkspaceProvider.future);
    if (!mounted) return;
    final bridge = ref.read(editorHostBridgeProvider)
      ..reportStatus(HostBridgeStatusPhase.loading, message: netlist.name);
    final previous = _hostNetlistLocation;
    final location = createHostNetlistLocation(netlist.name, netlist.text);
    _hostNetlistLocation = location;
    final project = NetcruxProject.create(sourceFiles: <String>[location]);
    var tab = _hostNetlistTabOpen
        ? ref.activeTabContainerOrNull(context)
        : null;
    if (tab != null) {
      tab
          .read(currentProjectProvider.notifier)
          .setProject(project, source: NetcruxDesignSource.netlistJson);
    } else {
      await _openDesignTab(
        recentPath: null,
        displayName: netlist.name,
        project: project,
        source: NetcruxDesignSource.netlistJson,
      );
      if (!mounted) return;
      _hostNetlistTabOpen = true;
      tab = ref.activeTabContainerOrNull(context);
    }
    if (previous != null) releaseHostNetlistLocation(previous);
    if (tab == null) return;
    final l10n = L10N.of(context);
    final NetlistModel? model;
    try {
      model = await tab.read(loadedNetlistProvider.future);
    } on Object catch (e) {
      bridge.reportStatus(HostBridgeStatusPhase.failed, message: '$e');
      if (!mounted) return;
      showCruxErrorSnack(
        context,
        l10n.hostNetlistLoadFailed(netlist.name, '$e'),
      );
      return;
    }
    if (model == null || !mounted) return;
    bridge.reportStatus(
      HostBridgeStatusPhase.loaded,
      message: netlist.name,
      modules: model.modules.length,
      cells: model.modules.values.fold<int>(
        0,
        (total, module) => total + module.cells.length,
      ),
    );
    WebDeepLink(
      scope: netlist.scope,
      signal: netlist.signal,
    ).applyTo(tab, model);
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
        if (!mounted) return;
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
        // Recorded once the project has read and opened, so a file that does
        // not read never lands in Recent.
        if (!mounted) return;
        ref.read(recentProjects.provider.notifier).markOpened(path);
      case NotAManifest(:final path) when _hasSuffix(path, kFilelistExtension):
        await _openFilelistByPath(path);
      case NotAManifest(:final path):
        await _openDesignTab(
          recentPath: path,
          displayName: p.basename(path),
          project: NetcruxProject.create(sourceFiles: <String>[path]),
          source: NetcruxDesignSource.rtl,
        );
    }
  }

  /// Opens the Vivado-style `.f` filelist at [path] as a design. The import
  /// action, a Recent Projects entry and a command-line argument all arrive
  /// here, so a filelist is expanded through [FilelistReader] on every route
  /// rather than handed to Yosys as a Verilog source, which is what the
  /// fall-through case above would do with it. The filelist is recorded as
  /// the tab's project file, so a restore re-reads it, defines and include
  /// paths included.
  Future<void> _openFilelistByPath(String path) async {
    if (!mounted) return;
    final l10n = L10N.of(context);
    final NetcruxProject project;
    try {
      project = await const FilelistReader().readAsProject(path);
    } on Object catch (e) {
      if (!mounted) return;
      showCruxErrorSnack(context, l10n.projectLoadFailed(e.toString()));
      return;
    }
    await _openDesignTab(
      recentPath: path,
      displayName: p.basenameWithoutExtension(path),
      project: project,
      source: NetcruxDesignSource.filelist,
      projectFilePath: path,
    );
  }

  /// Whether [path] ends in `.<extension>`, ignoring case — the command line
  /// routes `Demo.NetCrux-Project` here, so the branch has to agree.
  static bool _hasSuffix(String path, String extension) =>
      hasFileSuffix(path, extension);

  /// Reads a `.netcrux-project` file with its relative paths anchored to the
  /// project's own directory — a committed project file carries relative
  /// paths so it can travel between checkouts.
  static Future<NetcruxProject> _readNetcruxProject(String path) =>
      readNetcruxProjectFile(path);

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
  /// [recentPath] is recorded in recents once the design is open, when
  /// non-null. [projectFilePath] is the project or manifest the design came
  /// from, when it came from one.
  Future<void> _openDesignTab({
    required String? recentPath,
    required String displayName,
    required NetcruxProject project,
    required NetcruxDesignSource source,
    String? projectFilePath,
  }) async {
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
    if (recentPath != null) {
      ref.read(recentProjects.provider.notifier).markOpened(recentPath);
    }
  }

  /// Opens the `.netcrux` session at [path]: a tab for the session's design,
  /// then the session's view state restored into it.
  ///
  /// The session is read before any tab exists, because the tab's source list
  /// is the session's — a session is never itself an elaboration input.
  Future<void> _openSessionByPath(String path) async {
    if (!mounted) return;
    final l10n = L10N.of(context);
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
    // The session read and its tab is open: now it is a recent project.
    ref.read(recentProjects.provider.notifier).markOpened(path);
    final container = ref.activeTabContainerOrNull(context);
    if (container == null) return;
    await SessionController(
      container: container,
      context: context,
      l10n: l10n,
    ).apply(session);
  }

  /// Opens [paths] as one design tab. Liberty cell libraries among them
  /// (`.lib`, `.liberty`) become the project's cell libraries rather than
  /// sources ([NetcruxProject.fromOpenedFiles]); only the sources are
  /// recorded as recent files, since a library alone is not a design.
  Future<void> _openSourceFilesByPaths(List<String> requested) async {
    if (requested.isEmpty || !mounted) return;
    // A path typed on the command line is relative to the directory the app
    // was started in. Made absolute here, so a later Save Project As writes
    // it relative to the project file, as it does a path picked in a dialog;
    // kept as typed, `design/top.v` was saved verbatim and then read against
    // the project file's folder.
    final paths = <String>[
      for (final path in requested) p.normalize(p.absolute(path)),
    ];
    final project = NetcruxProject.fromOpenedFiles(paths);
    final named = project.sourceFiles.isEmpty ? paths : project.sourceFiles;
    final displayName = named.length == 1
        ? p.basename(named.first)
        : '${named.length} files';
    final libraries = project.libertyFiles.isEmpty
        ? null
        : project.libertyFiles;
    final workspace = ref.read(netcruxWorkspaceProvider.notifier);
    final tabId = await workspace.openTab(
      displayName: displayName,
      payload: NetcruxTabPayload(
        sourceFiles: project.sourceFiles,
        libertyFiles: libraries,
      ),
    );
    if (!mounted) return;
    // The same sources may already be open, and then openTab focuses that
    // tab and keeps its payload: bring its cell libraries (and black-box
    // option, which a fresh open leaves off) in line with the project about
    // to be set, so a restore agrees with what is shown.
    final opened = ref
        .read(netcruxWorkspaceProvider)
        .value
        ?.tabs
        .where((tab) => tab.id == tabId)
        .firstOrNull;
    if (opened != null &&
        (!listEquals(opened.payload.libertyFiles, libraries) ||
            opened.payload.blackBoxMissingModules != null)) {
      await workspace.updateTabPayload(
        tabId,
        (payload) => libraries == null
            ? payload.copyWith(
                clearLibertyFiles: true,
                clearBlackBoxMissingModules: true,
              )
            : payload.copyWith(
                libertyFiles: libraries,
                clearBlackBoxMissingModules: true,
              ),
      );
      if (!mounted) return;
    }
    final container = ref.activeTabContainerOrNull(context);
    container?.read(currentProjectProvider.notifier).setProject(project);
    // Newest last, so the first path ends up first in the list. A cell
    // library alone is not a design, so only sources are recorded.
    project.sourceFiles.reversed.forEach(
      ref.read(recentSources.provider.notifier).markOpened,
    );
  }

  Future<void> _openWorkspaceByPath(String path) async {
    if (!mounted) return;
    final l10n = L10N.of(context);
    try {
      await ref.read(netcruxWorkspaceProvider.notifier).loadFrom(path);
      // After load, hydrate each tab's currentProjectProvider so the
      // elaboration pipeline restarts.
      await _hydrateActiveTabFromWorkspace();
      // Recorded once the workspace has loaded.
      if (mounted) {
        ref.read(recentWorkspaces.provider.notifier).markOpened(path);
      }
    } on Object catch (e) {
      if (!mounted) return;
      showCruxErrorSnack(context, l10n.projectLoadFailed(e.toString()));
    }
  }

  /// Pushes each restored tab's design into its pipeline.
  ///
  /// A tab's project lives in its own container, so every tab restored from
  /// `workspace.json` starts without one. This runs after whatever the launch
  /// opened, for every launch route, and gives each tab that still has no
  /// design the one its payload names (see [hydrateTabProject]); a tab the
  /// launch has just opened already has its project and is left alone.
  Future<void> _hydrateActiveTabFromWorkspace() async {
    final ws = ref.read(netcruxWorkspaceProvider).value;
    if (ws == null) return;
    if (!mounted) return;
    final scope = WorkspaceManagersScope.of(context);
    for (final tab in ws.tabs) {
      // A tab closed while an earlier one was being read has no container
      // to fill: asking for it would create an orphan.
      final open =
          ref
              .read(netcruxWorkspaceProvider)
              .value
              ?.tabs
              .any((t) => t.id == tab.id) ??
          false;
      if (!open) continue;
      final container = scope.tabContainerManager.containerFor(tab.id);
      await hydrateTabProject(
        container,
        tab.payload,
        isCurrent: () => mounted,
      );
      if (!mounted) return;
    }
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
    openDesignByPath: _openProjectByPath,
  );

  void _dispatchAction(BuildContext context, NetcruxAction action) =>
      _dispatcher.dispatch(context, action);
}
