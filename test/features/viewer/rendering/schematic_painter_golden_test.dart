// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/layout/bounding_box.dart';
import 'package:netcrux/domain/models/layout/edge_route.dart';
import 'package:netcrux/domain/models/layout/netlist_layout.dart';
import 'package:netcrux/domain/models/layout/node_position.dart';
import 'package:netcrux/domain/models/netlist/port_direction.dart';
import 'package:netcrux/domain/models/schematic/cell_kind.dart';
import 'package:netcrux/domain/models/schematic/laid_out_graph.dart';
import 'package:netcrux/domain/models/schematic/pin_tie.dart';
import 'package:netcrux/domain/models/schematic/schematic_graph.dart';
import 'package:netcrux/features/viewer/rendering/lod_band.dart';
import 'package:netcrux/features/viewer/rendering/schematic_painter.dart';

/// Whole-scope render golden. Pins the
/// painter's geometry for a fixed three-cell design so a paint-geometry
/// refactor is caught by a pixel diff, not just "does not throw".
///
/// Rendered at `zoom == LodBandRouter.midUpper` (the detail/mid boundary):
/// nudging that threshold by one step (the mutation test) flips the scope
/// from the detail band (labels) to the mid band (no labels) and reds this
/// golden — proving it pins the LOD geometry, not merely that paint runs.
///
/// Regenerate: `flutter test --update-goldens \
///   test/features/viewer/rendering/schematic_painter_golden_test.dart`
LaidOutGraph _threeCellChain() {
  SchematicCell cell(String id, CellKind kind) => SchematicCell(
    id: id,
    kind: kind,
    type: r'$_DFF_P_',
    ports: <SchematicPort>[
      SchematicPort(
        id: '$id:D',
        name: 'D',
        direction: PortDirection.input,
        side: SchematicPortSide.west,
      ),
      SchematicPort(
        id: '$id:Q',
        name: 'Q',
        direction: PortDirection.output,
        side: SchematicPortSide.east,
      ),
    ],
  );

  final graph = SchematicGraph(
    moduleName: 'chain3',
    cells: <SchematicCell>[
      cell('ff0', CellKind.flipFlop),
      cell('ff1', CellKind.flipFlop),
      cell('ff2', CellKind.flipFlop),
    ],
    boundaryPorts: const <SchematicBoundaryPort>[
      SchematicBoundaryPort(
        id: 'port:d',
        name: 'd',
        direction: PortDirection.input,
        width: 1,
      ),
      SchematicBoundaryPort(
        id: 'port:q',
        name: 'q',
        direction: PortDirection.output,
        width: 1,
      ),
    ],
    edges: const <SchematicEdge>[
      SchematicEdge(
        id: 'e0',
        sourcePortId: 'ff0:Q',
        targetPortId: 'ff1:D',
        netId: 3,
      ),
      SchematicEdge(
        id: 'e1',
        sourcePortId: 'ff1:Q',
        targetPortId: 'ff2:D',
        netId: 4,
      ),
    ],
  );

  NodePosition node(String id, double x) => NodePosition(
    id: id,
    bounds: BoundingBox(x: x, y: 40, width: 60, height: 50),
    ports: <String, BoundingBox>{
      '$id:D': const BoundingBox(x: 0, y: 22, width: 4, height: 4),
      '$id:Q': const BoundingBox(x: 56, y: 22, width: 4, height: 4),
    },
  );

  final layout = NetlistLayout(
    nodes: <NodePosition>[
      node('ff0', 30),
      node('ff1', 140),
      node('ff2', 250),
      const NodePosition(
        id: 'port:d',
        bounds: BoundingBox(x: 0, y: 56, width: 16, height: 16),
      ),
      const NodePosition(
        id: 'port:q',
        bounds: BoundingBox(x: 320, y: 56, width: 16, height: 16),
      ),
    ],
    edges: const <EdgeRoute>[
      EdgeRoute(
        id: 'e0',
        points: <LayoutPoint>[LayoutPoint(90, 65), LayoutPoint(140, 65)],
      ),
      EdgeRoute(
        id: 'e1',
        points: <LayoutPoint>[LayoutPoint(200, 65), LayoutPoint(250, 65)],
      ),
    ],
    bounds: const BoundingBox(x: 0, y: 0, width: 340, height: 120),
  );
  return LaidOutGraph(graph: graph, layout: layout);
}

/// One LUT the way the serv_ice40 carry LUT is wired, plus a fault: I0 and
/// I1 tied to 0, I2 on a net from a driver, I3 on a net nothing drives, and
/// a fifth input `EN` the netlist left unconnected. Ports sit where
/// FIXED_SIDE puts them: inputs on the west face, the output east.
LaidOutGraph _tiedLut() {
  SchematicPort input(String name, PinTie tie) => SchematicPort(
    id: 'lut:$name',
    name: name,
    direction: PortDirection.input,
    side: SchematicPortSide.west,
    tie: tie,
  );
  final graph = SchematicGraph(
    moduleName: 'tied',
    cells: <SchematicCell>[
      SchematicCell(
        id: 'lut',
        kind: CellKind.generic,
        type: 'SB_LUT4',
        ports: <SchematicPort>[
          input('I0', const PinTie.constant('0')),
          input('I1', const PinTie.constant('0')),
          input('I2', PinTie.net),
          input('I3', PinTie.undriven),
          input('EN', PinTie.unconnected),
          const SchematicPort(
            id: 'lut:O',
            name: 'O',
            direction: PortDirection.output,
            side: SchematicPortSide.east,
          ),
        ],
      ),
      const SchematicCell(
        id: 'drv',
        kind: CellKind.generic,
        type: 'SB_DFF',
        ports: <SchematicPort>[
          SchematicPort(
            id: 'drv:Q',
            name: 'Q',
            direction: PortDirection.output,
            side: SchematicPortSide.east,
          ),
        ],
      ),
    ],
    boundaryPorts: const <SchematicBoundaryPort>[],
    edges: const <SchematicEdge>[
      SchematicEdge(
        id: 'e0',
        sourcePortId: 'drv:Q',
        targetPortId: 'lut:I2',
        netId: 3,
      ),
    ],
  );
  BoundingBox west(double y) => BoundingBox(x: -4, y: y, width: 4, height: 4);
  final layout = NetlistLayout(
    nodes: <NodePosition>[
      NodePosition(
        id: 'lut',
        bounds: const BoundingBox(x: 70, y: 10, width: 60, height: 70),
        ports: <String, BoundingBox>{
          'lut:I0': west(8),
          'lut:I1': west(20),
          'lut:I2': west(32),
          'lut:I3': west(44),
          'lut:EN': west(56),
          'lut:O': const BoundingBox(x: 60, y: 32, width: 4, height: 4),
        },
      ),
      const NodePosition(
        id: 'drv',
        bounds: BoundingBox(x: 4, y: 30, width: 30, height: 30),
        ports: <String, BoundingBox>{
          'drv:Q': BoundingBox(x: 30, y: 12, width: 4, height: 4),
        },
      ),
    ],
    edges: const <EdgeRoute>[
      EdgeRoute(
        id: 'e0',
        points: <LayoutPoint>[LayoutPoint(36, 44), LayoutPoint(68, 44)],
      ),
    ],
    bounds: const BoundingBox(x: 0, y: 0, width: 150, height: 90),
  );
  return LaidOutGraph(graph: graph, layout: layout);
}

Widget _canvas(LaidOutGraph laidOut, double zoom, ThemeData theme) =>
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 150 * zoom,
            height: 90 * zoom,
            child: SchematicCanvas(
              laidOut: laidOut,
              transform: ViewportTransform(zoom: zoom, offset: Offset.zero),
              statsSink: const NoopRenderStatsSink(),
              theme: theme,
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('tied pins: constant labels, an undriven stub, a bare pin', (
    tester,
  ) async {
    await tester.pumpWidget(
      _canvas(_tiedLut(), 3, ThemeData.light(useMaterial3: true)),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(SchematicCanvas),
      matchesGoldenFile('goldens/tied_pins_lut.png'),
    );
  });

  testWidgets('tied pins paint in the mid band and in a dark theme', (
    tester,
  ) async {
    for (final theme in <ThemeData>[
      ThemeData.dark(useMaterial3: true),
      ThemeData.light(useMaterial3: true),
    ]) {
      await tester.pumpWidget(_canvas(_tiedLut(), 0.5, theme));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('whole-scope render golden (detail/mid boundary)', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              height: 140,
              child: SchematicCanvas(
                laidOut: _threeCellChain(),
                // At exactly midUpper the scope is in the detail band; a
                // one-step nudge to the threshold flips it to mid and reds
                // this golden.
                transform: const ViewportTransform(
                  zoom: LodBandRouter.midUpper,
                  offset: Offset.zero,
                ),
                statsSink: const NoopRenderStatsSink(),
                theme: ThemeData.light(useMaterial3: true),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(SchematicCanvas),
      matchesGoldenFile('goldens/whole_scope_chain3.png'),
    );
  });
}
