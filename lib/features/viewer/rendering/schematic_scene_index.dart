// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset, Rect;

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
/// per graph — on first use, one section at a time — and every later frame,
/// click and keypress reads it. Before this existed, each of those scanned
/// the whole scope: on a 100,000-cell design a frame spent ~15 ms walking
/// cells and edges it then culled, a click ~34 ms, and a keyboard step
/// ~55 ms re-sorting every element into reading order.
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

  /// The scope this indexes.
  final LaidOutGraph laidOut;

  // ── Cells ─────────────────────────────────────────────────────────

  /// Cells that have a laid-out node, in [SchematicGraph.cells] order.
  List<SchematicCell> get cells => _cells.items;

  /// The node of each entry in [cells], by the same index.
  List<NodePosition> get cellNodes => _cells.nodes;

  /// Indices into [cells] whose body may overlap [rect], ascending, or
  /// `null` for all of them.
  List<int>? cellsIn(Rect rect) => _cells.grid.query(rect);

  late final _Placed<SchematicCell> _cells = _Placed<SchematicCell>(
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

  late final _Placed<SchematicBoundaryPort> _boundary =
      _Placed<SchematicBoundaryPort>(
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

  late final _Pins _pins = _Pins.build(this);

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

  late final _Wires _wires = _Wires.build(laidOut);
  late final _Segments _segments = _Segments.build(_wires);

  // ── Keyboard navigation ───────────────────────────────────────────

  /// Placed cells and module ports in reading order — top to bottom, then
  /// left to right — exactly as the keyboard navigator has always sorted
  /// them.
  List<SelectedElement> get readingOrder => _reading.order;

  /// Where [element] first appears in [readingOrder], or -1.
  int readingIndexOf(SelectedElement element) =>
      _reading.firstIndex[element] ?? -1;

  late final _ReadingOrder _reading = _ReadingOrder.build(laidOut);

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

/// Items of a scope that have a laid-out node, with their nodes and a grid
/// over the nodes' bounds.
class _Placed<T> {
  factory _Placed(List<T> all, NodePosition? Function(T item) nodeOf) {
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
    return _Placed._(items, nodes, _Grid.build(boxes));
  }

  _Placed._(this.items, this.nodes, this.grid);

  final List<T> items;
  final List<NodePosition> nodes;
  final _Grid grid;
}

class _Pins {
  _Pins(this.cell, this.port, this.box, this.grid);

  factory _Pins.build(SchematicSceneIndex index) {
    final cells = index.cells;
    final nodes = index.cellNodes;
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
    return _Pins(Int32List.fromList(cell), port, box, _Grid.build(boxes));
  }

  final Int32List cell;
  final List<SchematicPort> port;
  final List<BoundingBox> box;
  final _Grid grid;
}

class _Wires {
  _Wires(this.routes, this._bounds, this.grid);

  factory _Wires.build(LaidOutGraph laidOut) {
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
    return _Wires(routes, bounds, _Grid.build(bounds));
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
    var count = 0;
    for (final route in wires.routes) {
      count += route.points.length - 1;
    }
    final owner = Int32List(count);
    final boxes = Float64List(count * 4);
    var s = 0;
    for (var w = 0; w < wires.routes.length; w++) {
      final points = wires.routes[w].points;
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
    return _Segments(owner, _Grid.build(boxes));
  }

  final Int32List owner;
  final _Grid grid;
}

class _ReadingOrder {
  _ReadingOrder(this.order, this.firstIndex);

  factory _ReadingOrder.build(LaidOutGraph laidOut) {
    // Verbatim the navigator's former per-keypress construction, now run
    // once: the same input order through the same comparator gives the same
    // order, ties included.
    final placed =
        <(BoundingBox, SelectedElement)>[
          for (final cell in laidOut.graph.cells)
            if (laidOut.layout.findNode(cell.id) case final node?)
              (node.bounds, SelectedElement.cell(cellId: cell.id)),
          for (final port in laidOut.graph.boundaryPorts)
            if (laidOut.layout.findNode(port.id) case final node?)
              (
                node.bounds,
                SelectedElement.boundaryPort(
                  portId: port.id,
                  portName: port.name,
                ),
              ),
        ]..sort((a, b) {
          final byRow = a.$1.y.compareTo(b.$1.y);
          return byRow != 0 ? byRow : a.$1.x.compareTo(b.$1.x);
        });
    final order = List<SelectedElement>.unmodifiable(<SelectedElement>[
      for (final (_, element) in placed) element,
    ]);
    final firstIndex = <SelectedElement, int>{};
    for (var i = 0; i < order.length; i++) {
      firstIndex.putIfAbsent(order[i], () => i);
    }
    return _ReadingOrder(order, firstIndex);
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

/// A uniform bucket grid over item boxes (`left, top, right, bottom` per
/// item, in a flat list; either pair may be inverted).
///
/// An item is filed in every bucket its box touches, so a query returns a
/// superset of the items whose box meets the query rectangle — never a
/// subset, which is what lets callers keep their exact tests and get
/// identical answers. Items the grid does not file — a non-finite
/// coordinate, or the widest boxes once filing them all would cost more
/// than [_filingBudget] — are on a list every query returns.
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

  factory _Grid.build(Float64List boxes) {
    final count = boxes.length ~/ 4;
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;
    var finite = 0;
    for (var i = 0; i < count; i++) {
      if (!_isFinite(boxes, i)) continue;
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
      return _Grid._(
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
    final target = finite.clamp(1, _maxBuckets);
    final int cols;
    if (width <= 0) {
      cols = 1;
    } else if (height <= 0) {
      cols = target;
    } else {
      cols = math.sqrt(target * width / height).round().clamp(1, target);
    }
    final rows = (target / cols).ceil().clamp(1, _maxBuckets);
    final bucketW = width > 0 ? width / cols : 1.0;
    final bucketH = height > 0 ? height / rows : 1.0;

    // Pass 1: each item's bucket range. Every finite box lies inside the
    // extent, so the quotients are in [0, cols] / [0, rows].
    final span = Int32List(count * 4);
    final unfiled = <int>[];
    var filings = 0;
    for (var i = 0; i < count; i++) {
      if (!_isFinite(boxes, i)) {
        unfiled.add(i);
        span[i * 4] = -1;
        continue;
      }
      final c0 = _bucketOf(
        math.min(boxes[i * 4], boxes[i * 4 + 2]),
        minX,
        bucketW,
        cols,
      ).clamp(0, cols - 1);
      final c1 = _bucketOf(
        math.max(boxes[i * 4], boxes[i * 4 + 2]),
        minX,
        bucketW,
        cols,
      ).clamp(0, cols - 1);
      final r0 = _bucketOf(
        math.min(boxes[i * 4 + 1], boxes[i * 4 + 3]),
        minY,
        bucketH,
        rows,
      ).clamp(0, rows - 1);
      final r1 = _bucketOf(
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
    final budget = _filingBudget(count);
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
    return _Grid._(
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
