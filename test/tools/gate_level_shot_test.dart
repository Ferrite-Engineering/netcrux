// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Marketing-asset generator (not a real test): renders a small, curated
// gate-level design through NetCrux's ACTUAL SchematicPainter in the real
// dark theme, at a detail-band zoom, and writes a high-resolution PNG to
// build/gate_level.png. Run with:
//
//   flutter test test/tools/gate_level_shot_test.dart
//
// Then the PNG is copied into the product website's screenshots. The circuit
// is a curated 1-bit register slice (AND / OR / NOT / MUX / DFF), so it uses
// only real symbol-library shapes and reads as an actual schematic — the point
// being to show that the graph resolves into gate symbols when zoomed in,
// which the existing (overview-band) site screenshots do not.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/theme/netcrux_theme.dart';
import 'package:netcrux/domain/models/layout/bounding_box.dart';
import 'package:netcrux/domain/models/layout/edge_route.dart';
import 'package:netcrux/domain/models/layout/netlist_layout.dart';
import 'package:netcrux/domain/models/layout/node_position.dart';
import 'package:netcrux/domain/models/netlist/port_direction.dart';
import 'package:netcrux/domain/models/schematic/cell_kind.dart';
import 'package:netcrux/domain/models/schematic/laid_out_graph.dart';
import 'package:netcrux/domain/models/schematic/schematic_graph.dart';
import 'package:netcrux/features/viewer/rendering/schematic_painter.dart';

/// A curated 1-bit register slice: two inputs feed an AND and an OR gate, a
/// 2:1 MUX selects between them, a flip-flop registers the result, and an
/// inverter drives a second output. Only real symbol kinds, laid out by hand.
LaidOutGraph _registerSlice() {
  SchematicPort p(
    String cell,
    String name,
    PortDirection dir,
    SchematicPortSide side,
  ) => SchematicPort(id: '$cell:$name', name: name, direction: dir, side: side);

  SchematicCell cell(
    String id,
    CellKind kind,
    String type,
    List<SchematicPort> ports,
  ) => SchematicCell(id: id, kind: kind, type: type, ports: ports);

  final graph = SchematicGraph(
    moduleName: 'reg_slice',
    cells: <SchematicCell>[
      cell('g_and', CellKind.andGate, r'$_AND_', <SchematicPort>[
        p('g_and', 'A', PortDirection.input, SchematicPortSide.west),
        p('g_and', 'B', PortDirection.input, SchematicPortSide.west),
        p('g_and', 'Y', PortDirection.output, SchematicPortSide.east),
      ]),
      cell('g_or', CellKind.orGate, r'$_OR_', <SchematicPort>[
        p('g_or', 'A', PortDirection.input, SchematicPortSide.west),
        p('g_or', 'B', PortDirection.input, SchematicPortSide.west),
        p('g_or', 'Y', PortDirection.output, SchematicPortSide.east),
      ]),
      cell('g_not', CellKind.notGate, r'$_NOT_', <SchematicPort>[
        p('g_not', 'A', PortDirection.input, SchematicPortSide.west),
        p('g_not', 'Y', PortDirection.output, SchematicPortSide.east),
      ]),
      cell('m0', CellKind.mux, r'$_MUX_', <SchematicPort>[
        p('m0', 'I0', PortDirection.input, SchematicPortSide.west),
        p('m0', 'I1', PortDirection.input, SchematicPortSide.west),
        p('m0', 'S', PortDirection.input, SchematicPortSide.west),
        p('m0', 'Y', PortDirection.output, SchematicPortSide.east),
      ]),
      cell('ff', CellKind.flipFlop, r'$_DFF_P_', <SchematicPort>[
        p('ff', 'D', PortDirection.input, SchematicPortSide.west),
        p('ff', 'Q', PortDirection.output, SchematicPortSide.east),
      ]),
    ],
    boundaryPorts: const <SchematicBoundaryPort>[
      SchematicBoundaryPort(
        id: 'port:a',
        name: 'a',
        direction: PortDirection.input,
        width: 1,
      ),
      SchematicBoundaryPort(
        id: 'port:b',
        name: 'b',
        direction: PortDirection.input,
        width: 1,
      ),
      SchematicBoundaryPort(
        id: 'port:sel',
        name: 'sel',
        direction: PortDirection.input,
        width: 1,
      ),
      SchematicBoundaryPort(
        id: 'port:q',
        name: 'q',
        direction: PortDirection.output,
        width: 1,
      ),
      SchematicBoundaryPort(
        id: 'port:ny',
        name: 'ny',
        direction: PortDirection.output,
        width: 1,
      ),
    ],
    edges: const <SchematicEdge>[
      SchematicEdge(
        id: 'e1',
        sourcePortId: 'port:a',
        targetPortId: 'g_and:A',
        netId: 1,
      ),
      SchematicEdge(
        id: 'e2',
        sourcePortId: 'port:a',
        targetPortId: 'g_or:A',
        netId: 1,
      ),
      SchematicEdge(
        id: 'e3',
        sourcePortId: 'port:a',
        targetPortId: 'g_not:A',
        netId: 1,
      ),
      SchematicEdge(
        id: 'e4',
        sourcePortId: 'port:b',
        targetPortId: 'g_and:B',
        netId: 2,
      ),
      SchematicEdge(
        id: 'e5',
        sourcePortId: 'port:b',
        targetPortId: 'g_or:B',
        netId: 2,
      ),
      SchematicEdge(
        id: 'e6',
        sourcePortId: 'g_and:Y',
        targetPortId: 'm0:I0',
        netId: 3,
      ),
      SchematicEdge(
        id: 'e7',
        sourcePortId: 'g_or:Y',
        targetPortId: 'm0:I1',
        netId: 4,
      ),
      SchematicEdge(
        id: 'e8',
        sourcePortId: 'port:sel',
        targetPortId: 'm0:S',
        netId: 5,
      ),
      SchematicEdge(
        id: 'e9',
        sourcePortId: 'm0:Y',
        targetPortId: 'ff:D',
        netId: 6,
      ),
      SchematicEdge(
        id: 'e10',
        sourcePortId: 'ff:Q',
        targetPortId: 'port:q',
        netId: 7,
      ),
      SchematicEdge(
        id: 'e11',
        sourcePortId: 'g_not:Y',
        targetPortId: 'port:ny',
        netId: 8,
      ),
    ],
  );

  BoundingBox pb(double x, double y) =>
      BoundingBox(x: x, y: y, width: 4, height: 4);
  NodePosition n(
    String id,
    double x,
    double y,
    double w,
    double h,
    Map<String, BoundingBox> ports,
  ) => NodePosition(
    id: id,
    bounds: BoundingBox(x: x, y: y, width: w, height: h),
    ports: ports,
  );

  final layout = NetlistLayout(
    nodes: <NodePosition>[
      n('g_and', 150, 40, 72, 48, {
        'g_and:A': pb(0, 12),
        'g_and:B': pb(0, 32),
        'g_and:Y': pb(68, 22),
      }),
      n('g_or', 150, 120, 72, 48, {
        'g_or:A': pb(0, 12),
        'g_or:B': pb(0, 32),
        'g_or:Y': pb(68, 22),
      }),
      n('g_not', 150, 250, 92, 44, {
        'g_not:A': pb(0, 20),
        'g_not:Y': pb(88, 20),
      }),
      n('m0', 330, 70, 64, 96, {
        'm0:I0': pb(0, 20),
        'm0:I1': pb(0, 50),
        'm0:S': pb(0, 80),
        'm0:Y': pb(60, 44),
      }),
      n('ff', 480, 84, 64, 52, {'ff:D': pb(0, 24), 'ff:Q': pb(60, 24)}),
      const NodePosition(
        id: 'port:a',
        bounds: BoundingBox(x: 10, y: 60, width: 16, height: 16),
      ),
      const NodePosition(
        id: 'port:b',
        bounds: BoundingBox(x: 10, y: 132, width: 16, height: 16),
      ),
      const NodePosition(
        id: 'port:sel',
        bounds: BoundingBox(x: 10, y: 202, width: 16, height: 16),
      ),
      const NodePosition(
        id: 'port:q',
        bounds: BoundingBox(x: 640, y: 96, width: 16, height: 16),
      ),
      const NodePosition(
        id: 'port:ny',
        bounds: BoundingBox(x: 640, y: 264, width: 16, height: 16),
      ),
    ],
    edges: const <EdgeRoute>[
      EdgeRoute(
        id: 'e1',
        points: <LayoutPoint>[
          LayoutPoint(26, 68),
          LayoutPoint(96, 68),
          LayoutPoint(96, 54),
          LayoutPoint(152, 54),
        ],
      ),
      EdgeRoute(
        id: 'e2',
        points: <LayoutPoint>[
          LayoutPoint(26, 68),
          LayoutPoint(84, 68),
          LayoutPoint(84, 134),
          LayoutPoint(152, 134),
        ],
      ),
      EdgeRoute(
        id: 'e3',
        points: <LayoutPoint>[
          LayoutPoint(26, 68),
          LayoutPoint(72, 68),
          LayoutPoint(72, 272),
          LayoutPoint(152, 272),
        ],
      ),
      EdgeRoute(
        id: 'e4',
        points: <LayoutPoint>[
          LayoutPoint(26, 140),
          LayoutPoint(120, 140),
          LayoutPoint(120, 74),
          LayoutPoint(152, 74),
        ],
      ),
      EdgeRoute(
        id: 'e5',
        points: <LayoutPoint>[
          LayoutPoint(26, 140),
          LayoutPoint(108, 140),
          LayoutPoint(108, 154),
          LayoutPoint(152, 154),
        ],
      ),
      EdgeRoute(
        id: 'e6',
        points: <LayoutPoint>[
          LayoutPoint(220, 64),
          LayoutPoint(300, 64),
          LayoutPoint(300, 92),
          LayoutPoint(332, 92),
        ],
      ),
      EdgeRoute(
        id: 'e7',
        points: <LayoutPoint>[
          LayoutPoint(220, 144),
          LayoutPoint(288, 144),
          LayoutPoint(288, 122),
          LayoutPoint(332, 122),
        ],
      ),
      EdgeRoute(
        id: 'e8',
        points: <LayoutPoint>[
          LayoutPoint(26, 210),
          LayoutPoint(312, 210),
          LayoutPoint(312, 152),
          LayoutPoint(332, 152),
        ],
      ),
      EdgeRoute(
        id: 'e9',
        points: <LayoutPoint>[
          LayoutPoint(392, 116),
          LayoutPoint(452, 116),
          LayoutPoint(452, 110),
          LayoutPoint(482, 110),
        ],
      ),
      EdgeRoute(
        id: 'e10',
        points: <LayoutPoint>[
          LayoutPoint(542, 110),
          LayoutPoint(600, 110),
          LayoutPoint(600, 104),
          LayoutPoint(640, 104),
        ],
      ),
      EdgeRoute(
        id: 'e11',
        points: <LayoutPoint>[LayoutPoint(240, 272), LayoutPoint(640, 272)],
      ),
    ],
    bounds: const BoundingBox(x: 0, y: 0, width: 672, height: 330),
  );

  return LaidOutGraph(graph: graph, layout: layout);
}

void main() {
  testWidgets('generate gate-level marketing PNG', (tester) async {
    const surface = Size(1900, 1180);
    await tester.binding.setSurfaceSize(surface);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // flutter_test renders text in the Ahem placeholder font (every glyph a
    // solid block), which turns the schematic's port/type labels into filled
    // bars. Load a real font so the labels are legible. macOS-local; guarded
    // so the harness still runs (with the fallback font) elsewhere, e.g. CI.
    var labelFamily = '';
    const fontCandidates = <String>[
      '/System/Library/Fonts/Supplemental/Arial.ttf',
      '/Library/Fonts/Arial.ttf',
    ];
    for (final path in fontCandidates) {
      final file = File(path);
      if (!file.existsSync()) continue;
      final loader = FontLoader('SchematicLabel')
        ..addFont(
          Future<ByteData>.value(
            ByteData.view(Uint8List.fromList(file.readAsBytesSync()).buffer),
          ),
        );
      await loader.load();
      labelFamily = 'SchematicLabel';
      break;
    }

    final base = NetcruxTheme.dark();
    final theme = labelFamily.isEmpty
        ? base
        : base.copyWith(
            textTheme: base.textTheme.apply(fontFamily: labelFamily),
          );
    final key = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme,
        home: Scaffold(
          body: RepaintBoundary(
            key: key,
            child: SizedBox.expand(
              child: SchematicCanvas(
                laidOut: _registerSlice(),
                // zoom >= 0.75 => detail band: symbol shapes + port/wire labels.
                transform: const ViewportTransform(
                  zoom: 2.6,
                  offset: Offset(76, 161),
                ),
                statsSink: const NoopRenderStatsSink(),
                theme: theme,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final out = File('build/gate_level.png');
      await out.create(recursive: true);
      await out.writeAsBytes(data!.buffer.asUint8List());
    });
  });
}
