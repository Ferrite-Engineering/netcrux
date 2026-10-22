// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:netcrux/domain/interfaces/cone_of_influence_service.dart';
import 'package:netcrux/domain/interfaces/transitive_cone_resolver.dart';
import 'package:netcrux/domain/models/schematic/laid_out_graph.dart';
import 'package:netcrux/domain/models/schematic/schematic_graph.dart';
import 'package:netcrux/domain/models/trace/cone_view.dart';
import 'package:netcrux/domain/models/trace/trace_overlay.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/project/providers/loaded_netlist_provider.dart';
import 'package:netcrux/features/statistics/providers/layout_timing_provider.dart';
import 'package:netcrux/features/viewer/providers/cone_view_notifier.dart';
import 'package:netcrux/features/viewer/services/schematic_scene_index.dart';
import 'package:netcrux/services/custom_cell_symbols/cell_symbol_geometry_provider.dart';
import 'package:netcrux/services/layout/elk_layout_service.dart';
import 'package:netcrux/services/layout/elk_layout_service_provider.dart';
import 'package:netcrux/services/schematic/cone_membership.dart';
import 'package:netcrux/services/schematic/declared_cell_ports.dart';
import 'package:netcrux/services/schematic/schematic_graph_builder.dart';
import 'package:netcrux/services/schematic/transitive_cone_resolver_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'current_laid_out_graph_provider.g.dart';

/// Streams the [LaidOutGraph] for the currently selected scope.
///
/// Composition:
///   1. `loadedNetlistProvider` → NetlistModel?
///   2. `hierarchyTreeProvider.selected` → HierarchyNode?
///   3. SchematicGraphBuilder → SchematicGraph
///   4. ElkLayoutService → NetlistLayout
///   5. Pair (3) + (4) → LaidOutGraph
///
/// Yields `LaidOutGraph.empty` until both a model and a selection
/// are available so the canvas has something to paint immediately
/// — no flicker between "still loading" and "first paint".
///
/// No automatic retry ([noElaborationRetry]): this provider fails only by
/// re-throwing a deterministic upstream elaboration error or a
/// deterministic layout failure, so Riverpod's backoff retry would just
/// re-run ELK against the same input while churning listeners.
@Riverpod(keepAlive: true, retry: noElaborationRetry)
Future<LaidOutGraph> currentLaidOutGraph(Ref ref) async {
  final modelAsync = ref.watch(loadedNetlistProvider);
  // Elaboration failed (e.g. yosys missing, source files absent, parse
  // error) — propagate so the schematic canvas surfaces the error via
  // its error view instead of silently painting an empty graph.
  if (modelAsync.hasError) {
    Error.throwWithStackTrace(
      modelAsync.error!,
      modelAsync.stackTrace ?? StackTrace.current,
    );
  }
  final tree = ref.watch(hierarchyTreeProvider);
  final node = tree.selected;
  // No model loaded yet, or no scope selected — nothing to lay out.
  if (modelAsync.value == null || node == null) {
    return LaidOutGraph.empty;
  }
  final model = modelAsync.value!;
  final module = node.resolve(model);
  if (module == null) return LaidOutGraph.empty;

  final graph = const SchematicGraphBuilder().build(model, node);
  if (graph.isEmpty) return LaidOutGraph.empty;

  // Custom cell symbols shape the cells they draw, so a symbol added,
  // removed or re-anchored lays the scope out again. Open core always has
  // none, and the provider is value-equal, so this never re-solves there.
  final symbols = ref.watch(cellSymbolGeometriesProvider);

  // A cone view of this scope lays out the cone instead of the scope. The
  // cone is resolved on the graph above, before any layout, so a scope too
  // large to lay out quickly never has to be laid out to show one. Entering
  // or leaving a cone view rebuilds this provider, which abandons a solve
  // still running for the other one (below).
  final cone = ref.watch(coneViewProvider);
  final coneHere = cone != null && cone.scope == node ? cone : null;
  final coneDepth = coneHere?.depth;
  // The cone with no depth limit is the Pro form: walked by the resolver
  // the Pro overlay binds for a licence that admits it. With none bound the
  // scope is shown whole.
  final transitive = coneHere != null && coneDepth == null
      ? ref.watch(transitiveConeResolverProvider)
      : null;

  final service = ref.read(elkLayoutServiceProvider);
  // Leaving this scope (a new selection rebuilds the provider), entering or
  // leaving a cone view, or closing the tab abandons a solve still running
  // for it. The native engine stops at its next check and its worker stays
  // warm; elkjs cannot be interrupted, so its worker is killed. Without this
  // a slow scope kept a core busy after the user had moved on, and the next
  // layout queued behind it. The progress view's Cancel takes the same path.
  ref.onDispose(service.cancelInFlightLayout);

  TraceOverlay? members;
  if (coneHere != null && coneDepth != null) {
    members = coneViewMembership(
      graph,
      coneHere.root,
      direction: coneHere.direction,
      depth: coneDepth,
    );
  } else if (coneHere != null && transitive != null) {
    members = await _transitiveMembers(transitive, graph, coneHere);
  }
  // Time the pass for the statistics strip. Layout is the
  // slowest non-elaboration step in the pipeline, and on a large scope
  // "is it hung or is it working?" is a real question.
  //
  // Only the *completed* duration is published, and only after the await:
  // Riverpod forbids a provider mutating another during its build, and
  // "a pass is in flight" is already exactly this provider's own
  // `AsyncValue.isLoading` — a second flag could only ever disagree.
  final stopwatch = Stopwatch()..start();
  try {
    // The same patched module the graph builder draws from, so every pin
    // it adds for a declared-but-unconnected port has a place.
    final patched = withDeclaredCellPorts(model, module);
    final shown = members == null ? graph : coneSubgraph(graph, members);
    final layout = await service.layout(
      patched,
      symbols: symbols,
      only: members == null
          ? null
          : ElkSubgraph(
              cellIds: <String>{for (final c in shown.cells) c.id},
              boundaryPortIds: <String>{
                for (final b in shown.boundaryPorts) b.id,
              },
              edgeIds: <String>{for (final e in shown.edges) e.id},
            ),
    );
    ref.read(layoutTimingProvider.notifier).completed(stopwatch.elapsed);
    final symbolCells = symbolCellAnchoredPorts(patched, symbols);
    final laidOut = LaidOutGraph(
      graph: shown,
      layout: layout,
      symbolCells: members == null
          ? symbolCells
          : <String, Set<String>>{
              for (final entry in symbolCells.entries)
                if (members.highlightedCellIds.contains(entry.key))
                  entry.key: entry.value,
            },
      cone: coneHere == null || members == null
          ? null
          : ConeViewExtent(
              request: coneHere,
              scopeCellCount: graph.cells.length,
            ),
    );
    // The scene index the painter, the hit-tester and the keyboard
    // navigator read is built here, before the graph reaches the canvas, and
    // on another isolate for a large scope. Built on first use instead, a
    // 100,000-cell scope spent its first frame and its first click building
    // grids on the UI thread.
    await SchematicSceneIndex.warm(laidOut);
    return laidOut;
  } on LayoutException {
    // Deliberately not recorded: a failed layout measures how long the
    // failure took to detect, not what laying this scope out costs, and
    // it would spike the sparkline with a meaningless number.
    //
    // Layout failures are surfaced as an empty canvas with the
    // exception bubbling through `AsyncValue.error`. The Diagnostics
    // panel shows the underlying cause.
    rethrow;
  }
}

/// The whole cone of [request] in [graph], walked by [resolver] fan-in, or
/// fan-in and fan-out together, with the root's own anchor added so a root
/// with no connectivity is drawn alone rather than not at all.
Future<TraceOverlay> _transitiveMembers(
  TransitiveConeResolver resolver,
  SchematicGraph graph,
  ConeViewRequest request,
) async {
  var members = await resolver.resolve(
    graph,
    request.root,
    ConeOfInfluenceMode.fanin,
  );
  if (request.direction == ConeViewDirection.fanInAndFanOut) {
    members = unionConeMembership(
      members,
      await resolver.resolve(graph, request.root, ConeOfInfluenceMode.fanout),
    );
  }
  final cells = <String>{...members.highlightedCellIds};
  final boundaries = <String>{...members.highlightedBoundaryPortIds};
  final edges = <String>{...members.highlightedEdgeIds};
  addConeAnchors(graph, request.root, cells, boundaries, edges);
  return TraceOverlay(
    mode: members.mode ?? TraceOverlayMode.fanin,
    highlightedCellIds: cells,
    highlightedEdgeIds: edges,
    highlightedBoundaryPortIds: boundaries,
  );
}
