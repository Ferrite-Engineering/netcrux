// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// prefer_initializing_formals: the SchematicCanvasRenderObject
// constructor takes public named params (`laidOut`, `transform`, …) but
// stores them into private fields (`_laidOut`, `_transform`, …) so the
// markNeedsPaint setters work. Dart does not allow `this._foo` from a
// non-private named parameter, so the explicit assignment is the only
// way to bridge the public/private boundary.
// ignore_for_file: prefer_initializing_formals

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:netcrux/core/theme/netcrux_colors.dart';
import 'package:netcrux/domain/models/layout/bounding_box.dart';
import 'package:netcrux/domain/models/layout/edge_route.dart';
import 'package:netcrux/domain/models/layout/node_position.dart';
import 'package:netcrux/domain/models/schematic/cell_kind.dart';
import 'package:netcrux/domain/models/schematic/laid_out_graph.dart';
import 'package:netcrux/domain/models/schematic/pin_tie.dart';
import 'package:netcrux/domain/models/schematic/schematic_graph.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/domain/models/selection/selection.dart';
import 'package:netcrux/domain/models/trace/trace_overlay.dart';
import 'package:netcrux/features/collaboration/collab_presence_overlay_provider.dart';
import 'package:netcrux/features/viewer/providers/pane_render_stats.dart';
import 'package:netcrux/features/viewer/rendering/lod_band.dart';
import 'package:netcrux/features/viewer/rendering/schematic_scene_index.dart';
import 'package:netcrux/features/viewer/symbols/cell_body_painter_factory.dart';
import 'package:netcrux/features/viewer/symbols/symbol_painters.dart';
import 'package:netcrux/services/schematic/schematic_crossing_overlay_provider.dart';
import 'package:netcrux/shared/widgets/start_ellipsis_text.dart';

/// Sink the [SchematicCanvasRenderObject] writes its paint-time
/// metrics into. The viewer wires this to [PaneRenderStatsNotifier];
/// tests can supply a recording stub.
abstract interface class RenderStatsSink {
  /// Records [stats] for the most-recently-completed paint.
  void record(PaneRenderStats stats);
}

/// Viewport transform applied to the schematic before painting:
/// uniform scale (`zoom`) then translate (`offset`). Mirrors the
/// mental model the gesture handler maintains.
@immutable
class ViewportTransform {
  /// Creates a viewport transform.
  const ViewportTransform({
    required this.zoom,
    required this.offset,
  });

  /// Identity transform — 1.0 zoom, zero offset.
  static const ViewportTransform identity = ViewportTransform(
    zoom: 1,
    offset: Offset.zero,
  );

  /// Uniform scale factor.
  final double zoom;

  /// Translation in canvas pixels applied after scaling.
  final Offset offset;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ViewportTransform &&
          other.zoom == zoom &&
          other.offset == offset);

  @override
  int get hashCode => Object.hash(zoom, offset);

  @override
  String toString() => 'ViewportTransform(zoom=$zoom, offset=$offset)';
}

/// Widget host for [SchematicCanvasRenderObject].
class SchematicCanvas extends LeafRenderObjectWidget {
  /// Creates the canvas widget.
  const SchematicCanvas({
    required this.laidOut,
    required this.transform,
    required this.statsSink,
    this.selection = Selection.empty,
    this.overlay = TraceOverlay.empty,
    this.cellBodyPainterFactory = defaultCellBodyPainterFactory,
    this.netActivityColorOverride,
    this.crossingOverlay,
    this.presenceOverlay,
    this.filterViewMode = false,
    this.theme,
    this.cullingEnabled = true,
    super.key,
  });

  /// The graph to paint.
  final LaidOutGraph laidOut;

  /// Current viewport transform.
  final ViewportTransform transform;

  /// Sink for per-frame metrics.
  final RenderStatsSink statsSink;

  /// Current multi-selection (every element gets the selection accent; the
  /// primary element is rendered with the brighter primary accent).
  final Selection selection;

  /// Currently active trace overlay (dims non-highlighted elements).
  final TraceOverlay overlay;

  /// Factory consulted to pick the body painter for each cell.
  /// Defaults to [defaultCellBodyPainterFactory] so open-core
  /// rendering is unchanged. The Pro overlay threads through a
  /// factory that consults the [CustomCellSymbolRegistry] snapshot.
  final CellBodyPainterFactory cellBodyPainterFactory;

  /// Optional per-edge color override map keyed by [SchematicEdge.id]
  /// — when an edge id is present the painter renders the wire at
  /// the supplied color in place of the default base paint
  /// (selection + dim overlays still win). The Pro overlay's
  /// Switching Activity Heatmap publishes this map; open-core
  /// passes `null` so wires render at the theme's default
  /// `onSurfaceVariant`. See the `netActivityColorOverrideProvider` entry in
  /// `docs/ARCHITECTURE.md` §10.
  final Map<String, Color>? netActivityColorOverride;

  /// Optional severity-coded crossing overlay published by the Pro
  /// overlay's CDC + Reset-domain features. When non-null, the
  /// painter draws a severity-colored outline around every cell
  /// named in the overlay's source / destination / intermediate
  /// sets. Open-core passes `null` so the painter skips this pass.
  /// See `schematicCrossingOverlayProvider`.
  final SchematicCrossingOverlay? crossingOverlay;

  /// Remote participants' cursors and selections in a collaborative
  /// session, already filtered to the scope on screen. `null` outside a
  /// session — including for the whole life of an open-core build, whose
  /// no-op collaboration service never opens one. See
  /// `collabPresenceOverlayProvider`.
  final CollabPresenceOverlay? presenceOverlay;

  /// When `true` *and* a [overlay] is active, the painter skips
  /// non-highlighted cells / edges / boundary ports entirely rather
  /// than dimming them. Lets the Cone-of-Influence UI surface a
  /// "show only the COI sub-graph" toggle without redesigning the
  /// dispatch path. Open-core resolves the
  /// [coiFilterViewModeProvider] to `false` so the canvas paints
  /// normally without the Pro overlay present.
  final bool filterViewMode;

  /// Optional theme override — defaults to `Theme.of(context)` when
  /// `null`. Exposed so tests can pump a fixed theme without
  /// constructing a full MaterialApp.
  final ThemeData? theme;

  /// Whether the painter culls off-screen elements. Always `true` in
  /// production; the paint benchmark sets it `false` to measure the
  /// no-cull baseline.
  final bool cullingEnabled;

  @override
  SchematicCanvasRenderObject createRenderObject(BuildContext context) {
    return SchematicCanvasRenderObject(
      laidOut: laidOut,
      transform: transform,
      statsSink: statsSink,
      selection: selection,
      overlay: overlay,
      cellBodyPainterFactory: cellBodyPainterFactory,
      netActivityColorOverride: netActivityColorOverride,
      crossingOverlay: crossingOverlay,
      presenceOverlay: presenceOverlay,
      filterViewMode: filterViewMode,
      theme: theme ?? Theme.of(context),
      cullingEnabled: cullingEnabled,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    SchematicCanvasRenderObject renderObject,
  ) {
    renderObject
      ..laidOut = laidOut
      ..transform = transform
      ..statsSink = statsSink
      ..selection = selection
      ..overlay = overlay
      ..cellBodyPainterFactory = cellBodyPainterFactory
      ..netActivityColorOverride = netActivityColorOverride
      ..crossingOverlay = crossingOverlay
      ..presenceOverlay = presenceOverlay
      ..filterViewMode = filterViewMode
      ..theme = theme ?? Theme.of(context)
      ..cullingEnabled = cullingEnabled;
  }
}

/// Direct-paint render object for the schematic canvas.
class SchematicCanvasRenderObject extends RenderBox {
  /// Creates a schematic canvas render object.
  SchematicCanvasRenderObject({
    required LaidOutGraph laidOut,
    required ViewportTransform transform,
    required RenderStatsSink statsSink,
    required ThemeData theme,
    Selection selection = Selection.empty,
    TraceOverlay overlay = TraceOverlay.empty,
    CellBodyPainterFactory cellBodyPainterFactory =
        defaultCellBodyPainterFactory,
    Map<String, Color>? netActivityColorOverride,
    SchematicCrossingOverlay? crossingOverlay,
    CollabPresenceOverlay? presenceOverlay,
    bool filterViewMode = false,
    bool cullingEnabled = true,
  }) : _laidOut = laidOut,
       _transform = transform,
       _statsSink = statsSink,
       _theme = theme,
       _selection = selection,
       _overlay = overlay,
       _cellBodyPainterFactory = cellBodyPainterFactory,
       _netActivityColorOverride = netActivityColorOverride,
       _crossingOverlay = crossingOverlay,
       _presenceOverlay = presenceOverlay,
       _filterViewMode = filterViewMode,
       _cullingEnabled = cullingEnabled;

  LaidOutGraph _laidOut;

  /// Currently displayed graph.
  LaidOutGraph get laidOut => _laidOut;
  set laidOut(LaidOutGraph value) {
    if (value == _laidOut) return;
    _laidOut = value;
    // Cell geometry (label max-width) and displayLabels are tied to the
    // layout, so the memoized text layouts are stale once it changes.
    _clearTextLayoutCache();
    markNeedsPaint();
  }

  ViewportTransform _transform;

  /// Current viewport transform.
  ViewportTransform get transform => _transform;
  set transform(ViewportTransform value) {
    if (value == _transform) return;
    _transform = value;
    markNeedsPaint();
  }

  RenderStatsSink _statsSink;

  /// Sink that receives per-frame metrics.
  RenderStatsSink get statsSink => _statsSink;
  set statsSink(RenderStatsSink value) {
    if (identical(value, _statsSink)) return;
    _statsSink = value;
  }

  ThemeData _theme;

  /// Active theme — controls symbol fill / stroke / accent.
  ThemeData get theme => _theme;
  set theme(ThemeData value) {
    if (value == _theme) return;
    _theme = value;
    // Label styles are derived from the theme, so cached layouts (which
    // bake in colour + font metrics) must be rebuilt.
    _clearTextLayoutCache();
    markNeedsPaint();
  }

  bool _cullingEnabled;

  /// Whether the painter culls cells / edges / boundary ports that fall
  /// entirely outside the visible design-space rect. Always `true` in
  /// production; the paint benchmark flips it to `false` to measure
  /// the no-cull baseline against the culled path.
  bool get cullingEnabled => _cullingEnabled;
  set cullingEnabled(bool value) {
    if (value == _cullingEnabled) return;
    _cullingEnabled = value;
    markNeedsPaint();
  }

  /// Per-layout-instance cache of laid-out label [TextPainter]s, keyed by
  /// `<kind>:<id>:<band>`. At the detail LOD band the painter drew and
  /// laid out a fresh `TextPainter` per cell (and per boundary port)
  /// *every frame*, including for off-screen cells; memoizing the layout
  /// turns that into a one-time cost per label. Invalidated whenever the
  /// [laidOut] graph or [theme] changes (see the respective setters) and
  /// disposed in [dispose].
  ///
  /// Bounded by [_maxTextLayoutCacheEntries] and evicted least-recently-used.
  /// Without a cap a single large scope caches one laid-out `TextPainter`
  /// per label for the whole layout — every cell and boundary port,
  /// on-screen or not — and each painter retains a laid-out paragraph.
  /// Viewport culling means only a window of those labels is ever drawn
  /// again, so the cap keeps the retained set proportional to what the
  /// user can actually see rather than to design size.
  ///
  /// `Map` preserves insertion order; the LRU ordering is maintained by
  /// removing and re-inserting an entry on read.
  final Map<String, TextPainter> _textLayoutCache = <String, TextPainter>{};

  /// Maximum laid-out label painters retained at once. Comfortably above
  /// the number of labels a detail-band viewport can show, so a normal
  /// pan/zoom session never evicts a label it is about to redraw.
  static const int _maxTextLayoutCacheEntries = 2048;

  /// Returns the cached laid-out painter for [key], building and caching
  /// it on first use and promoting it to the LRU tail. The caller owns
  /// nothing — the cache disposes the painter on eviction or invalidation.
  ///
  /// A label too wide for [maxWidth] loses its end behind an ellipsis, or
  /// its start when [elideStart] is set ([startElidedText]).
  TextPainter _labelLayout(
    String key,
    String text,
    TextStyle style,
    double maxWidth, {
    bool elideStart = false,
  }) {
    final cached = _textLayoutCache.remove(key);
    if (cached != null) {
      _textLayoutCache[key] = cached;
      return cached;
    }
    final shown = elideStart
        ? startElidedText(text, style: style, maxWidth: maxWidth)
        : text;
    final painter = TextPainter(
      text: TextSpan(text: shown, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    _textLayoutCache[key] = painter;
    while (_textLayoutCache.length > _maxTextLayoutCacheEntries) {
      final oldest = _textLayoutCache.keys.first;
      _textLayoutCache.remove(oldest)?.dispose();
    }
    return painter;
  }

  void _clearTextLayoutCache() {
    for (final painter in _textLayoutCache.values) {
      painter.dispose();
    }
    _textLayoutCache.clear();
  }

  @override
  void dispose() {
    _clearTextLayoutCache();
    super.dispose();
  }

  Selection _selection;

  /// Current selection (drives accent overlays).
  Selection get selection => _selection;
  set selection(Selection value) {
    if (value == _selection) return;
    _selection = value;
    markNeedsPaint();
  }

  /// Cell ids in the current selection. Computed on demand from
  /// [_selection.elements] — avoids materializing a per-paint set
  /// when no cells are selected.
  Set<String> _selectedCellIds() {
    if (_selection.isEmpty) return const <String>{};
    final ids = <String>{};
    for (final element in _selection.elements) {
      switch (element) {
        case SelectedElementCell(:final cellId):
          ids.add(cellId);
        case SelectedElementPort(:final cellId):
          // Selecting a port should also highlight its cell so the
          // user sees what they clicked into. Cheap and matches
          // WaveCrux's "signal owns the lane" idiom.
          ids.add(cellId);
        case SelectedElementNone():
        case SelectedElementBoundaryPort():
        case SelectedElementWire():
          break;
      }
    }
    return ids;
  }

  /// Port ids (`cellName:portName`) in the current selection.
  Set<String> _selectedPortIds() {
    if (_selection.isEmpty) return const <String>{};
    final ids = <String>{};
    for (final element in _selection.elements) {
      if (element is SelectedElementPort) ids.add(element.portId);
    }
    return ids;
  }

  /// Edge ids in the current selection (wire selections).
  Set<String> _selectedEdgeIds() {
    if (_selection.isEmpty) return const <String>{};
    final ids = <String>{};
    for (final element in _selection.elements) {
      if (element is SelectedElementWire) ids.add(element.edgeId);
    }
    return ids;
  }

  /// Net ids in the current selection (wire selections).
  ///
  /// Wire selections are keyed by net, not by a single laid-out edge: a
  /// selected wire lights every routed segment of its net, matched on
  /// [EdgeRoute.netId]. The laid-out and schematic-graph edge ids are the
  /// same (both come from `enumerateNetEdges`), so the edge id also
  /// matches; the net match is what lights the rest of the net, and what
  /// keeps a wire restored from a saved session, whose edge id may no
  /// longer exist, lit. Negative sentinel net ids (an unresolved hit) are
  /// dropped so they can never match a real edge.
  Set<int> _selectedWireNetIds() {
    if (_selection.isEmpty) return const <int>{};
    final ids = <int>{};
    for (final element in _selection.elements) {
      if (element is SelectedElementWire && element.netId >= 0) {
        ids.add(element.netId);
      }
    }
    return ids;
  }

  /// Boundary-port ids in the current selection.
  Set<String> _selectedBoundaryPortIds() {
    if (_selection.isEmpty) return const <String>{};
    final ids = <String>{};
    for (final element in _selection.elements) {
      if (element is SelectedElementBoundaryPort) ids.add(element.portId);
    }
    return ids;
  }

  TraceOverlay _overlay;

  /// Current trace overlay (drives the dim/highlight split).
  TraceOverlay get overlay => _overlay;
  set overlay(TraceOverlay value) {
    if (value == _overlay) return;
    _overlay = value;
    markNeedsPaint();
  }

  CellBodyPainterFactory _cellBodyPainterFactory;

  /// Factory consulted to pick the body painter for each cell. The
  /// Pro overlay registers a factory backed by the
  /// [CustomCellSymbolRegistry] snapshot; open-core uses
  /// [defaultCellBodyPainterFactory].
  CellBodyPainterFactory get cellBodyPainterFactory => _cellBodyPainterFactory;
  set cellBodyPainterFactory(CellBodyPainterFactory value) {
    if (identical(value, _cellBodyPainterFactory)) return;
    _cellBodyPainterFactory = value;
    markNeedsPaint();
  }

  Map<String, Color>? _netActivityColorOverride;

  /// Per-edge color override map (keyed by [SchematicEdge.id])
  /// published by the Pro overlay's Switching Activity Heatmap. The
  /// painter applies these colors to edges in [_paintEdges] *after*
  /// the dim-overlay branch but *before* the selection branch, so
  /// activity colors are visible on highlighted edges while
  /// selection accent still wins. `null` (open-core default) skips
  /// the per-edge color lookup entirely.
  Map<String, Color>? get netActivityColorOverride => _netActivityColorOverride;
  set netActivityColorOverride(Map<String, Color>? value) {
    if (identical(value, _netActivityColorOverride)) return;
    _netActivityColorOverride = value;
    markNeedsPaint();
  }

  SchematicCrossingOverlay? _crossingOverlay;

  /// Severity-coded crossing overlay published by the Pro overlay's
  /// CDC + Reset-domain analysis features. Drawn as an extra pass
  /// after cells / edges / boundary ports — outlines every cell
  /// named in the overlay's source / destination / intermediate
  /// sets with the overlay's [SchematicCrossingOverlay.severityColor].
  /// `null` (open-core default) skips the extra pass entirely. See
  /// `schematicCrossingOverlayProvider`.
  SchematicCrossingOverlay? get crossingOverlay => _crossingOverlay;
  set crossingOverlay(SchematicCrossingOverlay? value) {
    if (value == _crossingOverlay) return;
    _crossingOverlay = value;
    markNeedsPaint();
  }

  CollabPresenceOverlay? _presenceOverlay;

  /// Remote participants' cursors and selections, drawn as the last pass
  /// so a colleague's marker is never hidden under the design. `null`
  /// (the open-core default, and the state whenever no session is
  /// running) skips the pass entirely. See
  /// `collabPresenceOverlayProvider`.
  CollabPresenceOverlay? get presenceOverlay => _presenceOverlay;
  set presenceOverlay(CollabPresenceOverlay? value) {
    if (value == _presenceOverlay) return;
    _presenceOverlay = value;
    markNeedsPaint();
  }

  bool _filterViewMode;

  /// When `true` *and* an [_overlay] is active, the painter skips
  /// non-highlighted cells / edges / boundary ports entirely (rather
  /// than dimming them). Default `false` preserves the dim-only
  /// behavior open-core ships by default.
  bool get filterViewMode => _filterViewMode;
  set filterViewMode(bool value) {
    if (value == _filterViewMode) return;
    _filterViewMode = value;
    markNeedsPaint();
  }

  int _frameNumber = 0;

  /// Frame counter — increments on every paint. Exposed so widget /
  /// integration tests can assert "the canvas painted".
  int get framesPainted => _frameNumber;

  /// Active LOD band for the most recently completed paint. Exposed so
  /// LOD-band golden tests can confirm the painter took the band they
  /// expected without poking the canvas output.
  LodBand get lastLodBand => _lastLodBand;
  LodBand _lastLodBand = LodBand.detail;

  @override
  bool get sizedByParent => true;

  @override
  void performResize() {
    size = constraints.biggest;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final stopwatch = Stopwatch()..start();
    final canvas = context.canvas
      ..save()
      ..clipRect(offset & size)
      ..translate(offset.dx, offset.dy);
    // Background — explicit fill so the canvas is solid even when
    // there's no design loaded yet.
    final background = Paint()..color = _theme.colorScheme.surface;
    canvas
      ..drawRect(Offset.zero & size, background)
      ..translate(_transform.offset.dx, _transform.offset.dy)
      ..scale(_transform.zoom, _transform.zoom);

    _lastLodBand = LodBandRouter.bandFor(_transform.zoom);

    final visibleRect = _visibleDesignRect();

    var paintedCells = 0;
    var paintedEdges = 0;
    if (!_laidOut.isEmpty) {
      paintedCells = _paintCells(canvas, _lastLodBand, visibleRect);
      paintedEdges = _paintEdges(canvas, _lastLodBand, visibleRect);
      _paintBoundaryPorts(canvas, _lastLodBand, visibleRect);
      // Labels of cells drawn with a custom symbol sit outside the drawing,
      // where wires may pass, so they paint over the wires on a backing.
      _paintOutsideCellLabels(canvas);
      // Crossing overlay paints last, on top of everything the passes
      // above drew — including the per-cell selection accent, which
      // _paintCells strokes inline. Drawn as the crossing net's wires
      // plus a per-cell stroked outline, all in the overlay's severity
      // colour. Skipped entirely when no Pro overlay is publishing
      // through schematicCrossingOverlayProvider.
      final crossing = _crossingOverlay;
      if (crossing != null && !crossing.isEmpty) {
        _paintCrossingOverlay(canvas, crossing, _lastLodBand, visibleRect);
      }
    }

    // Presence paints after everything, including the crossing overlay: a
    // colleague's pointer that can be hidden under the design is a pointer
    // that stops answering "where are they looking" exactly when the answer
    // matters. Unlike the passes above it also runs on an empty graph, so a
    // participant who has a design open still sees where the rest of the
    // room is while their own layout is still solving.
    final presence = _presenceOverlay;
    if (presence != null && !presence.isEmpty) {
      _paintPresenceOverlay(canvas, presence);
    }

    canvas.restore();

    stopwatch.stop();
    _frameNumber++;
    _statsSink.record(
      PaneRenderStats(
        frameNumber: _frameNumber,
        paintMicroseconds: stopwatch.elapsedMicroseconds,
        visibleCells: paintedCells,
        visibleEdges: paintedEdges,
        totalCells: _laidOut.graph.cells.length,
        totalEdges: _laidOut.graph.edges.length,
      ),
    );
  }

  // ── Viewport culling ───────────────────────────────────────────

  /// Design-space rectangle currently visible through the viewport.
  ///
  /// Inverts the paint transform (`design = (screen − offset) / zoom`,
  /// the same mapping the hit-tester uses) over the viewport rect
  /// `Offset.zero & size`, then inflates by [_cullMargin] so elements
  /// whose *drawn* extent slightly exceeds their bounds (pin stubs,
  /// selection strokes, boundary-port labels) are not clipped early.
  ///
  /// Returns [Rect.largest] (cull nothing) when culling is disabled or
  /// the zoom is degenerate, so every element paints.
  Rect _visibleDesignRect() {
    final zoom = _transform.zoom;
    if (!_cullingEnabled || zoom <= 0) return Rect.largest;
    final offset = _transform.offset;
    final left = -offset.dx / zoom;
    final top = -offset.dy / zoom;
    final right = (size.width - offset.dx) / zoom;
    final bottom = (size.height - offset.dy) / zoom;
    return Rect.fromLTRB(left, top, right, bottom).inflate(_cullMargin);
  }

  /// Design-space slop added around the visible rect before culling.
  /// Wide enough to cover a boundary-port label (drawn up to ~84 px to
  /// the right of its port) plus stroke/stub overhang.
  static const double _cullMargin = 96;

  // ── Cell painting ──────────────────────────────────────────────

  int _paintCells(Canvas canvas, LodBand band, Rect visibleRect) {
    _pendingOutsideLabels.clear();
    final symbolCtx = SymbolPaintContext.fromTheme(_theme);
    final labelStyle = (_theme.textTheme.labelSmall ?? const TextStyle())
        .copyWith(color: _theme.colorScheme.onSurface);
    final selectedCellIds = _selectedCellIds();
    // Hoisted out of _paintCellPinStubs, which is called once per cell:
    // building this set fresh per cell per frame was pure waste. Matches
    // the selectedCellIds treatment above.
    final selectedPortIds = _selectedPortIds();
    // Only the cells the scene index says may be on screen, in scope order;
    // the cull test below still decides. See [SchematicSceneIndex].
    final scene = SchematicSceneIndex.of(_laidOut);
    final cells = scene.cells;
    final nodes = scene.cellNodes;
    final candidates = scene.cellsIn(visibleRect);
    final candidateCount = candidates?.length ?? cells.length;
    var count = 0;
    for (var k = 0; k < candidateCount; k++) {
      final i = candidates == null ? k : candidates[k];
      final cell = cells[i];
      final position = nodes[i];
      final rect = Rect.fromLTWH(
        position.bounds.x,
        position.bounds.y,
        position.bounds.width,
        position.bounds.height,
      );
      // Viewport cull: skip cells entirely outside the visible design
      // rect. The clipRect at paint() would discard their draw calls
      // anyway, but skipping here also avoids the per-cell symbol +
      // label build cost — the point of culling.
      if (!visibleRect.overlaps(rect)) continue;
      final isHighlighted =
          _overlay.isEmpty || _overlay.highlightsCell(cell.id);
      // Filter-view hide mode: skip non-highlighted cells entirely
      // when a [TraceOverlay] is active. Selection still wins so the
      // user can keep a selection visible even outside the overlay.
      final isSelected = selectedCellIds.contains(cell.id);
      if (_filterViewMode &&
          !_overlay.isEmpty &&
          !isHighlighted &&
          !isSelected) {
        continue;
      }
      canvas
        ..save()
        ..translate(rect.left, rect.top);
      // A cell that is POSITIVELY in the active cone (overlay non-empty and
      // this cell highlighted) — as opposed to `isHighlighted`, which is
      // also true when there is no overlay at all. The mid/detail symbol
      // body is painted identically regardless of cone membership, so
      // without a positive accent the cone cells were barely distinguishable
      // from the dimmed rest at normal zoom.
      final isConeCell = !_overlay.isEmpty && isHighlighted;
      switch (band) {
        case LodBand.overview:
          _paintOverviewCell(
            canvas,
            rect.size,
            cell,
            isHighlighted,
            _transform.zoom,
          );
        case LodBand.mid:
          _cellBodyPainterFactory(cell)(canvas, rect.size, symbolCtx);
        case LodBand.detail:
          _cellBodyPainterFactory(cell)(canvas, rect.size, symbolCtx);
          final anchoredPins = _laidOut.symbolCells[cell.id];
          if (anchoredPins == null) {
            _paintCellLabel(canvas, rect.size, cell, labelStyle, band);
          } else {
            _paintSymbolPinNames(
              canvas,
              cell,
              position,
              anchoredPins,
              labelStyle,
              band,
            );
            _pendingOutsideLabels.add(
              _OutsideLabel(cell, rect, isHighlighted: isHighlighted),
            );
          }
      }
      // Accent the cone cell in ALL bands (drawn under any selection
      // overlay so a selected cone cell still reads as selected).
      if (isConeCell) {
        _paintCellConeAccent(canvas, rect.size);
      }
      if (isSelected) {
        _paintCellSelectionOverlay(canvas, rect.size);
      }
      canvas.restore();
      if (band != LodBand.overview) {
        _paintCellPinStubs(
          canvas,
          cell,
          position,
          isHighlighted,
          selectedPortIds,
          band,
        );
      }
      if (!isHighlighted) {
        _paintDimVeil(canvas, rect);
      }
      count++;
    }
    return count;
  }

  void _paintOverviewCell(
    Canvas canvas,
    Size size,
    SchematicCell cell,
    bool isHighlighted,
    double zoom,
  ) {
    final fill = Paint()
      ..color = _overviewColorFor(cell.kind, isHighlighted)
      ..style = PaintingStyle.fill;
    // Never let a cell fall below its device-pixel floor: the canvas is
    // scaled by [zoom], so the floor in design units is the pixel count
    // divided by it (see [SchematicViewportLimits.overviewMinCellPx]).
    final floor = zoom > 0
        ? SchematicViewportLimits.overviewMinCellPx / zoom
        : 0.0;
    final drawn = Size(
      math.max(size.width, floor),
      math.max(size.height, floor),
    );
    canvas.drawRect(Offset.zero & drawn, fill);
  }

  Color _overviewColorFor(CellKind kind, bool isHighlighted) {
    final base = switch (kind) {
      CellKind.andGate => Colors.lightBlueAccent.shade100,
      CellKind.orGate => Colors.lightGreenAccent.shade100,
      CellKind.notGate => Colors.pinkAccent.shade100,
      CellKind.mux => Colors.orangeAccent.shade100,
      CellKind.flipFlop => Colors.purpleAccent.shade100,
      CellKind.latch => Colors.tealAccent.shade100,
      CellKind.generic => _theme.colorScheme.surfaceContainerHighest,
    };
    return isHighlighted ? base : base.withValues(alpha: 0.35);
  }

  void _paintCellLabel(
    Canvas canvas,
    Size size,
    SchematicCell cell,
    TextStyle style,
    LodBand band,
  ) {
    // Memoized per (cell, band): the layout is stable for a given
    // NetlistLayout + theme, so we lay it out once and just re-paint it
    // each frame. The cache is disposed when the layout or theme changes.
    //
    // A long name keeps its tail: in a flat netlist every cell name carries
    // the same dotted path, and the end is what tells two cells apart.
    final painter = _labelLayout(
      'c:${cell.id}:${band.name}',
      cell.displayLabel,
      style,
      size.width - 8,
      elideStart: true,
    );
    painter.paint(
      canvas,
      Offset(
        (size.width - painter.width) / 2,
        (size.height - painter.height) / 2,
      ),
    );
  }

  /// Labels of custom-symbol cells collected by [_paintCells] for
  /// [_paintOutsideCellLabels], which draws them after the wires.
  final List<_OutsideLabel> _pendingOutsideLabels = <_OutsideLabel>[];

  /// The widest an outside label may be, in design units, when its cell is
  /// narrower: a symbol node can be small, and the name should stay legible.
  static const double _outsideLabelMinWidth = 120;

  /// Gap between a symbol cell's drawing and its outside label.
  static const double _outsideLabelGap = 2;

  /// Paints the label of every cell drawn with a custom symbol outside its
  /// drawing: centred below the node, or above it when a neighbouring cell
  /// or module port occupies the space below and none occupies the space
  /// above. A surface-coloured backing keeps it legible over wires.
  void _paintOutsideCellLabels(Canvas canvas) {
    if (_pendingOutsideLabels.isEmpty) return;
    final style = (_theme.textTheme.labelSmall ?? const TextStyle()).copyWith(
      color: _theme.colorScheme.onSurface,
    );
    final backing = Paint()
      ..color = _theme.colorScheme.surface.withValues(alpha: 0.85)
      ..style = PaintingStyle.fill;
    for (final label in _pendingOutsideLabels) {
      final cellRect = label.rect;
      final painter = _labelLayout(
        'o:${label.cell.id}',
        label.cell.displayLabel,
        style,
        math.max(cellRect.width, _outsideLabelMinWidth),
        elideStart: true,
      );
      final rect = outsideLabelRect(
        cellRect,
        Size(painter.width, painter.height),
        isFree: (candidate) => _isFreeOfOtherNodes(candidate, label.cell.id),
      );
      canvas.drawRect(rect.inflate(1), backing);
      painter.paint(canvas, rect.topLeft);
      if (!label.isHighlighted) _paintDimVeil(canvas, rect.inflate(1));
    }
    _pendingOutsideLabels.clear();
  }

  /// Whether [rect] overlaps no cell other than [selfId] and no module port.
  bool _isFreeOfOtherNodes(Rect rect, String selfId) {
    final scene = SchematicSceneIndex.of(_laidOut);
    final cells =
        scene.cellsIn(rect) ?? List<int>.generate(scene.cells.length, (i) => i);
    for (final i in cells) {
      if (scene.cells[i].id == selfId) continue;
      if (_nodeRect(scene.cellNodes[i]).overlaps(rect)) return false;
    }
    final ports =
        scene.boundaryPortsIn(rect) ??
        List<int>.generate(scene.boundaryPorts.length, (i) => i);
    for (final i in ports) {
      if (_nodeRect(scene.boundaryPortNodes[i]).overlaps(rect)) return false;
    }
    return true;
  }

  static Rect _nodeRect(NodePosition node) => Rect.fromLTWH(
    node.bounds.x,
    node.bounds.y,
    node.bounds.width,
    node.bounds.height,
  );

  /// Where the outside label of a cell at [cellRect] goes, for a label of
  /// [labelSize]: centred under the cell, [_outsideLabelGap] below it, when
  /// [isFree] says that space is clear; otherwise the same distance above
  /// when that is clear; otherwise below regardless. Never inside
  /// [cellRect].
  @visibleForTesting
  static Rect outsideLabelRect(
    Rect cellRect,
    Size labelSize, {
    required bool Function(Rect candidate) isFree,
  }) {
    final left = cellRect.center.dx - labelSize.width / 2;
    final below = Rect.fromLTWH(
      left,
      cellRect.bottom + _outsideLabelGap,
      labelSize.width,
      labelSize.height,
    );
    if (isFree(below)) return below;
    final above = Rect.fromLTWH(
      left,
      cellRect.top - _outsideLabelGap - labelSize.height,
      labelSize.width,
      labelSize.height,
    );
    return isFree(above) ? above : below;
  }

  /// Inset of a pin name from the edge of a symbol's drawing.
  static const double _pinNameInset = 3;

  /// Names each pin of a custom-symbol [cell] that a symbol anchor names
  /// exactly ([anchoredPins]), just inside the drawing beside the pin, on
  /// the pin's face: left-aligned against the west edge, right-aligned
  /// against the east, centred under the north edge and above the south.
  /// Detail band only. A pin no anchor names gets no name.
  void _paintSymbolPinNames(
    Canvas canvas,
    SchematicCell cell,
    NodePosition position,
    Set<String> anchoredPins,
    TextStyle labelStyle,
    LodBand band,
  ) {
    if (anchoredPins.isEmpty) return;
    final width = position.bounds.width;
    final height = position.bounds.height;
    final style = labelStyle.copyWith(
      fontSize: (labelStyle.fontSize ?? 11) * 0.8,
    );
    final backing = Paint()
      ..color = _theme.colorScheme.surface.withValues(alpha: 0.7)
      ..style = PaintingStyle.fill;
    for (final port in cell.ports) {
      if (!anchoredPins.contains(port.name)) continue;
      final box = position.ports[port.id];
      if (box == null) continue;
      final cx = box.x + box.width / 2;
      final cy = box.y + box.height / 2;
      final face = symbolPinFace(box, width, height);
      final vertical =
          face == SchematicPortSide.west || face == SchematicPortSide.east;
      final painter = _labelLayout(
        'p:${port.id}:${band.name}',
        port.name,
        style,
        math.max(1, (vertical ? width / 2 : width) - 2 * _pinNameInset),
      );
      final origin = switch (face) {
        SchematicPortSide.west => Offset(
          _pinNameInset,
          cy - painter.height / 2,
        ),
        SchematicPortSide.east => Offset(
          width - _pinNameInset - painter.width,
          cy - painter.height / 2,
        ),
        SchematicPortSide.north => Offset(
          cx - painter.width / 2,
          _pinNameInset,
        ),
        SchematicPortSide.south => Offset(
          cx - painter.width / 2,
          height - _pinNameInset - painter.height,
        ),
      };
      canvas.drawRect(
        (origin & Size(painter.width, painter.height)).inflate(0.5),
        backing,
      );
      painter.paint(canvas, origin);
    }
  }

  /// The face of a symbol node that a pin [box] (relative to the node, of
  /// [width] by [height]) sits on: the layout puts west pins wholly left of
  /// the node, east pins at its right edge, north pins above it and south
  /// pins at its bottom edge.
  @visibleForTesting
  static SchematicPortSide symbolPinFace(
    BoundingBox box,
    double width,
    double height,
  ) {
    const slop = 0.5;
    if (box.x + box.width <= slop) return SchematicPortSide.west;
    if (box.x >= width - slop) return SchematicPortSide.east;
    if (box.y + box.height <= slop) return SchematicPortSide.north;
    return SchematicPortSide.south;
  }

  /// Positive cone-of-influence highlight: an azure tint + outline drawn
  /// over a cone cell's body in every LOD band. Distinct hue from the amber
  /// selection overlay so a cone cell and a selected cell never read the
  /// same. See [NetcruxColors.coneAccent] / [NetcruxColors.coneFillTint].
  void _paintCellConeAccent(Canvas canvas, Size size) {
    final tint = Paint()
      ..color = NetcruxColors.coneFillTint
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = NetcruxColors.coneAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final rect = Offset.zero & size;
    canvas
      ..drawRect(rect, tint)
      ..drawRect(rect, stroke);
  }

  void _paintCellSelectionOverlay(Canvas canvas, Size size) {
    final tint = Paint()
      ..color = NetcruxColors.selectionFillTint
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = NetcruxColors.selectionAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4;
    final rect = Offset.zero & size;
    canvas
      ..drawRect(rect, tint)
      ..drawRect(rect, stroke);
  }

  void _paintCellPinStubs(
    Canvas canvas,
    SchematicCell cell,
    NodePosition position,
    bool isHighlighted,
    Set<String> selectedPortIds,
    LodBand band,
  ) {
    final stubPaint = Paint()
      ..color = isHighlighted
          ? _theme.colorScheme.primary
          : NetcruxColors.overlayDimStroke
      ..style = PaintingStyle.fill;
    final selPaint = Paint()
      ..color = NetcruxColors.selectionAccent
      ..style = PaintingStyle.fill;
    final undrivenPaint = Paint()
      ..color = isHighlighted
          ? _theme.colorScheme.error
          : NetcruxColors.overlayDimStroke
      ..style = PaintingStyle.fill;
    for (final port in cell.ports) {
      final box = position.ports[port.id];
      if (box == null) continue;
      final cx = position.bounds.x + box.x + box.width / 2;
      final cy = position.bounds.y + box.y + box.height / 2;
      final isSelectedPort = selectedPortIds.contains(port.id);
      final tie = port.tie;
      if (tie.kind == PinTieKind.constant || tie.kind == PinTieKind.undriven) {
        // The stub leaves the pin away from the body: leftwards from a pin
        // on the west half of the cell, rightwards from one on the east.
        final outward = box.x + box.width / 2 < position.bounds.width / 2
            ? -1.0
            : 1.0;
        _paintTieStub(
          canvas,
          port,
          Offset(cx, cy),
          outward,
          isHighlighted,
          band,
        );
      }
      final dotPaint = isSelectedPort
          ? selPaint
          : tie.kind == PinTieKind.undriven
          ? undrivenPaint
          : stubPaint;
      canvas.drawCircle(
        Offset(cx, cy),
        isSelectedPort ? 3.5 : 2.5,
        dotPaint,
      );
    }
  }

  /// Design-space length of the stub drawn out of a constant-tied or
  /// undriven pin. Short enough to stay inside the gap ELK leaves between
  /// layers.
  static const double _tieStubLength = 9;

  /// Draws the stub of a pin whose [SchematicPort.tie] is a constant or
  /// undriven, from [pin] towards [outward] (`-1` left, `1` right).
  ///
  /// A constant gets a stub in the muted wire colour, labelled with its
  /// value in the detail band. An undriven input gets a stub in the theme's
  /// error colour ending in an open ring, the mark of a pin left floating;
  /// it needs no text to read at any zoom the stub is drawn at.
  void _paintTieStub(
    Canvas canvas,
    SchematicPort port,
    Offset pin,
    double outward,
    bool isHighlighted,
    LodBand band,
  ) {
    final undriven = port.tie.kind == PinTieKind.undriven;
    final colour = !isHighlighted
        ? NetcruxColors.overlayDimStroke
        : undriven
        ? _theme.colorScheme.error
        : _theme.colorScheme.onSurfaceVariant;
    final stroke = Paint()
      ..color = colour
      ..style = PaintingStyle.stroke
      ..strokeWidth = undriven ? 1.6 : 1.2;
    final end = pin.translate(outward * _tieStubLength, 0);
    canvas.drawLine(pin, end, stroke);
    if (undriven) {
      canvas.drawCircle(end.translate(outward * 2, 0), 2, stroke);
      return;
    }
    final text = port.tie.constantText;
    if (band != LodBand.detail || text == null) return;
    final painter = _labelLayout(
      't:${port.id}:${band.name}:$isHighlighted',
      text,
      (_theme.textTheme.labelSmall ?? const TextStyle()).copyWith(
        color: colour,
        fontSize: 8,
        height: 1,
      ),
      28,
    );
    final dx = outward < 0 ? end.dx - 1 - painter.width : end.dx + 1;
    painter.paint(canvas, Offset(dx, end.dy - painter.height / 2));
  }

  void _paintDimVeil(Canvas canvas, Rect rect) {
    final veil = Paint()
      ..color = NetcruxColors.overlayDimVeil
      ..style = PaintingStyle.fill;
    canvas.drawRect(rect, veil);
  }

  // ── Edge painting ──────────────────────────────────────────────

  /// Stroke width for [band]: [other] outside the overview band; inside it
  /// [overview], but never thinner than [minDevicePx] on screen, so wires
  /// survive the zoom a huge scope fits at
  /// (see [SchematicViewportLimits.overviewMinWirePx]).
  double _strokeWidth(
    LodBand band, {
    required double overview,
    required double other,
    double minDevicePx = SchematicViewportLimits.overviewMinWirePx,
  }) {
    if (band != LodBand.overview) return other;
    final zoom = _transform.zoom;
    return zoom > 0 ? math.max(overview, minDevicePx / zoom) : overview;
  }

  int _paintEdges(Canvas canvas, LodBand band, Rect visibleRect) {
    final basePaint = Paint()
      ..color = _theme.colorScheme.onSurfaceVariant
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth(band, overview: 0.6, other: 1.2)
      ..strokeCap = StrokeCap.round;
    // Selected wires paint in two passes — a wide semi-transparent amber
    // glow underlay, then a bright near-white core on top — so a selected
    // net (especially a multi-strand bus) is unmistakable against the
    // warm-gold default wires without the user having to zoom in. Both
    // widths scale down in the overview band to stay proportional.
    final selectedGlowPaint = Paint()
      ..color = NetcruxColors.selectedWireGlow
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth(
        band,
        overview: 3.6,
        other: 7.2,
        minDevicePx: 3,
      )
      ..strokeCap = StrokeCap.round;
    final selectedCorePaint = Paint()
      ..color = NetcruxColors.selectedWireCore
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth(
        band,
        overview: 1.8,
        other: 3.6,
        minDevicePx: 1.5,
      )
      ..strokeCap = StrokeCap.round;
    final dimPaint = Paint()
      ..color = NetcruxColors.overlayDimStroke
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth(band, overview: 0.8, other: 0.8)
      ..strokeCap = StrokeCap.round;
    // Positive accent for a cone/trace-highlighted wire (overlay active).
    // Colors the cone's wiring so the highlighted sub-graph reads as a
    // connected cone, not merely "the wires that weren't dimmed".
    final conePaint = Paint()
      ..color = NetcruxColors.coneAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth(band, overview: 1, other: 2)
      ..strokeCap = StrokeCap.round;
    final selectedEdgeIds = _selectedEdgeIds();
    final selectedWireNetIds = _selectedWireNetIds();
    final activityOverride = _netActivityColorOverride;
    // Only the wires the scene index says may be on screen, in layout order;
    // their bounds are computed once per layout rather than every frame.
    final scene = SchematicSceneIndex.of(_laidOut);
    final wires = scene.wires;
    final candidates = scene.wiresIn(visibleRect);
    final candidateCount = candidates?.length ?? wires.length;
    var count = 0;
    for (var k = 0; k < candidateCount; k++) {
      final i = candidates == null ? k : candidates[k];
      final edge = wires[i];
      // Viewport cull: skip edges whose polyline bounding box is wholly
      // outside the visible design rect.
      if (!visibleRect.overlaps(scene.wireBounds(i))) continue;
      final isHighlighted =
          _overlay.isEmpty || _overlay.highlightsEdge(edge.id);
      // A wire selection matches on net id (stable across the layout /
      // graph id-counter divergence) as well as the raw edge id (which a
      // direct canvas hit-test supplies). See [_selectedWireNetIds].
      final edgeNetId = selectedWireNetIds.isEmpty ? null : edge.netId;
      final isSelected =
          selectedEdgeIds.contains(edge.id) ||
          (edgeNetId != null && selectedWireNetIds.contains(edgeNetId));
      // Filter-view hide mode: skip non-highlighted edges entirely
      // when a [TraceOverlay] is active. Selection still wins.
      if (_filterViewMode &&
          !_overlay.isEmpty &&
          !isHighlighted &&
          !isSelected) {
        continue;
      }
      final path = Path()..moveTo(edge.points.first.x, edge.points.first.y);
      for (var i = 1; i < edge.points.length; i++) {
        path.lineTo(edge.points[i].x, edge.points[i].y);
      }
      // Selected wires: glow underlay + bright core, drawn on top of
      // everything else so the selection reads at a glance. Every drawn
      // edge of a selected net matches (see [_selectedWireNetIds]), so a
      // multi-bit bus lights all its strands.
      if (isSelected) {
        canvas
          ..drawPath(path, selectedGlowPaint)
          ..drawPath(path, selectedCorePaint);
        count++;
        continue;
      }
      final Paint paint;
      if (!isHighlighted) {
        paint = dimPaint;
      } else {
        final activityColor = activityOverride?[edge.id];
        if (activityColor != null) {
          // Net-activity color override extension point: when
          // the Pro overlay publishes a per-edge color, render the
          // wire at that color *in place of* the default base paint.
          // Allocated per-edge because the color varies per edge —
          // pooling buys nothing here.
          paint = Paint()
            ..color = activityColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = _strokeWidth(band, overview: 1, other: 2)
            ..strokeCap = StrokeCap.round;
        } else if (!_overlay.isEmpty) {
          // Highlighted wire under an active cone/trace overlay: paint it
          // in the cone accent so the cone's wiring pops.
          paint = conePaint;
        } else {
          paint = basePaint;
        }
      }
      canvas.drawPath(path, paint);
      count++;
    }
    return count;
  }

  // ── Boundary port painting ──────────────────────────────────────

  void _paintBoundaryPorts(Canvas canvas, LodBand band, Rect visibleRect) {
    final basePaint = Paint()
      ..color = _theme.colorScheme.tertiary
      ..style = PaintingStyle.fill;
    final selPaint = Paint()
      ..color = NetcruxColors.selectionAccent
      ..style = PaintingStyle.fill;
    final dimPaint = Paint()
      ..color = NetcruxColors.overlayDimStroke
      ..style = PaintingStyle.fill;
    final selectedBoundaryIds = _selectedBoundaryPortIds();
    final scene = SchematicSceneIndex.of(_laidOut);
    final ports = scene.boundaryPorts;
    final nodes = scene.boundaryPortNodes;
    final candidates = scene.boundaryPortsIn(visibleRect);
    final candidateCount = candidates?.length ?? ports.length;
    for (var k = 0; k < candidateCount; k++) {
      final i = candidates == null ? k : candidates[k];
      final port = ports[i];
      final pos = nodes[i];
      final rect = Rect.fromLTWH(
        pos.bounds.x,
        pos.bounds.y,
        pos.bounds.width,
        pos.bounds.height,
      );
      // Viewport cull: the visible rect carries a margin wide enough to
      // keep a just-off-screen port whose label reaches back into view.
      if (!visibleRect.overlaps(rect)) continue;
      final isHighlighted =
          _overlay.isEmpty || _overlay.highlightsBoundaryPort(port.id);
      final isSelected = selectedBoundaryIds.contains(port.id);
      // Filter-view hide mode: skip non-highlighted boundary ports
      // entirely when a [TraceOverlay] is active. Selection wins.
      if (_filterViewMode &&
          !_overlay.isEmpty &&
          !isHighlighted &&
          !isSelected) {
        continue;
      }
      final paint = isSelected
          ? selPaint
          : isHighlighted
          ? basePaint
          : dimPaint;
      canvas.drawRect(rect, paint);
      if (band == LodBand.detail && isHighlighted) {
        _paintBoundaryLabel(canvas, rect, port, band);
      }
    }
  }

  // ── Crossing overlay (CDC + Reset) ──────────────────────────────

  /// Draws the active [SchematicCrossingOverlay]: first every laid-out
  /// wire of the crossing net ([SchematicCrossingOverlay.netIds], matched
  /// on [EdgeRoute.netId] the way a wire selection is, so each strand of
  /// a bus paints), then a severity-coded outline around each named cell.
  /// The wires take the severity colour at the selected-wire core width,
  /// so a crossing net that is also selected reads as the crossing.
  ///
  /// Source-side cells get the
  /// strongest stroke, intermediate cells get a medium stroke, and
  /// destination cells get the strongest stroke as well — the
  /// overlay's severity colour drives the hue, the role drives the
  /// stroke weight.
  ///
  /// The pass runs last — after the regular cell / edge / boundary
  /// painting, and therefore after the per-cell selection accent
  /// [_paintCells] strokes inline. On a cell that is both selected and
  /// part of the crossing, the severity outline is what the user sees;
  /// the two strokes are at different inflations so the accent stays
  /// partly visible underneath.
  ///
  /// The cell cost is O(overlay cells), not O(design cells): the three id
  /// sets are iterated directly and each id is resolved through
  /// [NetlistLayout.findNode]'s O(1) index. Scanning every cell in the
  /// graph and asking [SchematicCrossingOverlay.involvesCell] made an
  /// active overlay cost a full pass over the design on every frame,
  /// while a crossing names only a handful of cells. The wire pass walks
  /// only the wires the scene index puts in the viewport, and is skipped
  /// when the overlay names no nets.
  void _paintCrossingOverlay(
    Canvas canvas,
    SchematicCrossingOverlay overlay,
    LodBand band,
    Rect visibleRect,
  ) {
    final netIds = overlay.netIds;
    if (netIds.isNotEmpty) {
      final wirePaint = Paint()
        ..color = overlay.severityColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = _strokeWidth(
          band,
          overview: 1.8,
          other: 3.6,
          minDevicePx: 1.5,
        )
        ..strokeCap = StrokeCap.round;
      final scene = SchematicSceneIndex.of(_laidOut);
      final wires = scene.wires;
      final candidates = scene.wiresIn(visibleRect);
      final candidateCount = candidates?.length ?? wires.length;
      for (var k = 0; k < candidateCount; k++) {
        final i = candidates == null ? k : candidates[k];
        final edge = wires[i];
        final netId = edge.netId;
        if (netId == null || !netIds.contains(netId)) continue;
        if (edge.points.isEmpty) continue;
        if (!visibleRect.overlaps(scene.wireBounds(i))) continue;
        final path = Path()..moveTo(edge.points.first.x, edge.points.first.y);
        for (var p = 1; p < edge.points.length; p++) {
          path.lineTo(edge.points[p].x, edge.points[p].y);
        }
        canvas.drawPath(path, wirePaint);
      }
    }
    final sourcePaint = Paint()
      ..color = overlay.severityColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;
    final intermediatePaint = Paint()
      ..color = overlay.severityColor.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    final destinationPaint = Paint()
      ..color = overlay.severityColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;
    // Role precedence matches the previous per-cell branch: source wins
    // over destination, destination over intermediate. Painting the sets
    // in that order and skipping ids already drawn keeps a cell that
    // appears in two roles stroked exactly once, as before.
    final painted = <String>{};
    void paintRole(Set<String> cellIds, Paint paint) {
      for (final cellId in cellIds) {
        if (!painted.add(cellId)) continue;
        final position = _laidOut.layout.findNode(cellId);
        if (position == null) continue;
        // 2dp inflation keeps the outline visually distinct from the
        // cell body without occluding pin stubs.
        canvas.drawRect(
          Rect.fromLTWH(
            position.bounds.x - 2,
            position.bounds.y - 2,
            position.bounds.width + 4,
            position.bounds.height + 4,
          ),
          paint,
        );
      }
    }

    paintRole(overlay.sourceCellIds, sourcePaint);
    paintRole(overlay.destinationCellIds, destinationPaint);
    paintRole(overlay.intermediateCellIds, intermediatePaint);
  }

  // ── Collaboration presence ──────────────────────────────────────

  /// Draws the other participants' selections and pointers.
  ///
  /// Two passes with different scaling rules, and the split is the whole
  /// design of this method:
  ///
  /// * **Selections are design-space geometry.** A colleague's outline has
  ///   to sit exactly on the cell or wire they picked, so it is stroked in
  ///   the same transformed space everything else uses. Stroke widths are
  ///   divided by the zoom so the outline stays a consistent *visual*
  ///   weight — an outline that thickens as you zoom in swallows the shape
  ///   it is outlining.
  /// * **Pointers are chrome.** A cursor glyph and a name label are read at
  ///   screen size, not design size, so each one counter-scales by `1/zoom`
  ///   around its anchor. Without that, zooming out to see a whole design
  ///   shrinks every colleague's cursor to nothing at precisely the moment
  ///   the room is most likely to be pointing at something.
  ///
  /// Cost is O(remote selections + participants), never O(design): every id
  /// resolves through [NetlistLayout.findNode] / [NetlistLayout.findEdge],
  /// which are O(1) memoized indexes. A room of eight people who have each
  /// selected a handful of elements is a few dozen lookups per frame.
  void _paintPresenceOverlay(Canvas canvas, CollabPresenceOverlay presence) {
    final zoom = _transform.zoom;
    // Guard the divisions below. `zoom` is clamped well above zero by the
    // gesture handler, but this runs on whatever the render object was last
    // handed, and a zero would produce infinities inside Skia rather than an
    // exception anything catches.
    final inverseZoom = zoom > 0 ? 1.0 / zoom : 1.0;

    _paintPresenceSelections(canvas, presence, inverseZoom);
    for (final cursor in presence.cursors) {
      _paintPresenceCursor(canvas, cursor, inverseZoom);
    }
  }

  /// Outlines every element a remote participant has selected, in their
  /// colour.
  void _paintPresenceSelections(
    Canvas canvas,
    CollabPresenceOverlay presence,
    double inverseZoom,
  ) {
    if (presence.selectionColors.isEmpty) return;
    // Dashes rather than a solid stroke: a remote selection must not read as
    // your own. The local accent is a solid amber outline plus a filled tint
    // (see [_paintCellSelectionOverlay]); a dashed outline in a palette
    // colour is distinguishable from it at a glance and at any zoom, which a
    // second solid outline in a different hue is not.
    for (final entry in presence.selectionColors.entries) {
      final paint = Paint()
        ..color = entry.value
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0 * inverseZoom
        ..strokeCap = StrokeCap.round;

      final node = _laidOut.layout.findNode(entry.key);
      if (node != null) {
        final inset = 3.0 * inverseZoom;
        _strokeDashedRect(
          canvas,
          Rect.fromLTWH(
            node.bounds.x - inset,
            node.bounds.y - inset,
            node.bounds.width + inset * 2,
            node.bounds.height + inset * 2,
          ),
          paint,
          inverseZoom,
        );
        continue;
      }

      final edge = _laidOut.layout.findEdge(entry.key);
      if (edge != null && edge.points.length >= 2) {
        final path = Path()..moveTo(edge.points.first.x, edge.points.first.y);
        for (var i = 1; i < edge.points.length; i++) {
          path.lineTo(edge.points[i].x, edge.points[i].y);
        }
        canvas.drawPath(path, paint..strokeWidth = 3.0 * inverseZoom);
        continue;
      }

      // Ports arrive as `cellId:portId`; resolve the cell and then the port
      // box within it. An id that resolves to nothing is dropped silently —
      // a peer on a different elaboration of the design will name elements
      // this layout does not have, and that is a mismatch the netlist-hash
      // banner reports, not something to draw a stray box for.
      final separator = entry.key.lastIndexOf(':');
      if (separator <= 0) continue;
      final owner = _laidOut.layout.findNode(
        entry.key.substring(0, separator),
      );
      final box = owner?.ports[entry.key];
      if (owner == null || box == null) continue;
      canvas.drawRect(
        Rect.fromLTWH(
          owner.bounds.x + box.x,
          owner.bounds.y + box.y,
          box.width,
          box.height,
        ).inflate(2.0 * inverseZoom),
        paint,
      );
    }
  }

  /// Strokes [rect] as a dashed outline.
  ///
  /// Flutter has no dash support on [Paint], and pulling `path_drawing` in
  /// for four straight lines would be a dependency for an afternoon's
  /// arithmetic. Dash length is in *design* units scaled by [inverseZoom],
  /// so the dashes stay the same visual size at every zoom.
  void _strokeDashedRect(
    Canvas canvas,
    Rect rect,
    Paint paint,
    double inverseZoom,
  ) {
    final dash = 6.0 * inverseZoom;
    final gap = 4.0 * inverseZoom;
    void dashedLine(Offset from, Offset to) {
      final delta = to - from;
      final length = delta.distance;
      if (length <= 0) return;
      final step = delta / length;
      var travelled = 0.0;
      while (travelled < length) {
        final end = (travelled + dash).clamp(0.0, length);
        canvas.drawLine(
          from + step * travelled,
          from + step * end,
          paint,
        );
        travelled = end + gap;
      }
    }

    dashedLine(rect.topLeft, rect.topRight);
    dashedLine(rect.topRight, rect.bottomRight);
    dashedLine(rect.bottomRight, rect.bottomLeft);
    dashedLine(rect.bottomLeft, rect.topLeft);
  }

  /// Draws one remote pointer: an arrow glyph with the participant's name on
  /// a filled chip beside it, both at screen size.
  void _paintPresenceCursor(
    Canvas canvas,
    CollabPresenceCursor cursor,
    double inverseZoom,
  ) {
    canvas
      ..save()
      ..translate(cursor.x, cursor.y)
      // Everything below this line is in screen units: the counter-scale
      // cancels the viewport zoom, so a 14 px label is 14 px whatever the
      // design is scaled to.
      ..scale(inverseZoom, inverseZoom);

    final fill = Paint()..color = cursor.color;
    // A plain triangular pointer. Deliberately not the platform cursor
    // shape: it must read as somebody else's, and matching the local
    // pointer exactly is how you get two cursors nobody can tell apart.
    final arrow = Path()
      ..moveTo(0, 0)
      ..lineTo(0, 15)
      ..lineTo(4.2, 11.2)
      ..lineTo(6.8, 17)
      ..lineTo(9.4, 15.8)
      ..lineTo(6.8, 10.2)
      ..lineTo(12, 9.6)
      ..close();
    // A thin dark outline so a light palette colour still has an edge
    // against a light canvas.
    final outline = Paint()
      ..color = const Color(0x99000000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas
      ..drawPath(arrow, fill)
      ..drawPath(arrow, outline);

    final label = TextPainter(
      text: TextSpan(
        text: cursor.label,
        style: const TextStyle(
          color: Color(0xFF101010),
          fontSize: 11,
          fontWeight: FontWeight.w600,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 160);

    const chipPadH = 5.0;
    const chipPadV = 3.0;
    final chip = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        14,
        14,
        label.width + chipPadH * 2,
        label.height + chipPadV * 2,
      ),
      const Radius.circular(3),
    );
    canvas.drawRRect(chip, fill);
    // Dark text on the participant's own colour, rather than the theme's
    // onSurface: the chip is filled with an arbitrary palette hue, so the
    // contrast has to be decided against that hue and not against the
    // canvas behind it.
    label
      ..paint(canvas, const Offset(14 + chipPadH, 14 + chipPadV))
      ..dispose();

    canvas.restore();
  }

  void _paintBoundaryLabel(
    Canvas canvas,
    Rect rect,
    SchematicBoundaryPort port,
    LodBand band,
  ) {
    final style = (_theme.textTheme.labelSmall ?? const TextStyle()).copyWith(
      color: _theme.colorScheme.onSurface,
    );
    final painter = _labelLayout(
      'b:${port.id}:${band.name}',
      port.name,
      style,
      80,
    );
    final origin = Offset(
      rect.right + 4,
      rect.center.dy - painter.height / 2,
    );
    painter.paint(canvas, origin);
  }
}

/// Hard limits applied to viewport zoom.
class SchematicViewportLimits {
  /// Hard floor on zoom. Low enough that the largest flat scope the native
  /// layout engine hands back, a hundred thousand cells at ~470 000 ×
  /// 280 000 px, still fits a normal window. Each earlier floor clamped the
  /// fit of the next size up (0.1 clamped picorv32's core at ~15 000 ×
  /// 43 000 px; 0.01 clamped the hundred-thousand-cell fixture), and a
  /// clamped fit centres the camera on empty space between packed
  /// components with every cell sub-pixel, which reads as a blank pane. What
  /// keeps a fit this far out legible is [overviewMinCellPx] and
  /// [overviewMinWirePx], not the number itself.
  static const double minZoom = 0.001;

  /// Smallest footprint, in device pixels, the overview band gives a cell.
  ///
  /// At the zoom a hundred-thousand-cell scope fits, about 0.003, a 52 px
  /// cell is a sixth of a pixel and a whole scope vanished while the scroll
  /// bars insisted it was there. Two pixels keeps every cell a visible
  /// speck, so the scope reads as a fabric with its density and its
  /// component packing intact.
  static const double overviewMinCellPx = 2;

  /// The same floor for wires in the overview band: one device pixel.
  static const double overviewMinWirePx = 1;

  /// Hard ceiling on zoom (1000%).
  static const double maxZoom = 10;

  /// Clamps [zoom] to `[minZoom, maxZoom]`.
  static double clampZoom(double zoom) {
    if (zoom < minZoom) return minZoom;
    if (zoom > maxZoom) return maxZoom;
    return zoom;
  }
}

/// Drop-on-the-floor sink used by tests that don't care about stats.
class NoopRenderStatsSink implements RenderStatsSink {
  /// Creates a no-op sink.
  const NoopRenderStatsSink();

  @override
  void record(PaneRenderStats stats) {}
}

/// Recording sink so tests can introspect what the painter emitted.
class RecordingRenderStatsSink implements RenderStatsSink {
  /// Creates a recording sink with no samples.
  RecordingRenderStatsSink();

  /// Every sample recorded, in order.
  final List<PaneRenderStats> samples = <PaneRenderStats>[];

  /// Convenience: the most recent sample, or `null` before any
  /// paint has happened.
  PaneRenderStats? get last => samples.isEmpty ? null : samples.last;

  @override
  void record(PaneRenderStats stats) => samples.add(stats);
}

/// A custom-symbol cell whose label [SchematicCanvasRenderObject] paints
/// outside its drawing after the wires: the cell, its node rectangle in
/// design units, and whether the active overlay highlights it.
class _OutsideLabel {
  const _OutsideLabel(this.cell, this.rect, {required this.isHighlighted});

  final SchematicCell cell;
  final Rect rect;
  final bool isHighlighted;
}
