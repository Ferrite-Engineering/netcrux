// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:netcrux/domain/models/layout/bounding_box.dart';
import 'package:netcrux/domain/models/layout/edge_route.dart';
import 'package:netcrux/domain/models/layout/netlist_layout.dart';
import 'package:netcrux/domain/models/layout/node_position.dart';
import 'package:netcrux/domain/models/netlist/hierarchy_node.dart';
import 'package:netcrux/domain/models/schematic/laid_out_graph.dart';
import 'package:netcrux/domain/models/schematic/schematic_graph.dart';
import 'package:netcrux/services/schematic/schematic_graph_builder.dart';
import 'package:netcrux/services/yosys/streaming_yosys_json_reader.dart';

/// The committed `grid_100k` design (100 shift registers of 1,000 flops, one
/// flat scope) built into a schematic graph by the real
/// [SchematicGraphBuilder], then placed and routed deterministically.
///
/// elkjs runs in a JS runtime that does not start under `flutter test`, so
/// the geometry is synthetic, shaped like what the layout service produces:
/// every cell a node with a port box per pin (inputs west, outputs east,
/// others south), module ports down the left edge, and each routed edge an
/// orthogonal polyline between its two pin boxes. As in the layout service,
/// a net whose driver × sink product exceeds 32 (the clock) is left
/// unrouted: it stays in the graph's edges and is absent from the layout's.
LaidOutGraph flattenedGrid100k() => laidOutFixture(
  'test/fixtures/netlist/grid_100k/generated/grid_100k.netlist.json.gz',
);

/// The top scope of the gzipped Yosys netlist at [gzPath], built by the real
/// [SchematicGraphBuilder] and laid out by [placeAndRoute].
LaidOutGraph laidOutFixture(String gzPath) {
  final raw = utf8.decode(GZipCodec().decode(File(gzPath).readAsBytesSync()));
  final model = const StreamingYosysJsonReader().parse(raw);
  final graph = const SchematicGraphBuilder().build(
    model,
    HierarchyNode.rootOf(model)!,
  );
  return placeAndRoute(graph);
}

/// Deterministic grid placement and orthogonal routing for [graph]; see
/// [flattenedGrid100k].
LaidOutGraph placeAndRoute(SchematicGraph graph) {
  const pitchX = 110.0;
  const pitchY = 80.0;
  const cellW = 60.0;
  const cellH = 44.0;
  final columns = max(1, sqrt(graph.cells.length * 1.5).ceil());
  final nodes = <NodePosition>[];
  final pinCentre = <String, (double, double)>{};
  for (var i = 0; i < graph.cells.length; i++) {
    final cell = graph.cells[i];
    final x = (i % columns) * pitchX;
    final y = (i ~/ columns) * pitchY;
    final ports = <String, BoundingBox>{};
    var west = 0;
    var east = 0;
    var south = 0;
    for (final port in cell.ports) {
      final BoundingBox box;
      switch (port.side) {
        case SchematicPortSide.west:
          box = BoundingBox(x: 0, y: 6.0 + 10 * west++, width: 4, height: 4);
        case SchematicPortSide.east:
          box = BoundingBox(x: 56, y: 6.0 + 10 * east++, width: 4, height: 4);
        case SchematicPortSide.south:
        case SchematicPortSide.north:
          box = BoundingBox(x: 8.0 + 10 * south++, y: 40, width: 4, height: 4);
      }
      ports[port.id] = box;
      pinCentre[port.id] = (x + box.x + 2, y + box.y + 2);
    }
    nodes.add(
      NodePosition(
        id: cell.id,
        bounds: BoundingBox(x: x, y: y, width: cellW, height: cellH),
        ports: ports,
      ),
    );
  }
  for (var i = 0; i < graph.boundaryPorts.length; i++) {
    final port = graph.boundaryPorts[i];
    final y = i * 24.0;
    nodes.add(
      NodePosition(
        id: port.id,
        bounds: BoundingBox(x: -200, y: y, width: 16, height: 16),
      ),
    );
    pinCentre[port.id] = (-184, y + 8);
  }

  final edgesPerNet = <int, int>{};
  for (final edge in graph.edges) {
    edgesPerNet[edge.netId] = (edgesPerNet[edge.netId] ?? 0) + 1;
  }
  final routes = <EdgeRoute>[];
  for (final edge in graph.edges) {
    if (edgesPerNet[edge.netId]! > 32) continue;
    final from = pinCentre[edge.sourcePortId];
    final to = pinCentre[edge.targetPortId];
    if (from == null || to == null) continue;
    final midX = (from.$1 + to.$1) / 2;
    routes.add(
      EdgeRoute(
        id: 'e_${edge.netId}_${routes.length}',
        points: <LayoutPoint>[
          LayoutPoint(from.$1, from.$2),
          LayoutPoint(midX, from.$2),
          LayoutPoint(midX, to.$2),
          LayoutPoint(to.$1, to.$2),
        ],
      ),
    );
  }
  final rows = (graph.cells.length / columns).ceil();
  return LaidOutGraph(
    graph: graph,
    layout: NetlistLayout(
      nodes: nodes,
      edges: routes,
      bounds: BoundingBox(
        x: -200,
        y: 0,
        width: columns * pitchX + 200,
        height: max(rows * pitchY, graph.boundaryPorts.length * 24.0),
      ),
    ),
  );
}
