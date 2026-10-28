// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The headless half of a schematic render: one scope of an elaborated netlist,
// laid out the way the canvas lays it out, ready for the SVG exporter or the
// painter. `tool/render_schematic.dart` drives it from the command line.

import 'dart:convert';

import 'package:netcrux/domain/models/layout/bounding_box.dart';
import 'package:netcrux/domain/models/layout/netlist_layout.dart';
import 'package:netcrux/domain/models/netlist/hierarchy_node.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/schematic/laid_out_graph.dart';
import 'package:netcrux/services/layout/elk_layout_service.dart';
import 'package:netcrux/services/schematic/declared_cell_ports.dart';
import 'package:netcrux/services/schematic/schematic_graph_builder.dart';

/// Thrown when a render request cannot be met: a scope path that names no
/// scope, or a picture too large to paint.
class ScopeRenderException implements Exception {
  /// Creates the exception with a message for the person who ran the tool.
  const ScopeRenderException(this.message);

  /// What went wrong, in a sentence.
  final String message;

  @override
  String toString() => message;
}

/// The scope [path] names in [model]: dot-separated instance names from the
/// top module, such as `u_core.u_rf`. An empty path is the top module, and a
/// leading segment equal to the top module's name is accepted and skipped, so
/// the breadcrumb's `top.u_core.u_rf` works as well.
///
/// Throws [ScopeRenderException] when the model has no top module or a
/// segment names no instance of a user module.
HierarchyNode scopeAtPath(NetlistModel model, String path) {
  final root = HierarchyNode.rootOf(model);
  if (root == null) {
    throw const ScopeRenderException('the netlist has no top module');
  }
  final segments = <String>[
    for (final s in path.split('.'))
      if (s.isNotEmpty) s,
  ];
  if (segments.isNotEmpty && segments.first == root.moduleName) {
    segments.removeAt(0);
  }
  var node = root;
  for (final segment in segments) {
    final next = node.child(model, segment);
    if (next == null) {
      throw ScopeRenderException(
        'no instance "$segment" of a user module in '
        '${node.canonicalPath(model)}',
      );
    }
    node = next;
  }
  return node;
}

/// [node] of [model] laid out as the canvas lays a whole scope out: the graph
/// from [SchematicGraphBuilder], the layout from [buildElkInput] over the same
/// module with its declared-but-unconnected pins added, solved by [solve]
/// (ELK JSON in, laid-out ELK JSON out; `NativeElkSolver.solve` on desktop).
LaidOutGraph layOutScope(
  NetlistModel model,
  HierarchyNode node,
  String Function(String inputJson) solve,
) {
  final module = node.resolve(model);
  if (module == null) {
    throw ScopeRenderException(
      'the scope ${node.canonicalPath(model)} does not resolve to a module',
    );
  }
  final graph = const SchematicGraphBuilder().build(model, node);
  final input = buildElkInput(withDeclaredCellPorts(model, module));
  final layout = NetlistLayout.fromJson(
    jsonDecode(solve(jsonEncode(input))) as Map<String, Object?>,
  );
  return LaidOutGraph(graph: graph, layout: layout);
}

/// Parses a `--region` value, `x,y,width,height` in layout units.
///
/// Throws [FormatException] for anything else, or a width or height that is
/// not positive.
BoundingBox parseRenderRegion(String value) {
  final parts = value.split(',').map((s) => double.tryParse(s.trim()));
  final numbers = parts.toList();
  if (numbers.length != 4 || numbers.any((n) => n == null)) {
    throw FormatException('expected x,y,width,height, got "$value"');
  }
  final [x!, y!, width!, height!] = numbers;
  if (width <= 0 || height <= 0) {
    throw FormatException('width and height must be positive in "$value"');
  }
  return BoundingBox(x: x, y: y, width: width, height: height);
}

/// The part of the layout a render shows: [region] when given, otherwise the
/// whole layout with [margin] layout units of space on every side, room
/// for the name beside a boundary port at the edge.
BoundingBox renderFrame(
  LaidOutGraph laidOut, {
  BoundingBox? region,
  double margin = 96,
}) {
  if (region != null) return region;
  final b = laidOut.layout.bounds;
  return BoundingBox(
    x: b.x - margin,
    y: b.y - margin,
    width: b.width + 2 * margin,
    height: b.height + 2 * margin,
  );
}

/// The largest picture side, in pixels, a PNG render paints. Beyond it the
/// render stops with a message instead of exhausting memory.
const int maxRenderPixels = 16384;

/// The pixel size of a PNG of [frame] at [zoom] (pixels per layout unit),
/// rounded up.
///
/// Throws [ScopeRenderException] when a side exceeds [maxRenderPixels], with
/// the zoom that would fit, so the person can render a region or zoom out.
({int width, int height}) renderPixelSize(BoundingBox frame, double zoom) {
  final width = (frame.width * zoom).ceil();
  final height = (frame.height * zoom).ceil();
  final longest = width > height ? frame.width : frame.height;
  if (width > maxRenderPixels || height > maxRenderPixels) {
    // Rounded down, so the zoom named does fit.
    final fits = (maxRenderPixels / longest * 1000).floorToDouble() / 1000;
    throw ScopeRenderException(
      'a ${width}x$height pixel picture is larger than $maxRenderPixels '
      'pixels a side; use --zoom ${fits.toStringAsFixed(3)} or less, or '
      '--region to render part of the scope',
    );
  }
  return (width: width, height: height);
}
