// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/layout/bounding_box.dart';
import 'package:netcrux/domain/models/layout/edge_route.dart';
import 'package:netcrux/domain/models/layout/netlist_layout.dart';
import 'package:netcrux/domain/models/layout/node_position.dart';
import 'package:netcrux/domain/models/netlist/port_direction.dart';
import 'package:netcrux/domain/models/schematic/cell_kind.dart';
import 'package:netcrux/domain/models/schematic/laid_out_graph.dart';
import 'package:netcrux/domain/models/schematic/schematic_graph.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/features/viewer/rendering/schematic_painter.dart';
import 'package:netcrux/features/viewer/selection/schematic_hit_test.dart';

/// One cell (`u_and`, body 20,30 → 100,90) with an output port `Y`
/// (center 96,58), a boundary port (`port:y`, 160,30 → 176,46), and a
/// wire from the cell output to the boundary (100,60 → 160,38).
LaidOutGraph _graph() {
  const graph = SchematicGraph(
    moduleName: 'top',
    cells: <SchematicCell>[
      SchematicCell(
        id: 'u_and',
        kind: CellKind.andGate,
        type: r'$and',
        ports: <SchematicPort>[
          SchematicPort(
            id: 'u_and:Y',
            name: 'Y',
            direction: PortDirection.output,
            side: SchematicPortSide.east,
          ),
        ],
      ),
    ],
    boundaryPorts: <SchematicBoundaryPort>[
      SchematicBoundaryPort(
        id: 'port:y',
        name: 'y',
        direction: PortDirection.output,
        width: 1,
      ),
    ],
    edges: <SchematicEdge>[
      SchematicEdge(
        id: 'e0',
        sourcePortId: 'u_and:Y',
        targetPortId: 'port:y',
        netId: 4,
      ),
    ],
  );
  const layout = NetlistLayout(
    nodes: <NodePosition>[
      NodePosition(
        id: 'u_and',
        bounds: BoundingBox(x: 20, y: 30, width: 80, height: 60),
        ports: <String, BoundingBox>{
          // Port box is relative to the node bounds → abs center (96,58).
          'u_and:Y': BoundingBox(x: 76, y: 28, width: 4, height: 4),
        },
      ),
      NodePosition(
        id: 'port:y',
        bounds: BoundingBox(x: 160, y: 30, width: 16, height: 16),
      ),
    ],
    edges: <EdgeRoute>[
      EdgeRoute(
        id: 'e0',
        points: <LayoutPoint>[LayoutPoint(100, 60), LayoutPoint(160, 38)],
      ),
    ],
    bounds: BoundingBox(x: 0, y: 0, width: 200, height: 120),
  );
  return const LaidOutGraph(graph: graph, layout: layout);
}

SchematicHitTester _tester({
  ViewportTransform transform = ViewportTransform.identity,
}) => SchematicHitTester(laidOut: _graph(), transform: transform);

void main() {
  group('SchematicHitTester.hitTest — identity transform', () {
    test('a click on a port pin selects the port (ports win over cells)', () {
      final hit = _tester().hitTest(const Offset(96, 58));
      expect(hit, isA<SelectedElementPort>());
      final port = hit as SelectedElementPort;
      expect(port.cellId, 'u_and');
      expect(port.portId, 'u_and:Y');
      expect(port.portName, 'Y');
    });

    test('a click inside the cell body (away from pins) selects the cell', () {
      final hit = _tester().hitTest(const Offset(40, 45));
      expect(hit, isA<SelectedElementCell>());
      expect((hit as SelectedElementCell).cellId, 'u_and');
    });

    test('a click on a boundary port selects it', () {
      final hit = _tester().hitTest(const Offset(168, 38));
      expect(hit, isA<SelectedElementBoundaryPort>());
      final bp = hit as SelectedElementBoundaryPort;
      expect(bp.portId, 'port:y');
      expect(bp.portName, 'y');
    });

    test('a click near a wire polyline selects the wire with its netId', () {
      final hit = _tester().hitTest(const Offset(130, 49));
      expect(hit, isA<SelectedElementWire>());
      final wire = hit as SelectedElementWire;
      expect(wire.edgeId, 'e0');
      expect(wire.netId, 4);
    });

    test('a click on empty canvas selects nothing', () {
      expect(
        _tester().hitTest(const Offset(400, 400)),
        isA<SelectedElementNone>(),
      );
    });

    test('a click just outside the wire slop misses the wire', () {
      // Far above the (100,60)->(160,38) segment, well beyond wireSlop=6.
      expect(
        _tester().hitTest(const Offset(130, 10)),
        isA<SelectedElementNone>(),
      );
    });
  });

  group('SchematicHitTester.hitTest — viewport transform inversion', () {
    test('a scaled + translated viewport point maps back to design space', () {
      // design (40,45) → screen (40*2+10, 45*2+5) = (90,95).
      const transform = ViewportTransform(zoom: 2, offset: Offset(10, 5));
      final hit = _tester(transform: transform).hitTest(const Offset(90, 95));
      expect(hit, isA<SelectedElementCell>());
      expect((hit as SelectedElementCell).cellId, 'u_and');
    });
  });

  group('SchematicHitTester.hitTest — empty graph', () {
    test('an empty laid-out graph always misses', () {
      const hitTester = SchematicHitTester(
        laidOut: LaidOutGraph.empty,
        transform: ViewportTransform.identity,
      );
      expect(
        hitTester.hitTest(const Offset(10, 10)),
        isA<SelectedElementNone>(),
      );
    });
  });
}
