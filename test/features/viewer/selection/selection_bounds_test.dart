// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/layout/bounding_box.dart';
import 'package:netcrux/domain/models/layout/edge_route.dart';
import 'package:netcrux/domain/models/layout/netlist_layout.dart';
import 'package:netcrux/domain/models/layout/node_position.dart';
import 'package:netcrux/domain/models/schematic/cell_kind.dart';
import 'package:netcrux/domain/models/schematic/laid_out_graph.dart';
import 'package:netcrux/domain/models/schematic/schematic_graph.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/domain/models/trace/trace_overlay.dart';
import 'package:netcrux/features/viewer/selection/selection_bounds.dart';

/// Three cells and a boundary port spread across the layout, one routed
/// two-segment net (`e_7_*`) and one lone wire.
LaidOutGraph _fixture() => const LaidOutGraph(
  graph: SchematicGraph(
    moduleName: 'top',
    cells: <SchematicCell>[
      SchematicCell(
        id: 'a',
        kind: CellKind.generic,
        type: 'and',
        ports: <SchematicPort>[],
      ),
      SchematicCell(
        id: 'b',
        kind: CellKind.generic,
        type: 'or',
        ports: <SchematicPort>[],
      ),
      SchematicCell(
        id: 'far',
        kind: CellKind.generic,
        type: 'xor',
        ports: <SchematicPort>[],
      ),
    ],
    boundaryPorts: <SchematicBoundaryPort>[],
    edges: <SchematicEdge>[],
  ),
  layout: NetlistLayout(
    bounds: BoundingBox(x: 0, y: 0, width: 2000, height: 1000),
    nodes: <NodePosition>[
      NodePosition(
        id: 'a',
        bounds: BoundingBox(x: 0, y: 0, width: 50, height: 40),
      ),
      NodePosition(
        id: 'b',
        bounds: BoundingBox(x: 300, y: 100, width: 50, height: 40),
      ),
      NodePosition(
        id: 'far',
        bounds: BoundingBox(x: 1800, y: 900, width: 50, height: 40),
      ),
      NodePosition(
        id: 'p_in',
        bounds: BoundingBox(x: -100, y: 500, width: 20, height: 20),
      ),
    ],
    edges: <EdgeRoute>[
      EdgeRoute(
        id: 'e_7_0',
        points: <LayoutPoint>[LayoutPoint(50, 20), LayoutPoint(300, 120)],
      ),
      EdgeRoute(
        id: 'e_7_1',
        points: <LayoutPoint>[LayoutPoint(50, 20), LayoutPoint(50, 700)],
      ),
      EdgeRoute(
        id: 'lone',
        points: <LayoutPoint>[LayoutPoint(400, 300), LayoutPoint(600, 300)],
      ),
    ],
  ),
);

void main() {
  final laidOut = _fixture();

  test('frames one selected cell', () {
    expect(
      selectionBounds(
        laidOut,
        selection: const [SelectedElement.cell(cellId: 'a')],
      ),
      const BoundingBox(x: 0, y: 0, width: 50, height: 40),
    );
  });

  test('frames the union of a multi-selection', () {
    expect(
      selectionBounds(
        laidOut,
        selection: const [
          SelectedElement.cell(cellId: 'a'),
          SelectedElement.cell(cellId: 'b'),
        ],
      ),
      const BoundingBox(x: 0, y: 0, width: 350, height: 140),
    );
  });

  test('a pin frames its host cell, a boundary port its own node', () {
    expect(
      selectionBounds(
        laidOut,
        selection: const [
          SelectedElement.port(cellId: 'b', portId: 'b.Y', portName: 'Y'),
          SelectedElement.boundaryPort(portId: 'p_in', portName: 'in'),
        ],
      ),
      const BoundingBox(x: -100, y: 100, width: 450, height: 420),
    );
  });

  test('a wire frames every routed segment of its net', () {
    expect(
      selectionBounds(
        laidOut,
        selection: const [
          SelectedElement.wire(edgeId: 'e_7_0', netId: 7),
        ],
      ),
      const BoundingBox(x: 50, y: 20, width: 250, height: 680),
    );
  });

  test('adds every cell, wire and port an overlay highlights', () {
    const overlay = TraceOverlay(
      mode: TraceOverlayMode.fanout,
      highlightedCellIds: <String>{'a', 'far'},
      highlightedEdgeIds: <String>{'lone'},
      highlightedBoundaryPortIds: <String>{'p_in'},
    );
    expect(
      selectionBounds(
        laidOut,
        selection: const [SelectedElement.cell(cellId: 'a')],
        overlay: overlay,
      ),
      const BoundingBox(x: -100, y: 0, width: 1950, height: 940),
    );
  });

  test('a lone straight wire is widened to the minimum extent', () {
    final box = selectionBounds(
      laidOut,
      selection: const [SelectedElement.wire(edgeId: 'lone', netId: 99)],
    );
    expect(box, const BoundingBox(x: 400, y: 280, width: 200, height: 40));
  });

  test('null when nothing resolves to laid-out geometry', () {
    expect(
      selectionBounds(
        laidOut,
        selection: const [SelectedElement.cell(cellId: 'missing')],
      ),
      isNull,
    );
    expect(
      selectionBounds(laidOut, selection: const <SelectedElement>[]),
      isNull,
    );
    expect(
      selectionBounds(
        LaidOutGraph.empty,
        selection: const [SelectedElement.cell(cellId: 'a')],
      ),
      isNull,
    );
  });
}
