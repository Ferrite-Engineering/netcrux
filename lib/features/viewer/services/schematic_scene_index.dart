// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset, Rect;

import 'package:flutter/foundation.dart' show compute;
import 'package:netcrux/domain/models/layout/bounding_box.dart';
import 'package:netcrux/domain/models/layout/edge_route.dart';
import 'package:netcrux/domain/models/layout/node_position.dart';
import 'package:netcrux/domain/models/schematic/laid_out_graph.dart';
import 'package:netcrux/domain/models/schematic/schematic_graph.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';

/// Lookup structures over one scope, shared by the schematic painter, the
/// hit-tester and the keyboard navigator.
///
/// A [LaidOutGraph] is immutable, so everything here is built at most once
/// per graph and every later frame, click and keypress reads it. Before this
/// existed, each of those scanned the whole scope: on a 100,000-cell design
/// a frame spent ~15 ms walking cells and edges it then culled, a click
/// ~34 ms, and a keyboard step ~55 ms re-sorting every element into reading
/// order.
///
/// Each section is built in two steps. *Collecting* walks the graph and the
/// layout on the calling isolate and keeps the objects a query answers with
/// (cells, nodes, pins, routes) beside one flat array of their boxes.
/// *Gridding* turns those arrays into bucket grids, which is the expensive
/// half and touches nothing but numbers, so [warm] runs it on another
/// isolate for a large scope, when the laid-out graph is produced, and the
/// first frame and the first click find the grids ready. A section nothing
/// warmed is still built on first use, one section at a time, on the thread
/// that asked.
///
/// The spatial sections answer "which items might touch this rectangle" as
/// a list of item indices **in the scope's own order**, so a caller that
/// applies its original exact test to each candidate gets exactly the
/// result, and the paint order, its old full scan produced: the index only
/// skips items that could not have passed. A query that covers most of the
/// scope returns `null`, meaning "walk everything", because at that point
/// the scan is cheaper than the lookup.
class SchematicSceneIndex {
  SchematicSceneIndex._(this.laidOut);

  /// The index for [laidOut], built on first use and cached for the life of
  /// the graph (keyed by identity, released with it).
  factory SchematicSceneIndex.of(LaidOutGraph laidOut) =>
      _cache[laidOut] ??= SchematicSceneIndex._(laidOut);

  static final Expando<SchematicSceneIndex> _cache =
      Expando<SchematicSceneIndex>('SchematicSceneIndex');

  /// Builds every section of [laidOut]'s index ahead of its first use.
  ///
  /// The boxes are collected on this isolate; the grids are built from them
  /// on another isolate when the scope has at least [offIsolateThreshold]
  /// boxes, and inline below it, where spawning an isolate would cost more
  /// than the grids. Completes when the index is ready. Calling it again for
  /// the same graph returns the same future; a section a frame or a click
  /// built meanwhile is kept, since both are built from the same immutable
  /// graph and answer alike.
  static Future<void> warm(LaidOutGraph laidOut) =>
      SchematicSceneIndex.of(laidOut)._warm();

  /// Boxes, across every section, from which [warm] grids on another
  /// isolate rather than inline. An isolate costs a few milliseconds to
  /// start and to copy the arrays into; below this the grids cost less.
  static const int offIsolateThreshold = 1 << 15;

  /// The scope this indexes.
  final LaidOutGraph laidOut;

  Future<void>? _warming;

  Future<void> _warm() => _warming ??= _buildAhead();

  Future<void> _buildAhead() async {
    final cells = _Placed.collect<SchematicCell>(
      laidOut.graph.cells,
      (cell) => laidOut.layout.findNode(cell.id),
    );
    final boundary = _Placed.collect<SchematicBoundaryPort>(
      laidOut.graph.boundaryPorts,
      (port) => laidOut.layout.findNode(port.id),
    );
    final wires = _Wires.collect(laidOut);
    final pins = _Pins.collect(cells.items, cells.nodes);
    final segments = _Segments.collect(wires.routes);
    final reading = _ReadingOrder.collect(laidOut);
    final arrays = _SceneArrays(
      cells: cells.boxes,
      boundary: boundary.boxes,
      wires: wires.bounds,
      pins: pins.boxes,
      segments: segments.boxes,
      readingKeys: reading.keys,
    );
    final grids = arrays.boxCount >= offIsolateThreshold
        ? await compute(_buildSceneGrids, arrays)
        : _buildSceneGrids(arrays);
    _cellsOrNull ??= _Placed<SchematicCell>(
      cells.items,
      cells.nodes,
      _Grid.fromArrays(grids.cells),
    );
    _boundaryOrNull ??= _Placed<SchematicBoundaryPort>(
      boundary.items,
      boundary.nodes,
      _Grid.fromArrays(grids.boundary),
    );
    _wiresOrNull ??= _Wires(
      wires.routes,
      wires.bounds,
      _Grid.fromArrays(grids.wires),
    );
    _pinsOrNull ??= _Pins(
      pins.cell,
      pins.port,
      pins.box,
      _Grid.fromArrays(grids.pins),
    );
    _segmentsOrNull ??= _Segments(
      segments.owner,
      _Grid.fromArrays(grids.segments),
    );
    _readingOrNull ??= _ReadingOrder.fromPermutation(
      reading.elements,
      grids.readingOrder,
    );
  }

  // ── Cells ─────────────────────────────────────────────────────────

  /// Cells that have a laid-out node, in [SchematicGraph.cells] order.
  List<SchematicCell> get cells => _cells.items;

  /// The node of each entry in [cells], by the same index.
  List<NodePosition> get cellNodes => _cells.nodes;

  /// Indices into [cells] whose body may overlap [rect], ascending, or
  /// `null` for all of them.
  List<int>? cellsIn(Rect rect) => _cells.grid.query(rect);

  _Placed<SchematicCell>? _cellsOrNull;
  _Placed<SchematicCell> get _cells => _cellsOrNull ??= _Placed.build(
    laidOut.graph.cells,
    (cell) => laidOut.layout.findNode(cell.id),
  );

  // ── Boundary ports ────────────────────────────────────────────────

  /// Module ports that have a laid-out node, in
  /// [SchematicGraph.boundaryPorts] order.
  List<SchematicBoundaryPort> get boundaryPorts => _boundary.items;

  /// The node of each entry in [boundaryPorts], by the same index.
  List<NodePosition> get boundaryPortNodes => _boundary.nodes;

  /// Indices into [boundaryPorts] whose node may overlap [rect], ascending,
  /// or `null` for all of them.
  List<int>? boundaryPortsIn(Rect rect) => _boundary.grid.query(rect);

  _Placed<SchematicBoundaryPort>? _boundaryOrNull;
  _Placed<SchematicBoundaryPort> get _boundary =>
      _boundaryOrNull ??= _Placed.build(
        laidOut.graph.boundaryPorts,
        (port) => laidOut.layout.findNode(port.id),
      );

  // ── Cell pins ─────────────────────────────────────────────────────

  /// Every pin that has a box on its cell's node, in cell order and then
  /// declaration order: the entry's index into [cells].
  Int32List get pinCell => _pins.cell;

  /// The pin itself, by the same index as [pinCell].
  List<SchematicPort> get pins => _pins.port;

  /// The pin's box, relative to its cell's node, by the same index.
  List<BoundingBox> get pinBoxes => _pins.box;

  /// Indices into [pins] whose box may overlap [rect], ascending, or `null`
  /// for all of them.
  List<int>? pinsIn(Rect rect) => _pins.grid.query(rect);

  _Pins? _pinsOrNull;
  _Pins get _pins => _pinsOrNull ??= _Pins.build(cells, cellNodes);

  // ── Wires ─────────────────────────────────────────────────────────

  /// Routed edges with at least two points, in [NetlistLayout.edges] order —
  /// the ones there is anything to draw or click.
  List<EdgeRoute> get wires => _wires.routes;

  /// The axis-aligned bounds of [wires] entry [index]'s polyline.
  Rect wireBounds(int index) => _wires.bounds(index);

  /// Indices into [wires] whose bounds may overlap [rect], ascending, or
  /// `null` for all of them.
  List<int>? wiresIn(Rect rect) => _wires.grid.query(rect);

  /// Indices into [wires] that have a segment whose bounds may come within
  /// [slop] of [point], ascending, or `null` for all of them. Finer than
  /// [wiresIn]: an L-shaped wire's bounds cover a corner its segments never
  /// visit.
  List<int>? wiresNear(Offset point, double slop) {
    final segments = _segments.grid.query(around(point, slop));
    if (segments == null) return null;
    final owners = <int>[];
    for (final segment in segments) {
      final owner = _segments.owner[segment];
      // Segments are numbered wire by wire, so owners arrive ascending;
      // consecutive segments of one wire collapse here.
      if (owners.isEmpty || owners.last != owner) owners.add(owner);
    }
    return owners;
  }

  _Wires? _wiresOrNull;
  _Wires get _wires => _wiresOrNull ??= _Wires.build(laidOut);

  _Segments? _segmentsOrNull;
  _Segments get _segments => _segmentsOrNull ??= _Segments.build(_wires);

  // ── Keyboard navigation ───────────────────────────────────────────

  /// Placed cells and module ports in reading order — top to bottom, then
  /// left to right — exactly as the keyboard navigator has always sorted
  /// them.
  List<SelectedElement> get readingOrder => _reading.order;

  /// Where [element] first appears in [readingOrder], or -1.
  int readingIndexOf(SelectedElement element) =>
      _reading.firstIndex[element] ?? -1;

  _ReadingOrder? _readingOrNull;
  _ReadingOrder get _reading => _readingOrNull ??= _ReadingOrder.build(laidOut);

  /// The rectangle to query for a click at [point] against targets that
  /// count as hit within [slop]: the slop plus a margin, so floating-point
  /// rounding in a caller's exact test can never put a hit outside the
  /// candidates.
  static Rect around(Offset point, double slop) {
    final margin = slop.abs() + 1 + (point.dx.abs() + point.dy.abs()) * 1e-9;
    return Rect.fromLTRB(
      point.dx - margin,
      point.dy - margin,
      point.dx + margin,
      point.dy + margin,
    );
  }
}

/// The box arrays of every section, the only thing [SchematicSceneIndex.warm]
/// sends to the gridding isolate: typed data copies in one block, where the
/// graph's objects would be walked and rebuilt.
class _SceneArrays {
  const _SceneArrays({
    required this.cells,
    required this.boundary,
    required this.wires,
    required this.pins,
    required this.segments,
    required this.readingKeys,
  });

  final Float64List cells;
  final Float64List boundary;
  final Float64List wires;
  final Float64List pins;
  final Float64List segments;

  /// `y, x` per reading-order candidate.
  final Float64List readingKeys;

  int get boxCount =>
      (cells.length +
          boundary.length +
          wires.length +
          pins.length +
          segments.length) ~/
      4;
}

/// What the gridding isolate sends back: one grid per spatial section and
/// the reading-order permutation.
class _SceneGrids {
  const _SceneGrids({
    required this.cells,
    required this.boundary,
    required this.wires,
    required this.pins,
    required this.segments,
    required this.readingOrder,
  });

  final _GridArrays cells;
  final _GridArrays boundary;
  final _GridArrays wires;
  final _GridArrays pins;
  final _GridArrays segments;
  final Int32List readingOrder;
}

/// Grids every section of [arrays]. Pure: runs on any isolate.
_SceneGrids _buildSceneGrids(_SceneArrays arrays) => _SceneGrids(
  cells: _GridArrays.build(arrays.cells),
  boundary: _GridArrays.build(arrays.boundary),
  wires: _GridArrays.build(arrays.wires),
  pins: _GridArrays.build(arrays.pins),
  segments: _GridArrays.build(arrays.segments),
  readingOrder: _ReadingOrder.permutation(arrays.readingKeys),
);

/// Items of a scope that have a laid-out node, with their nodes and a grid
/// over the nodes' bounds.
class _Placed<T> {
  _Placed(this.items, this.nodes, this.grid);

  /// Collects and grids in one step, for a section built on first use.
  factory _Placed.build(List<T> all, NodePosition? Function(T item) nodeOf) {
    final collected = _Placed.collect(all, nodeOf);
    return _Placed(
      collected.items,
      collected.nodes,
      _Grid.build(collected.boxes),
    );
  }

  /// The items of [all] that have a node, their nodes, and the nodes' bounds
  /// as a flat box array.
  static ({List<T> items, List<NodePosition> nodes, Float64List boxes})
  collect<T>(List<T> all, NodePosition? Function(T item) nodeOf) {
    final items = <T>[];
    final nodes = <NodePosition>[];
    for (final item in all) {
      final node = nodeOf(item);
      if (node == null) continue;
      items.add(item);
      nodes.add(node);
    }
    final boxes = Float64List(nodes.length * 4);
    for (var i = 0; i < nodes.length; i++) {
      final b = nodes[i].bounds;
      // The same arithmetic the painter and hit-tester use, so the box is
      // exactly the rectangle their tests see.
      _putRect(boxes, i, Rect.fromLTWH(b.x, b.y, b.width, b.height));
    }
    return (items: items, nodes: nodes, boxes: boxes);
  }

  final List<T> items;
  final List<NodePosition> nodes;
  final _Grid grid;
}

class _Pins {
  _Pins(this.cell, this.port, this.box, this.grid);

  factory _Pins.build(List<SchematicCell> cells, List<NodePosition> nodes) {
    final collected = _Pins.collect(cells, nodes);
    return _Pins(
      collected.cell,
      collected.port,
      collected.box,
      _Grid.build(collected.boxes),
    );
  }

  /// Every pin with a box on its cell's node, and the boxes in design
  /// coordinates as a flat array.
  static ({
    Int32List cell,
    List<SchematicPort> port,
    List<BoundingBox> box,
    Float64List boxes,
  })
  collect(List<SchematicCell> cells, List<NodePosition> nodes) {
    final cell = <int>[];
    final port = <SchematicPort>[];
    final box = <BoundingBox>[];
    for (var c = 0; c < cells.length; c++) {
      final ports = nodes[c].ports;
      for (final pin in cells[c].ports) {
        final pinBox = ports[pin.id];
        if (pinBox == null) continue;
        cell.add(c);
        port.add(pin);
        box.add(pinBox);
      }
    }
    final boxes = Float64List(box.length * 4);
    for (var i = 0; i < box.length; i++) {
      final node = nodes[cell[i]].bounds;
      // Rect.fromLTWH's arithmetic, so the box is exactly the rectangle the
      // hit-test's exact check inflates.
      final left = node.x + box[i].x;
      final top = node.y + box[i].y;
      boxes
        ..[i * 4] = left
        ..[i * 4 + 1] = top
        ..[i * 4 + 2] = left + box[i].width
        ..[i * 4 + 3] = top + box[i].height;
    }
    return (
      cell: Int32List.fromList(cell),
      port: port,
      box: box,
      boxes: boxes,
    );
  }

  final Int32List cell;
  final List<SchematicPort> port;
  final List<BoundingBox> box;
  final _Grid grid;
}

class _Wires {
  _Wires(this.routes, this._bounds, this.grid);

  factory _Wires.build(LaidOutGraph laidOut) {
    final collected = _Wires.collect(laidOut);
    return _Wires(
      collected.routes,
      collected.bounds,
      _Grid.build(collected.bounds),
    );
  }

  /// The drawable routes and each one's polyline bounds as a flat array.
  static ({List<EdgeRoute> routes, Float64List bounds}) collect(
    LaidOutGraph laidOut,
  ) {
    final routes = <EdgeRoute>[
      for (final edge in laidOut.layout.edges)
        if (edge.points.length >= 2) edge,
    ];
    final bounds = Float64List(routes.length * 4);
    for (var i = 0; i < routes.length; i++) {
      final points = routes[i].points;
      // Exactly the painter's former per-frame bounds: seeded from the
      // first point, extended by comparison (so a NaN point is skipped,
      // and a NaN first point poisons the box, as it always did).
      var minX = points.first.x;
      var maxX = minX;
      var minY = points.first.y;
      var maxY = minY;
      for (final p in points) {
        if (p.x < minX) minX = p.x;
        if (p.x > maxX) maxX = p.x;
        if (p.y < minY) minY = p.y;
        if (p.y > maxY) maxY = p.y;
      }
      bounds
        ..[i * 4] = minX
        ..[i * 4 + 1] = minY
        ..[i * 4 + 2] = maxX
        ..[i * 4 + 3] = maxY;
    }
    return (routes: routes, bounds: bounds);
  }

  final List<EdgeRoute> routes;
  final Float64List _bounds;
  final _Grid grid;

  Rect bounds(int i) => Rect.fromLTRB(
    _bounds[i * 4],
    _bounds[i * 4 + 1],
    _bounds[i * 4 + 2],
    _bounds[i * 4 + 3],
  );
}

class _Segments {
  _Segments(this.owner, this.grid);

  factory _Segments.build(_Wires wires) {
    final collected = _Segments.collect(wires.routes);
    return _Segments(collected.owner, _Grid.build(collected.boxes));
  }

  /// Every segment of every route, numbered wire by wire: the wire each
  /// belongs to, and the segment boxes as a flat array.
  static ({Int32List owner, Float64List boxes}) collect(
    List<EdgeRoute> routes,
  ) {
    var count = 0;
    for (final route in routes) {
      count += route.points.length - 1;
    }
    final owner = Int32List(count);
    final boxes = Float64List(count * 4);
    var s = 0;
    for (var w = 0; w < routes.length; w++) {
      final points = routes[w].points;
      for (var i = 0; i + 1 < points.length; i++) {
        final a = points[i];
        final b = points[i + 1];
        owner[s] = w;
        boxes
          ..[s * 4] = math.min(a.x, b.x)
          ..[s * 4 + 1] = math.min(a.y, b.y)
          ..[s * 4 + 2] = math.max(a.x, b.x)
          ..[s * 4 + 3] = math.max(a.y, b.y);
        s++;
      }
    }
    return (owner: owner, boxes: boxes);
  }

  final Int32List owner;
  final _Grid grid;
}

class _ReadingOrder {
  _ReadingOrder(this.order, this.firstIndex);

  factory _ReadingOrder.build(LaidOutGraph laidOut) {
    final collected = _ReadingOrder.collect(laidOut);
    return _ReadingOrder.fromPermutation(
      collected.elements,
      _ReadingOrder.permutation(collected.keys),
    );
  }

  /// [elements] in the order [permutation] gives, with each element's first
  /// position.
  factory _ReadingOrder.fromPermutation(
    List<SelectedElement> elements,
    Int32List permutation,
  ) {
    final order = List<SelectedElement>.unmodifiable(<SelectedElement>[
      for (final i in permutation) elements[i],
    ]);
    final firstIndex = <SelectedElement, int>{};
    for (var i = 0; i < order.length; i++) {
      firstIndex.putIfAbsent(order[i], () => i);
    }
    return _ReadingOrder(order, firstIndex);
  }

  /// The placed cells, then the placed module ports, as the navigator has
  /// always gathered them, with each one's `y, x` sort key.
  static ({List<SelectedElement> elements, Float64List keys}) collect(
    LaidOutGraph laidOut,
  ) {
    final elements = <SelectedElement>[];
    final boxes = <BoundingBox>[];
    for (final cell in laidOut.graph.cells) {
      if (laidOut.layout.findNode(cell.id) case final node?) {
        elements.add(SelectedElement.cell(cellId: cell.id));
        boxes.add(node.bounds);
      }
    }
    for (final port in laidOut.graph.boundaryPorts) {
      if (laidOut.layout.findNode(port.id) case final node?) {
        elements.add(
          SelectedElement.boundaryPort(portId: port.id, portName: port.name),
        );
        boxes.add(node.bounds);
      }
    }
    final keys = Float64List(boxes.length * 2);
    for (var i = 0; i < boxes.length; i++) {
      keys
        ..[i * 2] = boxes[i].y
        ..[i * 2 + 1] = boxes[i].x;
    }
    return (elements: elements, keys: keys);
  }

  /// The indices of [keys]' entries sorted by row and then column: the same
  /// comparator, over the same input order, the navigator's former
  /// per-keypress sort applied to the elements themselves, so the order it
  /// yields is the same, ties included.
  static Int32List permutation(Float64List keys) {
    final order = List<int>.generate(keys.length ~/ 2, (i) => i)
      ..sort((a, b) {
        final byRow = keys[a * 2].compareTo(keys[b * 2]);
        return byRow != 0 ? byRow : keys[a * 2 + 1].compareTo(keys[b * 2 + 1]);
      });
    return Int32List.fromList(order);
  }

  final List<SelectedElement> order;
  final Map<SelectedElement, int> firstIndex;
}

void _putRect(Float64List boxes, int i, Rect r) {
  boxes
    ..[i * 4] = r.left
    ..[i * 4 + 1] = r.top
    ..[i * 4 + 2] = r.right
    ..[i * 4 + 3] = r.bottom;
}

/// The numbers a [_Grid] is made of: what gridding produces, on whichever
/// isolate it runs, and what the grid is then built from.
class _GridArrays {
  const _GridArrays({
    required this.count,
    required this.originX,
    required this.originY,
    required this.bucketW,
    required this.bucketH,
    required this.cols,
    required this.rows,
    required this.starts,
    required this.filed,
    required this.everywhere,
  });

  /// Grids the item boxes (`left, top, right, bottom` per item, in a flat
  /// list; either pair may be inverted).
  ///
  /// An item is filed in every bucket its box touches, so a query returns a
  /// superset of the items whose box meets the query rectangle — never a
  /// subset, which is what lets callers keep their exact tests and get
  /// identical answers. Items the grid does not file — a non-finite
  /// coordinate, or the widest boxes once filing them all would cost more
  /// than [_Grid._filingBudget] — are on a list every query returns.
  factory _GridArrays.build(Float64List boxes) {
    final count = boxes.length ~/ 4;
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;
    var finite = 0;
    for (var i = 0; i < count; i++) {
      if (!_Grid._isFinite(boxes, i)) continue;
      finite++;
      minX = math.min(minX, math.min(boxes[i * 4], boxes[i * 4 + 2]));
      maxX = math.max(maxX, math.max(boxes[i * 4], boxes[i * 4 + 2]));
      minY = math.min(minY, math.min(boxes[i * 4 + 1], boxes[i * 4 + 3]));
      maxY = math.max(maxY, math.max(boxes[i * 4 + 1], boxes[i * 4 + 3]));
    }
    final width = maxX - minX;
    final height = maxY - minY;
    if (finite == 0 || !width.isFinite || !height.isFinite) {
      // Nothing to file sensibly — every item is a candidate for every
      // query, which is the old full scan.
      return _GridArrays(
        count: count,
        originX: 0,
        originY: 0,
        bucketW: 1,
        bucketH: 1,
        cols: 1,
        rows: 1,
        starts: Int32List(2),
        filed: Int32List(0),
        everywhere: Int32List.fromList(List<int>.generate(count, (i) => i)),
      );
    }

    // About one item per bucket, shaped like the scope.
    final target = finite.clamp(1, _Grid._maxBuckets);
    final int cols;
    if (width <= 0) {
      cols = 1;
    } else if (height <= 0) {
      cols = target;
    } else {
      cols = math.sqrt(target * width / height).round().clamp(1, target);
    }
    final rows = (target / cols).ceil().clamp(1, _Grid._maxBuckets);
    final bucketW = width > 0 ? width / cols : 1.0;
    final bucketH = height > 0 ? height / rows : 1.0;

    // Pass 1: each item's bucket range. Every finite box lies inside the
    // extent, so the quotients are in [0, cols] / [0, rows].
    final span = Int32List(count * 4);
    final unfiled = <int>[];
    var filings = 0;
    for (var i = 0; i < count; i++) {
      if (!_Grid._isFinite(boxes, i)) {
        unfiled.add(i);
        span[i * 4] = -1;
        continue;
      }
      final c0 = _Grid._bucketOf(
        math.min(boxes[i * 4], boxes[i * 4 + 2]),
        minX,
        bucketW,
        cols,
      ).clamp(0, cols - 1);
      final c1 = _Grid._bucketOf(
        math.max(boxes[i * 4], boxes[i * 4 + 2]),
        minX,
        bucketW,
        cols,
      ).clamp(0, cols - 1);
      final r0 = _Grid._bucketOf(
        math.min(boxes[i * 4 + 1], boxes[i * 4 + 3]),
        minY,
        bucketH,
        rows,
      ).clamp(0, rows - 1);
      final r1 = _Grid._bucketOf(
        math.max(boxes[i * 4 + 1], boxes[i * 4 + 3]),
        minY,
        bucketH,
        rows,
      ).clamp(0, rows - 1);
      span
        ..[i * 4] = c0
        ..[i * 4 + 1] = c1
        ..[i * 4 + 2] = r0
        ..[i * 4 + 3] = r1;
      filings += (c1 - c0 + 1) * (r1 - r0 + 1);
    }
    int filingsOf(int i) =>
        (span[i * 4 + 1] - span[i * 4] + 1) *
        (span[i * 4 + 3] - span[i * 4 + 2] + 1);
    // A long diagonal wire's box covers a whole block of buckets. Filing
    // every such box could cost more memory than the scope itself, so the
    // widest are kept on the always-returned list instead, until the rest
    // fit the budget.
    final budget = _Grid._filingBudget(count);
    if (filings > budget) {
      final widest = <int>[
        for (var i = 0; i < count; i++)
          if (span[i * 4] >= 0) i,
      ]..sort((a, b) => filingsOf(b).compareTo(filingsOf(a)));
      for (final i in widest) {
        if (filings <= budget) break;
        filings -= filingsOf(i);
        span[i * 4] = -1;
        unfiled.add(i);
      }
    }

    // Pass 2 and 3: bucket sizes, then fill (CSR).
    final starts = Int32List(cols * rows + 1);
    for (var i = 0; i < count; i++) {
      if (span[i * 4] < 0) continue;
      for (var r = span[i * 4 + 2]; r <= span[i * 4 + 3]; r++) {
        for (var c = span[i * 4]; c <= span[i * 4 + 1]; c++) {
          starts[r * cols + c + 1]++;
        }
      }
    }
    for (var b = 1; b < starts.length; b++) {
      starts[b] += starts[b - 1];
    }
    final filed = Int32List(starts[starts.length - 1]);
    final cursor = Int32List.fromList(starts);
    for (var i = 0; i < count; i++) {
      if (span[i * 4] < 0) continue;
      for (var r = span[i * 4 + 2]; r <= span[i * 4 + 3]; r++) {
        for (var c = span[i * 4]; c <= span[i * 4 + 1]; c++) {
          filed[cursor[r * cols + c]++] = i;
        }
      }
    }
    return _GridArrays(
      count: count,
      originX: minX,
      originY: minY,
      bucketW: bucketW,
      bucketH: bucketH,
      cols: cols,
      rows: rows,
      starts: starts,
      filed: filed,
      everywhere: Int32List.fromList(unfiled..sort()),
    );
  }

  final int count;
  final double originX;
  final double originY;
  final double bucketW;
  final double bucketH;
  final int cols;
  final int rows;
  final Int32List starts;
  final Int32List filed;
  final Int32List everywhere;
}

/// A uniform bucket grid over item boxes; see [_GridArrays.build] for how
/// items are filed. Holds the per-query generation stamps beside the arrays,
/// which is why a grid is built on the isolate that queries it, from arrays
/// that may have been computed on another.
class _Grid {
  _Grid._({
    required this.count,
    required this.originX,
    required this.originY,
    required this.bucketW,
    required this.bucketH,
    required this.cols,
    required this.rows,
    required this.starts,
    required this.filed,
    required this.everywhere,
  }) : stamp = Int32List(count);

  factory _Grid.build(Float64List boxes) =>
      _Grid.fromArrays(_GridArrays.build(boxes));

  factory _Grid.fromArrays(_GridArrays arrays) => _Grid._(
    count: arrays.count,
    originX: arrays.originX,
    originY: arrays.originY,
    bucketW: arrays.bucketW,
    bucketH: arrays.bucketH,
    cols: arrays.cols,
    rows: arrays.rows,
    starts: arrays.starts,
    filed: arrays.filed,
    everywhere: arrays.everywhere,
  );

  /// Upper bound on buckets, whatever the item count.
  static const int _maxBuckets = 1 << 18;

  /// Most bucket filings a grid over [count] items keeps.
  static int _filingBudget(int count) => 8 * count + 65536;

  final int count;
  final double originX;
  final double originY;
  final double bucketW;
  final double bucketH;
  final int cols;
  final int rows;
  final Int32List starts;
  final Int32List filed;

  /// Items every query returns, ascending.
  final Int32List everywhere;

  /// Per-item query generation, so an item filed in several of the queried
  /// buckets is returned once without clearing a set per query.
  final Int32List stamp;
  int generation = 0;

  static bool _isFinite(Float64List boxes, int i) =>
      boxes[i * 4].isFinite &&
      boxes[i * 4 + 1].isFinite &&
      boxes[i * 4 + 2].isFinite &&
      boxes[i * 4 + 3].isFinite;

  /// The bucket along one axis holding the finite coordinate [v]: -1 when it
  /// is before the first bucket, [n] when past the last. Comparing the
  /// quotient before flooring keeps a coordinate far outside the grid from
  /// overflowing the integer conversion.
  static int _bucketOf(double v, double origin, double size, int n) {
    final q = (v - origin) / size;
    if (q < 0) return -1;
    if (q >= n) return n;
    return q.floor();
  }

  /// Items whose box may meet [rect] (closed), ascending; `null` when
  /// [rect] covers so much of the grid that walking every item is cheaper,
  /// or cannot be placed on it at all.
  List<int>? query(Rect rect) {
    if (count == 0) return const <int>[];
    final left = rect.left;
    final top = rect.top;
    final right = rect.right;
    final bottom = rect.bottom;
    if (!left.isFinite ||
        !top.isFinite ||
        !right.isFinite ||
        !bottom.isFinite ||
        left > right ||
        top > bottom) {
      return null;
    }
    final c0 = _bucketOf(left, originX, bucketW, cols);
    final c1 = _bucketOf(right, originX, bucketW, cols);
    final r0 = _bucketOf(top, originY, bucketH, rows);
    final r1 = _bucketOf(bottom, originY, bucketH, rows);
    if (c1 < 0 || c0 >= cols || r1 < 0 || r0 >= rows) {
      return List<int>.of(everywhere);
    }
    final cs = math.max(c0, 0);
    final ce = math.min(c1, cols - 1);
    final rs = math.max(r0, 0);
    final re = math.min(r1, rows - 1);
    if ((ce - cs + 1) * (re - rs + 1) * 4 > cols * rows) return null;
    if (++generation == 0x7fffffff) {
      stamp.fillRange(0, stamp.length, 0);
      generation = 1;
    }
    final current = generation;
    final hits = <int>[];
    for (var r = rs; r <= re; r++) {
      final rowBase = r * cols;
      for (var b = rowBase + cs; b <= rowBase + ce; b++) {
        for (var k = starts[b]; k < starts[b + 1]; k++) {
          final i = filed[k];
          if (stamp[i] == current) continue;
          stamp[i] = current;
          hits.add(i);
        }
      }
    }
    hits.sort();
    if (everywhere.isEmpty) return hits;
    // Merge the two ascending lists; an item is filed or on the list, never
    // both.
    final merged = <int>[];
    var a = 0;
    var b = 0;
    while (a < hits.length || b < everywhere.length) {
      if (b >= everywhere.length ||
          (a < hits.length && hits[a] < everywhere[b])) {
        merged.add(hits[a++]);
      } else {
        merged.add(everywhere[b++]);
      }
    }
    return merged;
  }
}
