// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:flutter/services.dart' show rootBundle;
import 'package:meta/meta.dart';
import 'package:netcrux/domain/models/custom_cell_symbol/cell_symbol_geometry.dart';
import 'package:netcrux/domain/models/custom_cell_symbol/port_anchor.dart';
import 'package:netcrux/domain/models/layout/netlist_layout.dart';
import 'package:netcrux/domain/models/netlist/module.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/netlist/port_direction.dart';
import 'package:netcrux/domain/models/schematic/boundary_port_label.dart';
import 'package:netcrux/domain/models/schematic/symbol_shapes.dart';
// Conditional import: the desktop worker's solver factory picks the native
// elkrs engine, or elkjs on a JavaScript engine when kept by environment or
// when the native library cannot start. Web never reaches it.
import 'package:netcrux/services/layout/elk_solver_stub.dart'
    if (dart.library.io) 'package:netcrux/services/layout/elk_solver_io.dart';
// Conditional import: on web the solve runs in the browser, the elkrs port
// as WebAssembly in a Web Worker (no flutter_js, no isolate). Off web
// `kElkWebSolverAvailable` is false and the isolate path is used.
import 'package:netcrux/services/layout/elk_web_solver_stub.dart'
    if (dart.library.js_interop) 'package:netcrux/services/layout/elk_web_solver_web.dart';
import 'package:netcrux/services/schematic/net_edge_enumeration.dart';

/// Narrow seam over [JavascriptRuntime] — exposing only what
/// [ElkLayoutService] actually needs. Implementing a full
/// [JavascriptRuntime] surface in tests is brittle; this interface keeps
/// the test fake to four members.
abstract class ElkJsHost {
  /// Synchronously evaluates [code] and returns the stringified result.
  String evaluate(String code);

  /// Advances one pending Promise / microtask job. Returns the number of
  /// jobs the engine had after this call (0 = idle).
  int executePendingJob();

  /// Releases the underlying engine. Subsequent calls are no-ops.
  void dispose();
}

/// One layout engine behind the worker: ELK JSON in, laid-out ELK JSON out.
///
/// Two implementations share the contract. `NativeElkSolver` calls the
/// vendored elkrs port through `native/elk_ffi` and is the desktop default;
/// [JsElkSolver] drives the vendored elkjs bundle on a JavaScript engine and
/// stays as the escape hatch and the parity reference. The service, the
/// caches and the renderer never learn which one answered.
abstract class ElkSolver {
  /// Lays out [inputJson] and returns the result document. Throws
  /// [LayoutException] when the engine rejects the input.
  String solve(String inputJson);

  /// A short name for the stderr announcement and diagnostics, such as
  /// `native (elkrs 0.1.1)`.
  String get engineDescription;

  /// Releases the engine. Subsequent calls are no-ops.
  void dispose();
}

/// [ElkSolver] over an initialised [ElkJsHost]: the elkjs path.
class JsElkSolver implements ElkSolver {
  /// Wraps [host], which must already have run [initElkRuntime].
  JsElkSolver(this._host);

  final ElkJsHost _host;

  @override
  String get engineDescription => 'elkjs';

  @override
  String solve(String inputJson) => runElkLayoutOnHost(_host, inputJson);

  @override
  void dispose() => _host.dispose();
}

/// Thrown by [ElkLayoutService] when the layout pipeline fails — either
/// the elkjs bundle cannot be loaded, the JS runtime is unavailable on
/// the host, or elk itself rejected the input. Carries a short message
/// suitable for snackbar display and retains the underlying cause for
/// the diagnostics panel.
class LayoutException implements Exception {
  /// Creates a layout exception.
  const LayoutException(this.message, {this.cause});

  /// One-line user-facing message.
  final String message;

  /// Underlying error (if any) — JS evaluation error, asset load error,
  /// parse error.
  final Object? cause;

  @override
  String toString() => cause == null
      ? 'LayoutException: $message'
      : 'LayoutException: $message (cause: $cause)';
}

/// Thrown by [ElkLayoutService.layout] when the solve was abandoned through
/// [ElkLayoutService.cancelInFlightLayout]: the user stopped it, or moved on
/// to another scope or view. Not a failure; nothing went wrong with the
/// input.
class LayoutCancelledException extends LayoutException {
  /// Creates the cancel signal.
  const LayoutCancelledException() : super('layout cancelled');
}

/// The ELK Layered phase a running layout is in, in the order they run.
enum LayoutPhase {
  /// Reversing a few edges so that every cycle can be drawn one way.
  cycleBreaking,

  /// Assigning each node to a layer (a column, for a left-to-right
  /// schematic).
  layering,

  /// Ordering the nodes in each layer so fewer edges cross; usually the
  /// longest phase.
  crossingMinimization,

  /// Giving every node its final coordinates.
  nodePlacement,

  /// Routing the edges between the placed nodes.
  edgeRouting;

  /// The phase for an `elk_ffi` / `elk_wasm` progress code (1 to 5), or
  /// `null` for 0 (no report yet) or a code this build does not know.
  static LayoutPhase? fromCode(int code) =>
      code >= 1 && code <= values.length ? values[code - 1] : null;

  /// The phase for an elkrs phase name (`Phase::name`, e.g. `"node
  /// placement"`), or `null` for a name this build does not know.
  static LayoutPhase? fromName(String name) => switch (name) {
    'cycle breaking' => cycleBreaking,
    'layering' => layering,
    'crossing minimization' => crossingMinimization,
    'node placement' => nodePlacement,
    'edge routing' => edgeRouting,
    _ => null,
  };
}

/// How far a running layout has got, as the engine reports it.
@immutable
class LayoutProgress {
  /// Creates a progress report.
  const LayoutProgress({required this.phase, this.fraction});

  /// The phase about to run or running.
  final LayoutPhase phase;

  /// The share of the layout done, in [0, 1), or `null` when the engine
  /// does not know it.
  final double? fraction;

  @override
  bool operator ==(Object other) =>
      other is LayoutProgress &&
      other.phase == phase &&
      other.fraction == fraction;

  @override
  int get hashCode => Object.hash(phase, fraction);

  @override
  String toString() => 'LayoutProgress(${phase.name}, $fraction)';
}

/// A solve running off the calling thread, started by [ElkJobSolver.start]:
/// the caller polls it, may cancel it, and collects the result with
/// [finish].
abstract class ElkSolveJob {
  /// Whether the result is ready, and the latest progress (`null` before
  /// the engine's first report).
  ({bool done, LayoutProgress? progress}) poll();

  /// Asks the engine to stop at its next check. [finish] then throws
  /// [LayoutCancelledException]. A no-op once the job is done.
  void cancel();

  /// The laid-out document, once [poll] has reported the job done. Throws
  /// [LayoutCancelledException] for a cancelled job and [LayoutException]
  /// when the engine rejected the input. Releases the job.
  String finish();
}

/// An [ElkSolver] that can also run a solve in the background, with
/// progress reports and a cooperative cancel: the native engine. elkjs
/// cannot, so its worker is killed to cancel it.
abstract class ElkJobSolver implements ElkSolver {
  /// Starts laying out [inputJson] and returns at once.
  ElkSolveJob start(String inputJson);
}

/// Polls [job] until it is done, passing each new progress report to
/// [onProgress], and returns its result (see [ElkSolveJob.finish]).
///
/// The poll interval starts at a millisecond and doubles up to
/// [maxInterval], so the result is collected within [maxInterval] of the
/// engine finishing (a poll is an FFI call that reads two atomics, so
/// polling often costs nothing a user could measure, while a coarse
/// interval would add its own length to every layout).
Future<String> driveElkSolveJob(
  ElkSolveJob job, {
  void Function(LayoutProgress progress)? onProgress,
  Duration maxInterval = const Duration(milliseconds: 8),
}) async {
  var interval = const Duration(milliseconds: 1);
  LayoutProgress? last;
  while (true) {
    final (:done, :progress) = job.poll();
    if (progress != null && progress != last) {
      last = progress;
      onProgress?.call(progress);
    }
    if (done) return job.finish();
    await Future<void>.delayed(interval);
    if (interval < maxInterval) {
      interval *= 2;
      if (interval > maxInterval) interval = maxInterval;
    }
  }
}

/// Pluggable persistent store for solved layouts, keyed by a stable content
/// hash of the ELK input, so a re-opened design skips the multi-second elkjs
/// solve. Implemented per-platform — `dart:io` files on desktop, a no-op on
/// web (which renders pre-laid-out netlists and never solves). The value is
/// the raw elkjs result JSON string. All methods are best-effort: `read`
/// returns null on miss/error, `write` silently drops on error.
abstract interface class LayoutDiskCache {
  /// Returns the cached layout-result JSON for [key], or null on miss.
  Future<String?> read(String key);

  /// Stores [value] (the layout-result JSON) under [key].
  Future<void> write(String key, String value);
}

/// The most edges a net may have and still be routed by the layout; a net
/// with more is drawn as an implied global net (clock, reset, enables).
const int highFanoutEdgeCap = 32;

/// The part of a scope a cone view lays out: the cells, boundary ports and
/// wires [buildElkInput] keeps, by the ids the whole scope gives them.
@immutable
class ElkSubgraph {
  /// Creates a sub-graph selection.
  const ElkSubgraph({
    required this.cellIds,
    required this.boundaryPortIds,
    required this.edgeIds,
  });

  /// The cells kept, by cell name.
  final Set<String> cellIds;

  /// The boundary ports kept, by `port:<name>` id.
  final Set<String> boundaryPortIds;

  /// The wires kept, by `netEdgeId` id.
  final Set<String> edgeIds;
}

/// Builds the ELK-compatible input JSON for a single module out of a
/// [NetlistModel]. Pure function — exposed at the top level so it can be
/// unit-tested without spinning up a JS runtime.
///
/// Each Yosys [Cell] becomes one ELK node; each module [Port] also
/// becomes a node sitting on the boundary. Each Yosys [Net] (or each
/// connection between a cell port and another cell port / module port)
/// becomes one ELK edge. Bit-level granularity is collapsed to net-level
/// — no bit-fanout / bit-merge cells are drawn.
///
/// A cell whose `type` has an entry in [symbols] is drawn with a custom
/// symbol, and its node takes that symbol's shape instead of the built-in
/// one (see [symbolCellNodeSize] and [symbolPortCentres]). With no
/// [symbols] the input is exactly what it was before symbols existed.
///
/// With [only], the input holds just that part of the scope: the cells,
/// boundary ports and wires it names, each built exactly as for the whole
/// scope and under the same id. A net too wide to route in the whole scope
/// stays unrouted in the part, so a cone view draws a global net the way
/// the whole scope does. With no [only] the input is the whole scope's,
/// byte for byte, so the cached layouts of whole scopes keep their keys.
Map<String, Object?> buildElkInput(
  Module module, {
  CellSymbolGeometries symbols = CellSymbolGeometries.none,
  ElkSubgraph? only,
}) {
  final children = <Map<String, Object?>>[];
  final edges = <Map<String, Object?>>[];
  var cellCount = 0;

  final netEdges = enumerateNetEdges(module);

  // Module ports become nodes on the boundary so ELK can route edges to
  // them as endpoints. Each carries its name as a sized label outside the
  // box, on the side its wire does not use (see [BoundaryPortLabel]), so
  // ELK leaves room for the name: a neighbouring port or cell is never placed
  // over it, and the name never lies over the port's own wire.
  final drivingPorts = <String>{
    for (final group in netEdges)
      for (final edge in group.edges)
        if (edge.sourcePortId.startsWith('port:')) edge.sourcePortId,
  };
  for (final entry in module.ports.entries) {
    final port = entry.value;
    final id = 'port:${port.name}';
    if (only != null && !only.boundaryPortIds.contains(id)) continue;
    final west = BoundaryPortLabel.onWest(
      direction: port.direction,
      drivesWire: drivingPorts.contains(id),
    );
    children.add(<String, Object?>{
      'id': id,
      'width': 16,
      'height': 16,
      // Whole numbers, written as integers: a double prints as `21.0` on
      // desktop and `21` in the browser, and the input must be the same text
      // on both (its hash keys the layout caches and the parity references).
      'labels': <Map<String, Object?>>[
        <String, Object?>{
          'text': port.name,
          'width': BoundaryPortLabel.widthFor(port.name).ceil(),
          'height': BoundaryPortLabel.height.ceil(),
        },
      ],
      'layoutOptions': <String, Object?>{
        'elk.nodeLabels.placement': west
            ? '[OUTSIDE, H_LEFT, V_CENTER]'
            : '[OUTSIDE, H_RIGHT, V_CENTER]',
        'elk.spacing.labelNode':
            '${SchematicDetailMarks.boundaryLabelGap.ceil()}',
      },
    });
  }

  // Cells become inner nodes. Each cell's connections list expands into
  // ELK ports beneath the node.
  //
  // Every cell fixes its port sides (`FIXED_SIDE`): inputs on the west
  // face, outputs on the east. Left FREE, ELK places a port wherever its
  // edges pull it, so a feedback edge or an unconnected pin could put both
  // pins of a LUT on one face. The order of ports along a face stays
  // ELK's choice, which keeps crossings low. Both engines read these as
  // `layoutOptions`; an element carries no `properties` map beside them,
  // because the importer reads only one of the two.
  for (final entry in module.cells.entries) {
    final cell = entry.value;
    if (only != null && !only.cellIds.contains(cell.name)) continue;
    cellCount++;
    // A cell drawn with a custom symbol gets a node of the drawing's shape
    // with its pins at the anchors; every other cell keeps the built-in
    // geometry below, byte for byte.
    final geometry = symbols[cell.type];
    if (geometry != null) {
      children.add(_symbolCellNode(cell, geometry));
      continue;
    }
    final ports = <Map<String, Object?>>[
      for (final portName in cell.connections.keys)
        <String, Object?>{
          'id': '${cell.name}:$portName',
          'width': 4,
          'height': 4,
          'layoutOptions': <String, Object?>{
            'elk.port.side': elkPortSideFor(cell.portDirections[portName]),
          },
        },
    ];
    children.add(<String, Object?>{
      'id': cell.name,
      'width': 80,
      'height': 32 + (ports.length * 10),
      'labels': <Map<String, Object?>>[
        <String, Object?>{'text': '${cell.name}\\n(${cell.type})'},
      ],
      'ports': ports,
      'layoutOptions': const <String, Object?>{
        'elk.portConstraints': 'FIXED_SIDE',
      },
    });
  }

  // Route only "datapath" nets as point-to-point edges, skipping
  // high-fanout global nets (clock, reset, enable — which drive every
  // flop). A net with more than [highFanoutEdgeCap] edges is treated as
  // global and left un-routed in the layout.
  //
  // Why: a single high-fanout net (clk → ~1 600 flops) expands to ~1 600
  // point-to-point edges, and ELK's layered algorithm inserts a dummy
  // routing node for every layer each edge crosses — which ballooned
  // picorv32 to ~21 000 edges, a 13 000 × 63 000 px layout, and a ~7 s
  // solve. Schematic tools don't route clock/reset anyway (they're shown
  // as implied global nets), so skipping them keeps the datapath
  // connectivity that actually drives a readable, compact layout. Edges
  // stay 'simple' (1 source → 1 target) as ELK's layered algorithm
  // requires — it rejects multi-endpoint hyperedges.
  //
  // The edges come from the enumeration the schematic graph is built
  // from, with their ids unchanged: a skipped net renumbers nothing, so a
  // routed edge's id names the same wire in the graph.
  for (final group in netEdges) {
    if (group.edges.length > highFanoutEdgeCap) continue;
    for (final edge in group.edges) {
      if (only != null && !only.edgeIds.contains(edge.id)) continue;
      edges.add(<String, Object?>{
        'id': edge.id,
        'sources': <String>[edge.sourcePortId],
        'targets': <String>[edge.targetPortId],
      });
    }
  }

  // For a large dense scope the layered solve dominates wall-time —
  // picorv32's 1 599-cell core is ~4.5 s in QuickJS-interpreted elkjs. Two
  // knobs roughly halve it with comparable layout quality:
  //  * `thoroughness: 1` — a single crossing-minimization pass instead of
  //    the default multi-pass search.
  //  * `cycleBreaking: DEPTH_FIRST` — cheaper than the default greedy
  //    minimal-reversal search, which is costly on the many feedback loops a
  //    register-heavy netlist has (every flop's Q→D is a cycle).
  // Measured on picorv32: 4.5 s → ~2 s, bounds comparable. Gated to large
  // scopes only — small modules are already instant and keep the
  // higher-quality defaults (DEPTH_FIRST can reverse a few more edges, very
  // slightly hurting the left-to-right signal-flow reading you'd want when
  // studying a small datapath up close).
  const largeScopeCellThreshold = 500;
  final layoutOptions = <String, Object?>{
    'elk.algorithm': 'layered',
    'elk.direction': 'RIGHT',
    'elk.spacing.nodeNode': '20',
    'elk.layered.spacing.nodeNodeBetweenLayers': '30',
    if (cellCount > largeScopeCellThreshold) ...<String, Object?>{
      'elk.layered.thoroughness': '1',
      'elk.layered.cycleBreaking.strategy': 'DEPTH_FIRST',
    },
  };
  return <String, Object?>{
    'id': 'root',
    'layoutOptions': layoutOptions,
    'children': children,
    'edges': edges,
  };
}

/// The ELK `port.side` of a cell pin with [direction]: `WEST` for an input,
/// `EAST` for an output or inout.
///
/// A pin with no recorded direction is an input, the same fallback
/// `SchematicGraphBuilder` uses, so the face ELK puts it on agrees with the
/// pin the canvas draws and with the edges, which treat it as a sink.
@visibleForTesting
String elkPortSideFor(PortDirection? direction) {
  switch (direction) {
    case PortDirection.input:
    case null:
      return 'WEST';
    case PortDirection.output:
    case PortDirection.inout:
      return 'EAST';
  }
}

/// The spacing between two pins on one face of a symbol-bearing node, in
/// layout units: the ten per pin a built-in node's height allows.
const double symbolPinPitch = 10;

/// The ELK node for [cell], drawn with the custom symbol [geometry]: sized
/// by [symbolCellNodeSize], with `FIXED_POS` ports at [symbolPortCentres],
/// so the drawing fills the node and each anchored pin sits on the face and
/// at the place its anchor names.
Map<String, Object?> _symbolCellNode(Cell cell, CellSymbolGeometry geometry) {
  final faces = symbolPortFaces(cell, geometry);
  final size = symbolCellNodeSize(faces.values, geometry.aspect);
  final centres = symbolPortCentres(cell, geometry, faces, size);
  const portSize = 4.0;
  const half = portSize / 2;
  final ports = <Map<String, Object?>>[
    for (final portName in cell.connections.keys)
      () {
        // Both maps are built over these same `connections` keys, so every
        // port has a face and a centre.
        final side = faces[portName]!;
        final c = centres[portName]!;
        final (x, y) = switch (side) {
          'WEST' => (-portSize, c - half),
          'EAST' => (size.width, c - half),
          'NORTH' => (c - half, -portSize),
          _ => (c - half, size.height),
        };
        return <String, Object?>{
          'id': '${cell.name}:$portName',
          'width': portSize,
          'height': portSize,
          'x': _round2(x),
          'y': _round2(y),
          'layoutOptions': <String, Object?>{'elk.port.side': side},
        };
      }(),
  ];
  return <String, Object?>{
    'id': cell.name,
    'width': size.width,
    'height': size.height,
    'labels': <Map<String, Object?>>[
      <String, Object?>{'text': '${cell.name}\\n(${cell.type})'},
    ],
    'ports': ports,
    'layoutOptions': const <String, Object?>{
      'elk.portConstraints': 'FIXED_POS',
    },
  };
}

double _round2(double value) => (value * 100).roundToDouble() / 100;

/// The ELK face (`WEST`, `EAST`, `NORTH` or `SOUTH`) of each pin of [cell]
/// under the symbol [geometry], by port name in `connections` order.
///
/// A pin whose name equals an anchor's port name goes on the anchor's side.
/// Any other pin keeps the face its direction gives it ([elkPortSideFor]).
/// Anchors that name no pin of the cell are ignored.
@visibleForTesting
Map<String, String> symbolPortFaces(Cell cell, CellSymbolGeometry geometry) {
  return <String, String>{
    for (final portName in cell.connections.keys)
      portName: switch (geometry.anchors[portName]?.side) {
        PortAnchorSide.left => 'WEST',
        PortAnchorSide.right => 'EAST',
        PortAnchorSide.top => 'NORTH',
        PortAnchorSide.bottom => 'SOUTH',
        null => elkPortSideFor(cell.portDirections[portName]),
      },
  };
}

/// The node size of a symbol-bearing cell whose pins sit on [faces], for a
/// drawing of [aspect] (width over height).
///
/// Each face must hold its pins at [symbolPinPitch] with the same margin a
/// built-in node keeps: the west and east faces need a height of
/// `32 + 10 × pins` for the busier of the two, the north and south faces
/// the same in width. The node is the smallest rectangle of the drawing's
/// aspect that meets both, rounded to hundredths.
@visibleForTesting
({double width, double height}) symbolCellNodeSize(
  Iterable<String> faces,
  double aspect,
) {
  var west = 0;
  var east = 0;
  var north = 0;
  var south = 0;
  for (final face in faces) {
    switch (face) {
      case 'WEST':
        west++;
      case 'EAST':
        east++;
      case 'NORTH':
        north++;
      default:
        south++;
    }
  }
  final minHeight = 32 + symbolPinPitch * math.max(west, east);
  final minWidth = 32 + symbolPinPitch * math.max(north, south);
  final height = math.max(minHeight, minWidth / aspect);
  return (width: _round2(height * aspect), height: _round2(height));
}

/// Where each pin of [cell] sits along its face, measured from the face's
/// top (west and east) or left (north and south) end, in layout units.
///
/// An anchored pin asks for its anchor's position along the face (`y` on
/// the west and east faces, `x` on the north and south), scaled to the
/// face. Unanchored pins on a face ask for even spacing among themselves.
/// [spreadAlongFace] then keeps every pin at least [symbolPinPitch] from
/// its neighbours and clear of the corners, moving pins that ask for the
/// same place apart around it in declaration order.
@visibleForTesting
Map<String, double> symbolPortCentres(
  Cell cell,
  CellSymbolGeometry geometry,
  Map<String, String> faces,
  ({double width, double height}) size,
) {
  final result = <String, double>{};
  for (final face in const <String>['WEST', 'EAST', 'NORTH', 'SOUTH']) {
    final names = <String>[
      for (final entry in faces.entries)
        if (entry.value == face) entry.key,
    ];
    if (names.isEmpty) continue;
    final vertical = face == 'WEST' || face == 'EAST';
    final length = vertical ? size.height : size.width;
    final unanchored = <String>[
      for (final name in names)
        if (geometry.anchors[name] == null) name,
    ];
    final desired = <double>[
      for (final name in names)
        () {
          final anchor = geometry.anchors[name];
          final fraction = anchor == null
              ? (unanchored.indexOf(name) + 1) / (unanchored.length + 1)
              : (vertical ? anchor.y : anchor.x).clamp(0.0, 1.0);
          return fraction * length;
        }(),
    ];
    final placed = spreadAlongFace(desired, length, symbolPinPitch);
    for (var i = 0; i < names.length; i++) {
      result[names[i]] = placed[i];
    }
  }
  return result;
}

/// Moves the points [desired] along a segment of [length] as little as
/// possible so that no two are closer than [pitch] and none is nearer an
/// end than half a pitch, keeping their order (ties in input order).
///
/// Points that crowd together are spread evenly around their mean, then the
/// group is slid back inside the segment. When they cannot fit at [pitch]
/// at all, they are spaced evenly along the whole segment instead.
@visibleForTesting
List<double> spreadAlongFace(
  List<double> desired,
  double length,
  double pitch,
) {
  final n = desired.length;
  if (n == 0) return const <double>[];
  final low = math.min(pitch / 2, length / 2);
  final high = length - low;
  final order = List<int>.generate(n, (i) => i)
    ..sort((a, b) {
      final byPosition = desired[a].compareTo(desired[b]);
      return byPosition != 0 ? byPosition : a.compareTo(b);
    });
  final placed = List<double>.filled(n, 0);
  if (pitch * (n - 1) > high - low) {
    for (var k = 0; k < n; k++) {
      placed[order[k]] = length * (k + 1) / (n + 1);
    }
    return placed;
  }
  // Each group: how many points, and the sum of where they asked to be.
  final counts = <int>[];
  final sums = <double>[];
  double first(int g) {
    final span = pitch * (counts[g] - 1);
    final start = sums[g] / counts[g] - span / 2;
    return start.clamp(low, high - span);
  }

  for (final i in order) {
    counts.add(1);
    sums.add(desired[i].clamp(low, high));
    while (counts.length > 1) {
      final last = counts.length - 1;
      final previousEnd = first(last - 1) + pitch * counts[last - 1];
      if (previousEnd <= first(last) + 1e-9) break;
      counts[last - 1] += counts[last];
      sums[last - 1] += sums[last];
      counts.removeLast();
      sums.removeLast();
    }
  }
  var k = 0;
  for (var g = 0; g < counts.length; g++) {
    final start = first(g);
    for (var j = 0; j < counts[g]; j++) {
      placed[order[k++]] = start + pitch * j;
    }
  }
  return placed;
}

/// The cells of [module] drawn with a custom symbol, by cell name, each with
/// the names of its pins that an anchor names exactly: the pins the canvas
/// labels. A cell whose symbol anchors none of its pins maps to an empty
/// set. Pins are matched by name only, never by order or position.
Map<String, Set<String>> symbolCellAnchoredPorts(
  Module module,
  CellSymbolGeometries symbols,
) {
  if (symbols.isEmpty) return const <String, Set<String>>{};
  final result = <String, Set<String>>{};
  for (final cell in module.cells.values) {
    final geometry = symbols[cell.type];
    if (geometry == null) continue;
    result[cell.name] = <String>{
      for (final portName in cell.connections.keys)
        if (geometry.anchors.containsKey(portName)) portName,
    };
  }
  return result;
}

/// Async layout pipeline over the Eclipse Layout Kernel.
///
/// Lifecycle:
///   * Lazily start a worker isolate on the first [layout] call. The worker
///     picks its engine ([ElkSolver]): the vendored elkrs port through
///     `native/elk_ffi` on desktop, or the vendored `assets/elk/elk.bundled.js`
///     on a JavaScript engine when kept by `NETCRUX_LAYOUT_ENGINE` or when
///     the native library cannot start. The browser runs elkjs natively.
///   * On each [layout] call, convert the [Module] to ELK input JSON
///     (see [buildElkInput]), solve, and parse the result via
///     [NetlistLayout.fromJson].
///
/// All failures (asset missing, JS engine boot failure, elk error,
/// JSON parse error) surface as [LayoutException]. The service is safe
/// to share across multiple layout requests — initialization is guarded
/// by a `Future` so concurrent first-callers see the same initialization
/// promise.
class ElkLayoutService {
  /// Creates a service. Optional [hostFactory], [solverFactory] and
  /// [assetLoader] are the test seams: an in-process elkjs host, an
  /// in-process [ElkSolver] of any kind, and the asset loader, which default
  /// to the worker isolate's own engine choice and the Flutter `rootBundle`.
  ElkLayoutService({
    ElkJsHost Function()? hostFactory,
    ElkSolver Function()? solverFactory,
    Future<String> Function(String assetKey)? assetLoader,
    LayoutDiskCache? diskCache,
    this.maxMemCacheEntries = 16,
    this.maxMemCacheBytes = 64 * 1024 * 1024,
    this.maxConeCacheEntries = 8,
  }) : // The public params are `hostFactory` / `diskCache`; an initializing
       // formal can't map them to the private fields without leaking the
       // underscore into the API.
       // ignore: prefer_initializing_formals
       _hostFactory = hostFactory,
       // Same public-param/private-field mapping as `_hostFactory` above.
       // ignore: prefer_initializing_formals
       _solverFactory = solverFactory,
       _assetLoader = assetLoader ?? rootBundle.loadString,
       // Same public-param/private-field mapping as `_hostFactory` above.
       // ignore: prefer_initializing_formals
       _diskCache = diskCache;

  /// Asset keys checked, in order, when loading the bundled elkjs UMD.
  /// The first key is the in-package path that works under
  /// `flutter test` against the netcrux package itself. The second key
  /// is the path Flutter rewrites the asset to when netcrux is consumed
  /// as a path dependency from the Pro overlay (or any other downstream
  /// app): the bundler prepends `packages/<package>/` to every
  /// package-declared asset. Without the second fallback the production
  /// app loads with elkjs missing — every elaboration succeeded but
  /// the schematic painted blank.
  static const List<String> _elkAssetKeys = <String>[
    'assets/elk/elk.bundled.js',
    'packages/netcrux/assets/elk/elk.bundled.js',
  ];

  /// In-process host factory. When non-null (the test seam), [layout] runs
  /// the elkjs solve synchronously on the calling isolate against this host.
  /// When null (the production default), [layout] offloads the solve to a
  /// dedicated background isolate so a large scope's multi-second layout
  /// never blocks the UI isolate.
  final ElkJsHost Function()? _hostFactory;

  /// In-process solver factory (the other test seam): when non-null,
  /// [layout] solves synchronously on the calling isolate with the solver it
  /// makes, whatever engine that is. Lets a test drive the native engine
  /// without a worker isolate.
  final ElkSolver Function()? _solverFactory;
  ElkSolver? _solver;
  final Future<String> Function(String assetKey) _assetLoader;

  /// Persistent (cross-session) layout cache, or null when disabled (tests /
  /// web). Keyed by [_cacheKey].
  final LayoutDiskCache? _diskCache;

  /// Maximum number of layouts retained in [_memCache].
  final int maxMemCacheEntries;

  /// Maximum summed [_MemCacheEntry.approxBytes] retained in [_memCache].
  final int maxMemCacheBytes;

  /// In-session LRU memory cache so re-navigating to a scope (A → B → A)
  /// returns instantly without re-solving. Keyed by [_cacheKey].
  ///
  /// Bounded two ways — [maxMemCacheEntries] (count) and [maxMemCacheBytes]
  /// (summed result-JSON length, the size proxy for a parsed
  /// [NetlistLayout]) — because a session that walks a deep hierarchy visits
  /// one scope per node and each retained layout is megabytes for a large
  /// scope. Eviction is least-recently-used and never touches the entry
  /// being stored, so the scope the user is currently viewing always stays
  /// cached even when it alone exceeds the byte budget. Mirrors
  /// [ElaborationCacheService]'s policy.
  ///
  /// `Map` preserves insertion order; the LRU ordering is maintained by
  /// removing and re-inserting an entry on read.
  final Map<String, _MemCacheEntry> _memCache = <String, _MemCacheEntry>{};

  int _memCacheBytes = 0;

  /// Maximum number of cone-view layouts retained in [_coneCache].
  final int maxConeCacheEntries;

  /// In-session LRU memory cache of cone-view layouts (a layout of part of
  /// a scope), keyed by [_cacheKey] like [_memCache] but separate from it,
  /// so a run of cone views never pushes a whole scope's layout out.
  final Map<String, NetlistLayout> _coneCache = <String, NetlistLayout>{};

  /// Number of layouts currently held in the in-session memory cache.
  @visibleForTesting
  int get memCacheLength => _memCache.length;

  /// Number of cone-view layouts currently held in their memory cache.
  @visibleForTesting
  int get coneCacheLength => _coneCache.length;

  /// Summed size proxy of the layouts currently held in the memory cache.
  @visibleForTesting
  int get memCacheBytes => _memCacheBytes;

  /// Bumped when the layout result format or the elkjs engine changes, to
  /// invalidate persisted layouts (the input-derived part of the key already
  /// covers changes to `buildElkInput`).
  static const String _cacheVersion = 'elk1';

  ElkJsHost? _host;
  Future<void>? _initialization;
  _ElkLayoutIsolate? _isolate;

  /// Lays out [module] using elkjs. Throws [LayoutException] on any
  /// failure in the pipeline.
  ///
  /// The ELK input is built and the result parsed on the calling isolate
  /// (both pure, fast Dart). The elkjs solve itself — the multi-second cost
  /// for a large scope — runs in-process against the injected [_hostFactory]
  /// host (tests), or on a dedicated background isolate (production), so it
  /// never blocks the UI isolate. The provider stays in its loading state
  /// while the isolate works, so the canvas can paint a live progress
  /// indicator.
  ///
  /// Cells whose type has an entry in [symbols] are laid out in their custom
  /// symbol's shape (see [buildElkInput]); that changes the ELK input, and
  /// so the cache key, only for scopes that contain such a cell.
  ///
  /// With [only], the layout is of that part of the scope (a cone view; see
  /// [buildElkInput]). Such a layout is cheap to solve again, so it is kept
  /// in a small memory cache of its own ([maxConeCacheEntries]) and never
  /// on disk: cone views never evict a whole scope's layout from either
  /// cache, and the whole scope's layout survives any number of them.
  Future<NetlistLayout> layout(
    Module module, {
    CellSymbolGeometries symbols = CellSymbolGeometries.none,
    ElkSubgraph? only,
  }) async {
    final input = buildElkInput(module, symbols: symbols, only: only);
    final inputJson = jsonEncode(input);
    final key = _cacheKey(inputJson);

    if (only != null) {
      final cone = _coneCache.remove(key);
      if (cone != null) {
        _coneCache[key] = cone;
        return cone;
      }
      final resultJson = await _solve(inputJson);
      final layout = _parseLayout(resultJson);
      _coneCache[key] = layout;
      while (_coneCache.length > maxConeCacheEntries) {
        _coneCache.remove(_coneCache.keys.first);
      }
      return layout;
    }

    final cached = _lookupMemCache(key);
    if (cached != null) return cached;

    final diskJson = await _diskCache?.read(key);
    if (diskJson != null) {
      try {
        final fromDisk = _parseLayout(diskJson);
        _storeMemCache(key, fromDisk, diskJson.length);
        return fromDisk;
      } on Object {
        // Corrupt / stale cache entry — fall through and re-solve.
      }
    }

    final resultJson = await _solve(inputJson);
    final layout = _parseLayout(resultJson);
    _storeMemCache(key, layout, resultJson.length);
    // Fire-and-forget: persisting must not delay the first paint.
    unawaited(_diskCache?.write(key, resultJson) ?? Future<void>.value());
    return layout;
  }

  /// Whether a solve is running on the worker (isolate, or Web Worker on web)
  /// right now.
  bool get hasLayoutInFlight => kElkWebSolverAvailable
      ? elkWebLayoutInFlight
      : _inProcessJob != null || (_isolate?.hasInFlight ?? false);

  /// The progress of the solve in flight, as the engine reports it: `null`
  /// when nothing is in flight or before the engine's first report, and
  /// always `null` on elkjs, which reports none. The canvas's layout
  /// progress view listens to it.
  ValueListenable<LayoutProgress?> get progress => _progress;
  final ValueNotifier<LayoutProgress?> _progress =
      ValueNotifier<LayoutProgress?>(null);

  /// Counts solves, so a solve that ends after a newer one started leaves
  /// the newer one's [progress] alone.
  int _solveGeneration = 0;

  /// The in-process job of the [_solverFactory] seam, while one runs.
  ElkSolveJob? _inProcessJob;

  /// Abandons the solve in flight, if any: the user stopped it, or moved to
  /// a scope or view that does not need it. The abandoned [layout] call
  /// completes with a [LayoutCancelledException] at once. The native engine
  /// stops at its next check, within a pipeline step, and its worker stays
  /// warm for the next layout; elkjs cannot be interrupted, so its worker is
  /// killed and the next call starts a fresh one. A no-op when nothing is in
  /// flight, so the warm worker survives ordinary navigation.
  void cancelInFlightLayout() {
    if (kElkWebSolverAvailable) {
      cancelElkOnWeb();
    } else {
      _inProcessJob?.cancel();
      _isolate?.cancelInFlight();
    }
  }

  /// Runs the solve for [inputJson] and returns the result JSON string,
  /// in-process against the injected solver or host (tests), on the worker
  /// isolate (desktop) or in the browser's Web Worker (web), publishing the
  /// engine's progress on [progress] while it runs.
  Future<String> _solve(String inputJson) async {
    final generation = ++_solveGeneration;
    void report(LayoutProgress p) {
      if (generation == _solveGeneration) _progress.value = p;
    }

    _progress.value = null;
    try {
      return await _solveWith(inputJson, report);
    } finally {
      if (generation == _solveGeneration) _progress.value = null;
    }
  }

  Future<String> _solveWith(
    String inputJson,
    void Function(LayoutProgress progress) onProgress,
  ) async {
    if (_solverFactory != null) {
      final solver = _solver ??= _solverFactory();
      if (solver is! ElkJobSolver) return solver.solve(inputJson);
      final job = _inProcessJob = solver.start(inputJson);
      try {
        return await driveElkSolveJob(job, onProgress: onProgress);
      } finally {
        if (identical(_inProcessJob, job)) _inProcessJob = null;
      }
    }
    if (_hostFactory != null) {
      await _ensureInitialized();
      return runElkLayoutOnHost(_host!, inputJson);
    }
    // On web the elkrs port runs as WebAssembly in a Web Worker, with elkjs
    // on the page as the fallback when the module cannot load; there is no
    // `dart:ffi` and no `Isolate.spawn` there. Off web this is compiled out
    // (`kElkWebSolverAvailable` is a const `false`) and the solve runs on the
    // background isolate.
    if (kElkWebSolverAvailable) {
      return await solveElkOnWeb(
        inputJson,
        _loadElkSource,
        onProgress: onProgress,
      );
    }
    return await (_isolate ??= _ElkLayoutIsolate(_loadElkSource)).layout(
      inputJson,
      onProgress: onProgress,
    );
  }

  /// Returns the cached layout for [key], promoting it to the LRU tail,
  /// or `null` when there is no entry.
  NetlistLayout? _lookupMemCache(String key) {
    final entry = _memCache.remove(key);
    if (entry == null) return null;
    _memCache[key] = entry;
    return entry.layout;
  }

  /// Stores [layout] under [key] with [approxBytes] as its size proxy,
  /// then evicts least-recently-used entries while either bound is
  /// exceeded. The just-stored entry is never evicted.
  void _storeMemCache(String key, NetlistLayout layout, int approxBytes) {
    final previous = _memCache.remove(key);
    if (previous != null) _memCacheBytes -= previous.approxBytes;
    _memCache[key] = _MemCacheEntry(layout: layout, approxBytes: approxBytes);
    _memCacheBytes += approxBytes;
    while (_memCache.length > 1 &&
        (_memCache.length > maxMemCacheEntries ||
            _memCacheBytes > maxMemCacheBytes)) {
      final oldest = _memCache.keys.first;
      final evicted = _memCache.remove(oldest);
      _memCacheBytes -= evicted!.approxBytes;
    }
  }

  NetlistLayout _parseLayout(String resultJson) {
    final decoded = jsonDecode(resultJson);
    if (decoded is! Map<String, Object?>) {
      throw const LayoutException('elkjs returned a non-object layout result');
    }
    return NetlistLayout.fromJson(decoded);
  }

  /// Stable, cross-session cache key for a layout. The input JSON fully
  /// determines the layout (it folds in the module structure AND the
  /// `buildElkInput` options), so a content hash of it — plus its length to
  /// make a hash collision astronomically unlikely, plus the engine version —
  /// is a safe key. Uses FNV-1a so it is deterministic across runs (unlike
  /// `String.hashCode`).
  static String _cacheKey(String inputJson) =>
      '${_cacheVersion}_${inputJson.length}_'
      '${_fnv1a32(inputJson).toRadixString(16)}';

  static int _fnv1a32(String input) {
    var hash = 0x811c9dc5;
    for (final code in input.codeUnits) {
      hash ^= code & 0xff;
      hash = (hash * 0x01000193) & 0xffffffff;
      hash ^= (code >> 8) & 0xff;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash;
  }

  /// Convenience: lays out the top module of [model], or `null` when
  /// no module is marked top.
  Future<NetlistLayout?> layoutTop(NetlistModel model) async {
    final top = model.topModule;
    if (top == null) return null;
    return await layout(top);
  }

  /// Disposes the in-process host or solver (tests) and tears down the
  /// layout isolate (production). Call when shutting down the app or to free
  /// the engine's memory.
  void dispose() {
    _host?.dispose();
    _host = null;
    _inProcessJob?.cancel();
    _progress.value = null;
    _solver?.dispose();
    _solver = null;
    _initialization = null;
    _isolate?.dispose();
    _isolate = null;
    _memCache.clear();
    _memCacheBytes = 0;
    _coneCache.clear();
  }

  Future<void> _ensureInitialized() {
    return _initialization ??= _initialize();
  }

  /// Loads the elkjs UMD bundle, falling back across the keys declared
  /// in [_elkAssetKeys]. The first key that resolves to a non-empty
  /// string wins; if every key fails the last error is rethrown so the
  /// outer try/catch can wrap it in a [LayoutException].
  Future<String> _loadElkSource() async {
    Object? lastError;
    for (final key in _elkAssetKeys) {
      try {
        final source = await _assetLoader(key);
        if (source.isNotEmpty) return source;
      } on Object catch (e) {
        lastError = e;
      }
    }
    if (lastError is Exception) throw lastError;
    if (lastError is Error) throw lastError;
    throw const LayoutException('elkjs asset not found in any known key');
  }

  Future<void> _initialize() async {
    try {
      final host = _hostFactory!();
      final source = await _loadElkSource();
      initElkRuntime(host, source);
      _host = host;
    } on Object catch (e) {
      _initialization = null;
      if (e is LayoutException) rethrow;
      throw LayoutException(
        'Failed to initialize the elkjs runtime',
        cause: e,
      );
    }
  }
}

/// Boots the elkjs runtime on [host]: installs the GWT/browser shims, loads
/// the [elkSource] UMD bundle, and constructs the singleton `ELK` instance.
/// Throws [LayoutException] if the constructor fails. Top-level so it runs
/// both in-process and inside the layout worker isolate.
void initElkRuntime(ElkJsHost host, String elkSource) {
  host
    // Shim browser/GWT globals that ELK's bundled JS expects.
    //
    // ELK is GWT-compiled — its runtime references `$wnd` (GWT's pointer to
    // the browser window) at constructor time
    // (`$wnd.Error.stackTraceLimit = Error.stackTraceLimit = 64`). QuickJS
    // via flutter_js has no `$wnd`, no `window`, and no
    // `Error.stackTraceLimit`, so `new ELK()` threw synchronously — the
    // exception was swallowed by an outer try/catch in the UMD wrapper,
    // leaving `globalThis.__elkInstance` undefined. Every subsequent
    // `layout()` call then resolved to an empty result and the schematic
    // canvas painted nothing. Map `$wnd` / `window` onto `globalThis` so the
    // GWT runtime sees a host object to drive.
    //
    // ELK's PromisedWorker dispatch also wraps every worker message in
    // `setTimeout(fn, 0)`. QuickJS via flutter_js has no timer driver, so the
    // default flutter_js runtime lacks `setTimeout`. We polyfill it as a FIFO
    // queue that the layout loop drains by calling
    // `globalThis.__drainSetTimeout()` between `executePendingJob` ticks. The
    // polyfill is good enough for ELK's in-band dispatch — it doesn't honor
    // the `ms` argument because ELK only ever passes 0.
    ..evaluate(r'''
      (function(){
        var __setTimeoutQueue = [];
        var __setTimeoutId = 0;
        globalThis.setTimeout = function(fn, ms){
          var id = ++__setTimeoutId;
          __setTimeoutQueue.push({id: id, fn: fn});
          return id;
        };
        globalThis.clearTimeout = function(id){
          for (var i = 0; i < __setTimeoutQueue.length; i++) {
            if (__setTimeoutQueue[i].id === id) {
              __setTimeoutQueue.splice(i, 1);
              return;
            }
          }
        };
        globalThis.__drainSetTimeout = function(){
          while (__setTimeoutQueue.length > 0) {
            var entry = __setTimeoutQueue.shift();
            try { entry.fn(); } catch (e) { /* swallow */ }
          }
        };
        // GWT compatibility shims — see comment above.
        globalThis.$wnd = globalThis;
        if (typeof globalThis.window === "undefined") {
          globalThis.window = globalThis;
        }
        if (typeof globalThis.Error.stackTraceLimit === "undefined") {
          globalThis.Error.stackTraceLimit = 64;
        }
      })();
    ''')
    ..evaluate(elkSource)
    // The UMD bundle attaches `ELK` to globalThis via `g.ELK = f()`. Wrap in
    // a try/catch that surfaces the constructor failure through
    // __elkInitError so callers see a real error instead of a silently-unset
    // __elkInstance.
    ..evaluate('''
      (function(){
        globalThis.__elkInitError = null;
        try {
          globalThis.__elkInstance = new ELK();
        } catch (e) {
          globalThis.__elkInitError = String(e && e.message ? e.message : e);
        }
      })();
    ''');
  final initError = host.evaluate('globalThis.__elkInitError || ""');
  if (initError.isNotEmpty) {
    throw LayoutException('elkjs constructor threw: $initError');
  }
}

/// Runs one elkjs solve on an already-[initElkRuntime]-booted [host] and
/// returns the layout result as a JSON string. Throws [LayoutException] on
/// an elk error or empty result. Top-level so it runs both in-process and
/// inside the layout worker isolate.
String runElkLayoutOnHost(ElkJsHost host, String inputJson) {
  // Stash the input on globalThis and call elk.layout(...), which returns a
  // Promise resolved via a then handler that stores the JSON result back on
  // globalThis under __elk_result. Errors become __elk_error.
  host
    ..evaluate('globalThis.__elk_input = $inputJson;')
    ..evaluate('globalThis.__elk_result = null;')
    ..evaluate('globalThis.__elk_error = null;')
    ..evaluate('''
      globalThis.__elkInstance
        .layout(globalThis.__elk_input)
        .then(function(r){ globalThis.__elk_result = JSON.stringify(r); })
        .catch(function(e){ globalThis.__elk_error = String(e && e.message ? e.message : e); });
    ''');
  // Advance the JS event loop until the Promise resolves. ELK schedules its
  // in-band worker dispatch with `setTimeout(fn, 0)`, which
  // QuickJS-via-flutter_js doesn't drain through `executePendingJob`
  // (microtasks only). The setTimeout polyfill (see initElkRuntime) queues
  // callbacks into a global array; we drain it on every probe tick alongside
  // the microtask queue. Without this, ELK's PromisedWorker.onmessage
  // callback never fires and the promise hangs "pending" forever.
  for (var i = 0; i < 5000; i++) {
    host
      ..executePendingJob()
      ..evaluate(
        'globalThis.__drainSetTimeout && globalThis.__drainSetTimeout();',
      )
      ..executePendingJob();
    final probe = host.evaluate(
      'globalThis.__elk_result === null && globalThis.__elk_error === null ? "pending" : "done"',
    );
    if (probe != 'pending') break;
  }
  final error = host.evaluate('globalThis.__elk_error || ""');
  if (error.isNotEmpty) {
    throw LayoutException('elkjs rejected the layout input: $error');
  }
  final resultStr = host.evaluate('globalThis.__elk_result || ""');
  if (resultStr.isEmpty) {
    throw const LayoutException('elkjs returned an empty layout');
  }
  return resultStr;
}

/// A dedicated long-lived background isolate that owns a flutter_js elkjs
/// runtime and services layout requests, so a large scope's multi-second
/// solve never blocks the UI isolate. The elk UMD source is loaded on the
/// main isolate (via `rootBundle`) and handed to the worker once at init —
/// the worker never touches `rootBundle` (which needs a root-isolate token).
class _ElkLayoutIsolate {
  _ElkLayoutIsolate(this._loadSource);

  /// Loads the elk UMD bundle on the main isolate.
  final Future<String> Function() _loadSource;

  Isolate? _isolate;
  SendPort? _commands;
  ReceivePort? _errors;
  Future<void>? _ready;

  Future<void> _ensureReady() => _ready ??= _start();

  Future<void> _start() async {
    final handshake = ReceivePort();
    // The worker has no `WidgetsBinding`, so anything in flutter_js that
    // reaches for one (its fetch polyfill did, before the host stopped
    // enabling it) surfaces as an asynchronous error that does not affect
    // the layout result. Spawn with `errorsAreFatal: false` and drain the
    // error port — otherwise the default fatal handling tears the worker
    // down mid-flight and every pending `layout()` hangs forever.
    _errors = ReceivePort()..listen((_) {});
    try {
      _isolate = await Isolate.spawn(
        _elkIsolateEntry,
        handshake.sendPort,
        debugName: 'elk-layout',
        errorsAreFatal: false,
        onError: _errors!.sendPort,
      );
      _commands = await handshake.first as SendPort;
    } finally {
      handshake.close();
    }
    final source = await _loadSource();
    final reply = ReceivePort();
    _commands!.send(<String, Object?>{
      'type': 'init',
      'source': source,
      'reply': reply.sendPort,
    });
    final result = await reply.first as Map<Object?, Object?>;
    reply.close();
    if (result['ok'] != true) {
      _ready = null;
      throw LayoutException('elkjs isolate init failed: ${result['error']}');
    }
    _cooperative = result['cooperative'] == true;
  }

  /// What [Future.any] yields when the solve was abandoned first.
  static const Object _cancelled = Object();

  /// Whether the worker's engine stops on request (the native engine), so a
  /// cancel can keep the worker; elkjs cannot, so its worker is killed.
  bool _cooperative = false;

  /// Completer for the solve in flight; completed by [cancelInFlight] and
  /// [dispose].
  Completer<void>? _cancelInFlight;

  /// The worker's id for the solve in flight, for its `cancel` command.
  int? _inFlightId;
  int _nextId = 0;

  /// Whether a solve is running on the worker right now.
  bool get hasInFlight => _cancelInFlight != null;

  /// Runs one solve on the worker and returns its result JSON, passing the
  /// engine's progress reports to [onProgress] as they arrive.
  ///
  /// Two ways out besides a result: the worker reports an engine error, or
  /// [cancelInFlight] abandons the solve, which throws
  /// [LayoutCancelledException]. There is no time limit: the progress view
  /// shows the solve is moving, and the user can stop it or leave.
  Future<String> layout(
    String inputJson, {
    void Function(LayoutProgress progress)? onProgress,
  }) async {
    await _ensureReady();
    final reply = ReceivePort();
    final progress = ReceivePort();
    final id = _nextId++;
    final cancel = _cancelInFlight = Completer<void>();
    _inFlightId = id;
    progress.listen((message) {
      final (phase, fraction) = message! as (int, double?);
      onProgress?.call(
        LayoutProgress(phase: LayoutPhase.values[phase], fraction: fraction),
      );
    });
    _commands!.send(<String, Object?>{
      'type': 'layout',
      'id': id,
      'input': inputJson,
      'reply': reply.sendPort,
      'progress': progress.sendPort,
    });
    try {
      final first = await Future.any<Object?>(<Future<Object?>>[
        reply.first,
        cancel.future.then((_) => _cancelled),
      ]);
      if (identical(first, _cancelled)) throw const LayoutCancelledException();
      final result = first! as Map<Object?, Object?>;
      if (result['cancelled'] == true) throw const LayoutCancelledException();
      if (result['ok'] != true) {
        throw LayoutException('elk layout failed: ${result['error']}');
      }
      return result['result']! as String;
    } finally {
      reply.close();
      progress.close();
      if (identical(_cancelInFlight, cancel)) {
        _cancelInFlight = null;
        _inFlightId = null;
      }
    }
  }

  /// Abandons the solve in flight, if any: the pending [layout] call
  /// completes with a [LayoutCancelledException] at once. The native engine
  /// is told to stop, which it does within a pipeline step, and the worker
  /// stays warm; elkjs cannot be interrupted, so its worker is killed. A
  /// no-op when idle, so the warm worker is kept.
  void cancelInFlight() {
    final cancel = _cancelInFlight;
    if (cancel == null) return;
    if (!_cooperative) {
      dispose();
      return;
    }
    _commands?.send(<String, Object?>{'type': 'cancel', 'id': _inFlightId});
    _cancelInFlight = null;
    _inFlightId = null;
    if (!cancel.isCompleted) cancel.complete();
  }

  void dispose() {
    final cancel = _cancelInFlight;
    _cancelInFlight = null;
    _inFlightId = null;
    if (cancel != null && !cancel.isCompleted) cancel.complete();
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _commands = null;
    _errors?.close();
    _errors = null;
    _ready = null;
    _cooperative = false;
  }
}

/// Entry point for the elk layout worker isolate. Owns one [ElkSolver],
/// chosen by [createDefaultElkSolver] at `init`; services `init`, `layout`,
/// `cancel` and `dispose` commands, replying on each message's port. The
/// `init` reply carries the engine's description and whether it stops on
/// request.
///
/// A native solve runs as a job on the engine's own thread, so this isolate
/// stays free while it runs: it polls the job, forwards its progress to the
/// `layout` message's progress port, and passes a `cancel` for that job's id
/// on to the engine. An elkjs solve runs synchronously here.
Future<void> _elkIsolateEntry(SendPort handshake) async {
  final commands = ReceivePort();
  handshake.send(commands.sendPort);
  ElkSolver? solver;
  final jobs = <int, ElkSolveJob>{};
  commands.listen((message) async {
    final command = message! as Map<Object?, Object?>;
    if (command['type'] == 'cancel') {
      jobs[command['id']]?.cancel();
      return;
    }
    final reply = command['reply']! as SendPort;
    try {
      switch (command['type']) {
        case 'init':
          final created = solver = createDefaultElkSolver(
            command['source']! as String,
          );
          reply.send(<String, Object?>{
            'ok': true,
            'engine': created.engineDescription,
            'cooperative': created is ElkJobSolver,
          });
        case 'layout':
          final input = command['input']! as String;
          final engine = solver!;
          if (engine is! ElkJobSolver) {
            reply.send(<String, Object?>{
              'ok': true,
              'result': engine.solve(input),
            });
            return;
          }
          final id = command['id']! as int;
          final progress = command['progress'] as SendPort?;
          final job = jobs[id] = engine.start(input);
          try {
            final result = await driveElkSolveJob(
              job,
              onProgress: (p) => progress?.send((p.phase.index, p.fraction)),
            );
            reply.send(<String, Object?>{'ok': true, 'result': result});
          } finally {
            jobs.remove(id);
          }
        case 'dispose':
          for (final job in jobs.values) {
            job.cancel();
          }
          solver?.dispose();
          reply.send(<String, Object?>{'ok': true});
          commands.close();
      }
    } on LayoutCancelledException {
      reply.send(<String, Object?>{'ok': false, 'cancelled': true});
    } on Object catch (e) {
      reply.send(<String, Object?>{'ok': false, 'error': '$e'});
    }
  });
}

/// One entry in [ElkLayoutService]'s in-session LRU memory cache: the
/// parsed [layout] plus [approxBytes], the size proxy driving the byte
/// bound (the length of the result JSON the layout was parsed from).
class _MemCacheEntry {
  const _MemCacheEntry({required this.layout, required this.approxBytes});

  final NetlistLayout layout;
  final int approxBytes;
}
