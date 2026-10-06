// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:netcrux/domain/models/schematic/laid_out_graph.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/project/providers/loaded_netlist_provider.dart';
import 'package:netcrux/features/statistics/providers/layout_timing_provider.dart';
import 'package:netcrux/services/custom_cell_symbols/cell_symbol_geometry_provider.dart';
import 'package:netcrux/services/layout/elk_layout_service.dart';
import 'package:netcrux/services/layout/elk_layout_service_provider.dart';
import 'package:netcrux/services/schematic/declared_cell_ports.dart';
import 'package:netcrux/services/schematic/schematic_graph_builder.dart';
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

  final service = ref.read(elkLayoutServiceProvider);
  // Leaving this scope (a new selection rebuilds the provider) or closing
  // the tab abandons a solve still running for it: the engine cannot be
  // interrupted, so the worker is killed and the next scope starts a fresh
  // one. Without this a slow scope kept a core busy for the whole timeout
  // after the user had moved on, and the next layout queued behind it.
  ref.onDispose(service.cancelInFlightLayout);
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
    final layout = await service.layout(patched, symbols: symbols);
    ref.read(layoutTimingProvider.notifier).completed(stopwatch.elapsed);
    return LaidOutGraph(
      graph: graph,
      layout: layout,
      symbolCells: symbolCellAnchoredPorts(patched, symbols),
    );
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
