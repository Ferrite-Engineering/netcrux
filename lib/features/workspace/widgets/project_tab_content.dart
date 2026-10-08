// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/core/providers/workspace_banner_widgets_provider.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/selection/selection.dart';
import 'package:netcrux/features/collaboration/collab_presence_overlay_provider.dart';
import 'package:netcrux/features/collaboration/collab_presence_publisher.dart';
import 'package:netcrux/features/collaboration/collab_presenter_bridge.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/project/providers/current_laid_out_graph_provider.dart';
import 'package:netcrux/features/project/providers/current_project_provider.dart';
import 'package:netcrux/features/project/providers/loaded_netlist_provider.dart';
import 'package:netcrux/features/remote/providers/cxp_server_provider.dart';
import 'package:netcrux/features/statistics/widgets/netcrux_stats_strip.dart';
import 'package:netcrux/features/viewer/providers/pane_render_stats.dart';
import 'package:netcrux/features/viewer/providers/schematic_canvas_key_provider.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/features/viewer/providers/trace_overlay_notifier.dart';
import 'package:netcrux/features/viewer/providers/viewport_transform_notifier.dart';
import 'package:netcrux/features/viewer/rendering/schematic_painter.dart';
import 'package:netcrux/features/viewer/symbols/cell_body_painter_factory_provider.dart';
import 'package:netcrux/features/viewer/widgets/breadcrumb_bar.dart';
import 'package:netcrux/features/viewer/widgets/netcrux_ide_layout.dart';
import 'package:netcrux/features/viewer/widgets/netcrux_status_bar.dart';
import 'package:netcrux/features/viewer/widgets/schematic_gesture_handler.dart';
import 'package:netcrux/features/viewer/widgets/schematic_scrollbars.dart';
import 'package:netcrux/features/workspace/widgets/netcrux_docks.dart';
import 'package:netcrux/features/workspace/widgets/schematic_error_view.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/collaboration/netlist_fingerprint.dart';
import 'package:netcrux/services/collaboration/schematic_collaboration_service_provider.dart';
import 'package:netcrux/services/custom_cell_symbols/custom_cell_symbol_registry_provider.dart';
import 'package:netcrux/services/reload/source_file_watcher_provider.dart';
import 'package:netcrux/services/remote/cxp/cxp_workspace_link.dart';
import 'package:netcrux/services/schematic/coi_filter_view_mode_provider.dart';
import 'package:netcrux/services/schematic/net_activity_color_override_provider.dart';
import 'package:netcrux/services/schematic/schematic_annotation_markers_provider.dart';
import 'package:netcrux/services/schematic/schematic_crossing_overlay_provider.dart';
import 'package:netcrux/services/yosys/prebuilt_netlist_loader_provider.dart';

/// Per-tab content rendered inside [`PaneHost`]'s `IndexedStack` of tabs.
///
/// Lives **inside** the per-tab `UncontrolledProviderScope` the package's
/// [`PaneHost`] establishes, so every Riverpod read here resolves to this
/// tab's container — its own [`currentProjectProvider`],
/// [`loadedNetlistProvider`], [`hierarchyTreeProvider`],
/// [`viewportTransformProvider`], [`selectedElementProvider`],
/// [`traceOverlayProvider`], and [`paneRenderStatsProvider`] (the last
/// resolves from the hosting pane's container, not this tab's, but the
/// lookup is transparent to widgets).
///
/// Wires the per-tab listeners that used to live on the legacy
/// [`ProjectScreen`]:
/// * Forwards [`loadedNetlistProvider`] → [`hierarchyTreeProvider`] so the
///   tree refreshes when elaboration completes.
/// * Activates [`sourceFileWatcherProvider`] so this tab's source files
///   are watched (per-tab — only this tab re-elaborates when its files
///   change).
/// * Surfaces prompt-mode reload events as a snackbar.
///
/// Renders the breadcrumb + schematic canvas. The hierarchy panel,
/// inspector, and diagnostics drawer live at the workspace level (in the
/// outer `IdeLayout`'s side panes) and look up the active tab's container
/// via [`ActiveTabScope`].
class ProjectTabContent extends ConsumerWidget {
  /// Creates the per-tab content widget.
  const ProjectTabContent({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    ref
      ..listen<AsyncValue<NetlistModel?>>(
        loadedNetlistProvider,
        (previous, next) {
          final model = next.value;
          if (model == null) return;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!context.mounted) return;
            // Only the design the tab settled on reaches the tree, and it is
            // read again here rather than trusted from the change. A reload's
            // loading state still carries the design it is replacing as its
            // value, and when the replacement lands before the next frame —
            // a small netlist, a cache hit — a session restore has already
            // installed and navigated it by the time this runs. Handing the
            // tree the carried value then would put the replaced design back
            // and throw the restored scope to its root.
            final current = ref.read(loadedNetlistProvider);
            if (current.isLoading || !identical(current.value, model)) return;
            // Only a model the tree does not already hold resets it. Whoever
            // pushed this exact model in first — a session restore or a web
            // deep link — has already navigated it, and a second setModel
            // would throw that scope and expansion back to the root.
            if (identical(ref.read(hierarchyTreeProvider).model, model)) return;
            ref.read(hierarchyTreeProvider.notifier).setModel(model);
          });
          // Shared-workspace producer: publish this design's HDL source into
          // the shared workspace (keyed by its input directory) so a peer that
          // receives a cross-probe naming the same design can open NetCrux's
          // source even with nothing loaded. Best-effort + gated on the CXP
          // server running. The browser has neither peers nor a file system to
          // derive a design id from, so it skips the step outright.
          if (!ref.read(hdlElaborationSupportedProvider)) return;
          final project = ref.read(currentProjectProvider);
          final designId = cxpDesignIdForProject(project);
          if (designId != null) {
            unawaited(
              publishDesignSourceArtifact(
                ProviderScope.containerOf(context, listen: false),
                serverRunning: ref.read(cxpServerHostProvider).value != null,
                designId: designId,
                sourcePath: project.sourceFiles.first,
                topModule: model.topModule?.name ?? project.topModule,
              ),
            );
          }
        },
      )
      // ── collaborative presence ──────────────────────────────────────
      // Selection and scope are published on change rather than polled: both
      // are low-rate (a click, a breadcrumb push) so there is nothing to
      // throttle, and a listener is the only shape that catches a selection
      // set by something other than a click — a cross-probe, a search result,
      // an X-trace jump all land here too.
      //
      // Every one of these is a no-op with no session running. The Pro
      // overlay is what makes them do something; open core keeps the seam
      // warm.
      ..listen<Selection>(selectedElementProvider, (previous, next) {
        publishCollabSelection(ref, next);
      })
      ..listen<HierarchyTreeState>(hierarchyTreeProvider, (previous, next) {
        if (collabScopePath(previous?.selected) ==
            collabScopePath(next.selected)) {
          return;
        }
        final service = ref.read(schematicCollaborationServiceProvider);
        if (!service.isInSession) return;
        final model = ref.read(loadedNetlistProvider).value;
        service.announceScope(
          scopePath: collabScopePath(next.selected),
          netlistContentHash: model == null ? null : netlistFingerprint(model),
        );
      })
      ..watch(sourceFileWatcherProvider)
      ..listen<int?>(sourceReloadEventsProvider, (previous, next) {
        if (next == null) return;
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: Text(l10n.fileChangedSnackbar(next)),
              behavior: SnackBarBehavior.floating,
              action: SnackBarAction(
                label: l10n.autoReloadPromptAction,
                onPressed: () => ref.invalidate(loadedNetlistProvider),
              ),
            ),
          );
        ref.read(sourceReloadEventsProvider.notifier).clear();
      });

    // Level-triggered netlist→hierarchy reconciliation, complementing the
    // edge-triggered `ref.listen` above. The elaboration can resolve BEFORE
    // this widget's first build registers that listener: the root-scope
    // `ActiveTabActionFlagsNotifier` starts the pipeline (via its
    // `container.listen` on `currentLaidOutGraphProvider`) the moment the
    // tab is created, and an elaboration-cache hit then completes within a
    // few event-loop turns — while the native file-picker dismissal delays
    // the next Flutter frame. An edge-triggered listen alone never fires in
    // that ordering, leaving the hierarchy on its empty placeholder and the
    // canvas blank even though the status bar (a plain `ref.watch`) shows
    // the loaded design. Reconcile here: if the resolved model hasn't
    // reached the tree yet, push it after this frame. The identity guard
    // keeps this a no-op on every later build, so user selection/expansion
    // state is never clobbered; the post-frame deferral preserves the
    // no-setState-during-build invariant.
    final resolvedModel = ref.read(loadedNetlistProvider).value;
    if (resolvedModel != null &&
        !identical(ref.read(hierarchyTreeProvider).model, resolvedModel)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        final current = ref.read(loadedNetlistProvider).value;
        if (current == null) return;
        if (identical(ref.read(hierarchyTreeProvider).model, current)) return;
        ref.read(hierarchyTreeProvider.notifier).setModel(current);
      });
    }

    // Empty-project state — a tab whose payload has no source files yet
    // (typical for a freshly-opened "+" tab before the user has chosen
    // anything). Render a friendly hint so the canvas isn't a blank
    // area. The IDE chrome (hierarchy / inspector / diagnostics) still
    // surrounds it: this is an OPEN tab, just one without a design loaded.
    // The chrome-free state is the zero-tabs empty workspace, handled by
    // `PaneHost` one level up.
    final project = ref.watch(currentProjectProvider);
    final Widget center = project.sourceFiles.isEmpty
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                // The browser opens netlists only; point at what it can do.
                ref.watch(hdlElaborationSupportedProvider)
                    ? l10n.actionOpenProject
                    : l10n.actionOpenNetlistJson,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          )
        : const Column(
            children: <Widget>[
              BreadcrumbBar(),
              Divider(height: 1),
              Expanded(child: _SchematicCenter()),
            ],
          );

    // Per-tab IDE layout. Mounting it here (inside `PaneHost`'s per-tab
    // scope) rather than as outer workspace chrome is what keeps the
    // zero-tabs empty canvas chrome-free and aligns NetCrux with the
    // WaveCrux / LintCrux / SimCrux workspace-shell model. The side panels
    // read this tab's per-tab providers directly — no `ActiveTabScope`
    // needed.
    //
    // The design status bar pins to the bottom, spanning the full tab width
    // below the IDE panels. It is per-tab for
    // the same reason the panels are: it reads this tab's providers
    // directly, and the zero-tabs empty canvas (handled one level up) stays
    // chrome-free.
    //
    // Presenter mode rides the tab's own state, so it wraps the tab here,
    // inside the per-tab scope. Inert outside a collaborative session.
    return CollabPresenterBridge(
      child: Column(
        children: <Widget>[
          // Notices that need acting on, above everything. Empty in open core —
          // and empty in a Pro build too, unless something is actually wrong.
          ...ref.watch(workspaceBannerWidgetsProvider),
          Expanded(
            // Collapsed regions leave a slim restore bar along their edge
            // (JetBrains tool-window model — the suite panel-reopen canon).
            // Wrapped here in the workspace shell, which owns the dock
            // widgets, keeping the viewer-layer layout free of lateral
            // feature imports (`docs/ARCHITECTURE.md` §6.2).
            child: NetcruxDockRestoreBars(
              child: NetcruxIdeLayout(
                // Each region is a CruxDock: Hierarchy (titled header), the
                // tabbed Inspector / analysis / Cross-Probe dock, and the
                // Diagnostics drawer (titled header).
                hierarchyBuilder: (_, _) => const NetcruxLeftDock(),
                centerBuilder: (_, _) => center,
                inspectorBuilder: (_, _) => const NetcruxRightDock(),
                diagnosticsBuilder: (_, _) => const NetcruxBottomDock(),
              ),
            ),
          ),
          // The tab's bottom chrome is one keyboard region (an F6 stop). A
          // sibling of the IDE layout, whose panes are regions of their own, so
          // regions never nest.
          const CruxFocusRegion(
            child: Column(
              children: <Widget>[
                // Live statistics strip. Docks ABOVE the base status
                // bar: the status bar carries design identity (source file, top
                // module, cell count), the strip carries ambient telemetry, and
                // identity belongs closest to the window edge. Collapsed by
                // default, so it costs one 24 px disclosure row until asked for.
                NetcruxStatsStrip(),
                NetcruxStatusBar(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SchematicCenter extends ConsumerWidget {
  const _SchematicCenter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final laidOutAsync = ref.watch(currentLaidOutGraphProvider);
    final transform = ref.watch(viewportTransformProvider);
    final selection = ref.watch(selectedElementProvider);
    final overlay = ref.watch(traceOverlayProvider);
    final statsNotifier = ref.read(paneRenderStatsProvider.notifier);
    // Watch the snapshot first so the canvas repaints whenever the
    // Pro custom-cell-symbol registry mutates; reading the factory
    // alone is not enough because the Pro factory closes over the
    // snapshot map by identity.
    ref.watch(customCellSymbolSnapshotProvider);
    final cellBodyPainterFactory = ref.watch(cellBodyPainterFactoryProvider);
    final activityColorOverride = ref.watch(netActivityColorOverrideProvider);
    final crossingOverlay = ref.watch(schematicCrossingOverlayProvider);
    final annotationMarkers = ref.watch(schematicAnnotationMarkersProvider);
    final presenceOverlay = ref.watch(collabPresenceOverlayProvider);
    final filterViewMode = ref.watch(coiFilterViewModeProvider);

    final canvasKey = ref.watch(schematicCanvasKeyProvider);
    return laidOutAsync.when(
      // The scrollbars flank the gesture-handled canvas: dragging a thumb pans through the design's
      // laid-out bounds, and the thumbs track mouse/trackpad pan + zoom
      // because both surfaces share viewportTransformProvider.
      // The schematic is a DATA SURFACE, and the decision here is what a
      // screen reader should hear from it.
      //
      // Not every cell: a mid-size design is thousands of them, and reading
      // out a flat list of gate instances is not navigation, it is noise. Not
      // nothing either — an unlabelled canvas announces as a blank region and
      // gives a reader no way to tell a loaded design from an empty tab.
      //
      // So: a summary of what is on the surface, matching what WaveCrux does
      // for the waveform canvas. Per-element access is through the hierarchy
      // tree and the search dialog, which are real widgets with real
      // semantics; this label is what tells a reader the canvas has content
      // and roughly how much.
      data: (laidOut) => SchematicScrollbars(
        bounds: laidOut.layout.bounds,
        child: SchematicGestureHandler(
          child: Semantics(
            label: L10N
                .of(context)
                .accessibilitySchematicActive(
                  laidOut.graph.cells.length,
                  laidOut.graph.edges.length,
                ),
            child: RepaintBoundary(
              key: canvasKey,
              child: SchematicCanvas(
                laidOut: laidOut,
                transform: transform,
                selection: selection,
                overlay: overlay,
                cellBodyPainterFactory: cellBodyPainterFactory,
                netActivityColorOverride: activityColorOverride,
                crossingOverlay: crossingOverlay,
                annotationMarkers: annotationMarkers,
                presenceOverlay: presenceOverlay,
                filterViewMode: filterViewMode,
                statsSink: _NotifierStatsSink(statsNotifier),
              ),
            ),
          ),
        ),
      ),
      loading: () => const _SchematicLayoutLoading(),
      error: (error, stackTrace) => SchematicErrorView(error: error),
    );
  }
}

class _NotifierStatsSink implements RenderStatsSink {
  const _NotifierStatsSink(this._notifier);

  final PaneRenderStatsNotifier _notifier;

  @override
  void record(PaneRenderStats stats) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notifier.record(stats);
    });
  }
}

/// Progress state shown while the ELK layout for the selected scope runs.
///
/// The layout solve is offloaded to a background isolate (see
/// `ElkLayoutService`), so the UI isolate stays free to animate this
/// indicator — a large scope (e.g. a ~1 600-cell CPU core) takes a few
/// seconds. Shows the cell count so the user understands why a big scope
/// takes longer, an **indeterminate progress bar**, and an elapsed-seconds
/// readout. The bar is indeterminate because elkjs is an opaque solve — it
/// reports no incremental progress, so a true percentage isn't available;
/// the elapsed counter is the honest "it's working" signal.
class _SchematicLayoutLoading extends ConsumerStatefulWidget {
  const _SchematicLayoutLoading();

  @override
  ConsumerState<_SchematicLayoutLoading> createState() =>
      _SchematicLayoutLoadingState();
}

class _SchematicLayoutLoadingState
    extends ConsumerState<_SchematicLayoutLoading> {
  final Stopwatch _stopwatch = Stopwatch()..start();
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Repaint the elapsed readout a few times a second. The widget is
    // unmounted the instant the layout completes (the canvas swaps to the
    // data state), so the timer is naturally short-lived.
    _ticker = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) {
        if (mounted) setState(() {});
      },
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    final model = ref.watch(loadedNetlistProvider).value;
    final module = model == null
        ? null
        : ref.watch(hierarchyTreeProvider).selected?.resolve(model);
    final cellCount = module?.cells.length ?? 0;
    final seconds = (_stopwatch.elapsedMilliseconds / 1000).toStringAsFixed(1);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              l10n.schematicLayoutInProgress(cellCount),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Text(
              l10n.schematicLayoutElapsed(seconds),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
