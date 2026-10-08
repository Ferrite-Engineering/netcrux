// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:netcrux/features/bookmarks/providers/annotation_reveal_request.dart';
import 'package:netcrux/features/bookmarks/providers/bookmark_schematic_annotation_markers.dart';
import 'package:netcrux/features/cdc/providers/cdc_analysis_state_provider.dart';
import 'package:netcrux/features/collaboration/collab_presence_overlay_provider.dart';
import 'package:netcrux/features/diagnostics/providers/netlist_footprint_provider.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/hierarchy/providers/scope_flash_notifier.dart';
import 'package:netcrux/features/project/providers/current_laid_out_graph_provider.dart';
import 'package:netcrux/features/project/providers/current_project_provider.dart';
import 'package:netcrux/features/project/providers/elaboration_diagnostics_provider.dart';
import 'package:netcrux/features/project/providers/loaded_netlist_provider.dart';
import 'package:netcrux/features/source_pane/providers/source_pane_state_provider.dart';
import 'package:netcrux/features/statistics/providers/layout_timing_provider.dart';
import 'package:netcrux/features/viewer/providers/reveal_request_notifier.dart';
import 'package:netcrux/features/viewer/providers/schematic_canvas_key_provider.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/features/viewer/providers/trace_overlay_notifier.dart';
import 'package:netcrux/features/viewer/providers/viewport_transform_notifier.dart';
import 'package:netcrux/services/reload/source_file_watcher_provider.dart';
import 'package:netcrux/services/schematic/schematic_annotation_markers_provider.dart';
import 'package:netcrux/services/session/bookmark_annotation_state.dart';
import 'package:netcrux/services/session/bookmark_annotation_store_provider.dart';
import 'package:netcrux/services/session/in_session_bookmark_annotation_store.dart';

/// Per-tab override list applied on top of [`tabIdProvider`] when
/// [`TabContainerManager`] creates a fresh `ProviderContainer` for a new
/// tab.
///
/// Every override here re-binds a previously-root-scoped notifier so that
/// each tab has its own independent instance. App-wide providers (settings,
/// theme, license tier, shortcut bindings, Yosys-engine resolution) are
/// **not** listed — they stay at root and resolve via the parent-container
/// chain so each tab still sees the same global state.
///
/// Per-pane providers ([`paneRenderStatsProvider`]) are handled by the
/// parallel [`netcruxPaneOverridesFactory`].
///
/// Most overrides here ignore [tabId] — a fresh notifier instance per
/// container is all the isolation they need. Providers whose *value*
/// must be derived from the tab identity read it: [`schematicCanvasKeyProvider`]
/// builds a `GlobalKey` labelled with the tab id below.
List<Override> netcruxTabOverridesFactory(TabId tabId) {
  return <Override>[
    // Project + elaboration pipeline.
    currentProjectProvider.overrideWith(CurrentProject.new),
    loadedNetlistProvider.overrideWith(LoadedNetlist.new),
    // The schematic canvas pipeline must be per-tab too — otherwise
    // its build hoists to the root container and reads root-scoped
    // (empty) instances of loadedNetlist + hierarchyTree, which is
    // why the canvas painted blank even after a successful yosys
    // elaboration in a tab. The provider is implemented as a
    // FunctionalProvider (top-level `@Riverpod`), so the override
    // form is `.overrideWith((ref) => currentLaidOutGraph(ref))`.
    currentLaidOutGraphProvider.overrideWith(currentLaidOutGraph),
    // Written by the layout pass above, so it follows the same scope.
    layoutTimingProvider.overrideWith(LayoutTimingNotifier.new),
    elaborationStderrProvider.overrideWith(ElaborationStderr.new),
    elaborationDiagnosticFilterProvider.overrideWith(
      ElaborationDiagnosticFilter.new,
    ),
    // The two derived diagnostics views must re-bind alongside their
    // per-tab sources. Without them a tab-scoped read hoists them to the
    // ROOT container, where their `watch` resolves ROOT's (always-empty)
    // stderr and ROOT's filter set — so the tab diagnostics drawer showed
    // no Yosys warnings after a successful elaboration and the severity
    // chips filtered a different instance than the one they rendered
    // from. Derived providers follow their source's scope.
    elaborationDiagnosticsProvider.overrideWith(elaborationDiagnostics),
    filteredElaborationDiagnosticsProvider.overrideWith(
      filteredElaborationDiagnostics,
    ),
    // The App Diagnostics memory breakdown reads one row per tab, so this
    // derived view follows its source per the same rule — left at root it
    // would report the empty root netlist for every tab and the table
    // would be a column of zeros.
    netlistFootprintProvider.overrideWith(netlistFootprint),
    // Hierarchy + viewer state.
    hierarchyTreeProvider.overrideWith(HierarchyTreeNotifier.new),
    selectedElementProvider.overrideWith(SelectedElementNotifier.new),
    traceOverlayProvider.overrideWith(TraceOverlayNotifier.new),
    viewportTransformProvider.overrideWith(ViewportTransformNotifier.new),
    // Per-tab pending "reveal this cell" request (search jump-to-element).
    // Scoped alongside the viewport + selection it drives so a reveal acts
    // on the focused tab's canvas.
    revealRequestProvider.overrideWith(RevealRequestNotifier.new),
    // Collaboration presence, derived from the session roster and the tab's
    // own hierarchy selection. Per-tab because the scope filter is: left at
    // root it would read ROOT's (always-empty) hierarchy, every remote
    // participant's scope would compare unequal, and NO colleague's cursor or
    // selection would ever paint — silently, in a feature whose whole job is
    // to paint them. The session itself is a singleton at root; only this
    // projection of it is per-tab.
    collabPresenceOverlayProvider.overrideWith(collabPresenceOverlay),
    // Per-tab pending "flash this scope" request — the hierarchy-tree pulse an
    // inbound scope cross-probe fires so it produces a visible cue even when
    // it resolves to the scope already selected. Scoped alongside the
    // hierarchy state it pulses.
    scopeFlashProvider.overrideWith(ScopeFlashNotifier.new),
    // Per-tab RTL source-pane state. Documented per-tab since the pane
    // landed (mirrors bookmarks / X-trace scoping — see
    // source_pane_state_provider.dart's doc comment)
    // but, like the CDC state notifier before it, was only *documented*
    // per-tab, never actually re-bound here — so it hoisted to the ROOT
    // container. Its internal `ref.read(sourcePaneServiceProvider)` then
    // resolved ROOT's (empty) service instead of the active tab's, so
    // "Show Source for this Element" always fell through to the "no source
    // attribution" path for a design loaded in a tab (the recurring
    // per-tab scope-leak class; the Pro `sourcePaneServiceProvider`
    // per-tab override cannot reach a root-instantiated state notifier).
    sourcePaneStateProvider.overrideWith(SourcePaneStateNotifier.new),
    // Per-tab file watcher — each tab watches its own source list and
    // re-elaborates independently when files change.
    sourceFileWatcherProvider.overrideWith(SourceFileWatcher.new),
    sourceReloadEventsProvider.overrideWith(SourceReloadEvents.new),
    // Per-tab GlobalKey on the schematic's RepaintBoundary. The PNG
    // export controller reads the active tab's key off its container
    // and grabs the boundary's render object via `findRenderObject()`.
    schematicCanvasKeyProvider.overrideWith(
      (_) => GlobalKey(debugLabel: 'schematicCanvasKey-${tabId.value}'),
    ),
    // CDC analysis result + selection. Documented per-tab since the CDC
    // pane landed but only actually scoped per-tab here — without this
    // override the notifier hoists to root and every tab shares one
    // result set. Writers (the Pro openers) and readers (the analysis
    // pane, the schematic crossing overlay) must resolve it through the
    // active tab's container. The four derived views re-scope alongside
    // it, or a tab-scoped consumer's read would hoist them to root where
    // their `watch` resolves the ROOT state — a derived provider always
    // follows the scope of the provider it watches.
    cdcAnalysisStateProvider.overrideWith(CdcAnalysisNotifier.new),
    perTabCdcAnalysisResultProvider.overrideWith(perTabCdcAnalysisResult),
    selectedCdcCrossingProvider.overrideWith(selectedCdcCrossing),
    selectedClockDomainProvider.overrideWith(selectedClockDomain),
    cdcSeverityFilterProvider.overrideWith(cdcSeverityFilter),
    // Bookmarks and annotations belong to the design in the tab they were
    // made in. As root-only registrations, the keepAlive state notifier
    // would be one app-wide list: a bookmark on one design's cell would
    // show in every tab's panel and be saved into every tab's session. The
    // store and the snapshot the panels watch read the state notifier
    // through their own `ref`, so they re-bind with it; the annotation
    // reveal request names an annotation of this tab, and the canvas markers
    // read the tab's annotations and its hierarchy.
    bookmarkAnnotationStateProvider.overrideWith(BookmarkAnnotationState.new),
    bookmarkAnnotationStoreProvider.overrideWith(
      InSessionBookmarkAnnotationStore.new,
    ),
    bookmarkAnnotationSnapshotProvider.overrideWith(
      (ref) => ref.watch(bookmarkAnnotationStateProvider),
    ),
    annotationRevealRequestProvider.overrideWith(AnnotationRevealRequest.new),
    schematicAnnotationMarkersProvider.overrideWith(
      bookmarkSchematicAnnotationMarkers,
    ),
  ];
}
