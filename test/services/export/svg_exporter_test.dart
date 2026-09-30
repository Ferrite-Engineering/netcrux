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
import 'package:netcrux/services/export/svg_exporter.dart';

LaidOutGraph _graph({String cellLabel = 'u_and'}) {
  final graph = SchematicGraph(
    moduleName: 'top',
    cells: <SchematicCell>[
      SchematicCell(
        id: 'u_and',
        kind: CellKind.andGate,
        type: r'$and',
        label: cellLabel,
        ports: const <SchematicPort>[
          SchematicPort(
            id: 'u_and:Y',
            name: 'Y',
            direction: PortDirection.output,
            side: SchematicPortSide.east,
          ),
        ],
      ),
    ],
    boundaryPorts: const <SchematicBoundaryPort>[
      SchematicBoundaryPort(
        id: 'port:y',
        name: 'y',
        direction: PortDirection.output,
        width: 1,
      ),
    ],
    edges: const <SchematicEdge>[
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
  return LaidOutGraph(graph: graph, layout: layout);
}

void main() {
  const exporter = SvgExporter();

  group('SvgExporter.toSvg', () {
    test('emits a well-formed SVG document with sized root', () {
      final svg = exporter.toSvg(_graph());
      expect(svg, startsWith('<?xml version="1.0" encoding="UTF-8"?>'));
      expect(svg, contains('<svg xmlns="http://www.w3.org/2000/svg"'));
      expect(svg, contains('width="200.00"'));
      expect(svg, contains('height="120.00"'));
      expect(svg, contains('viewBox="0 0 200.00 120.00"'));
      expect(svg.trimRight(), endsWith('</svg>'));
    });

    test('renders one cell rect + label, boundary port rect, and edge '
        'polyline', () {
      final svg = exporter.toSvg(_graph());
      // Cell rect at the node position + its label.
      expect(svg, contains('<rect x="20.0" y="30.0" width="80.0"'));
      expect(svg, contains('>u_and</text>'));
      // Boundary port filled rect (the accent fill).
      expect(svg, contains('fill="#FFB627"'));
      // Edge polyline with both points.
      expect(svg, contains('<polyline points="100.00,60.00 160.00,38.00"'));
    });

    test('escapes XML-special characters in cell labels', () {
      final svg = exporter.toSvg(_graph(cellLabel: 'a<b>&"c'));
      expect(svg, contains('>a&lt;b&gt;&amp;&quot;c</text>'));
      expect(svg, isNot(contains('>a<b>')));
    });

    test('an empty graph still yields a valid (cell-free) SVG', () {
      final svg = exporter.toSvg(LaidOutGraph.empty);
      expect(svg, contains('<svg'));
      expect(svg, contains('</svg>'));
      expect(svg, isNot(contains('<polyline')));
      expect(svg, isNot(contains('</text>')));
    });
  });

  group('svgEscape', () {
    test('escapes &, <, >, and "', () {
      expect(svgEscape('a&b<c>d"e'), 'a&amp;b&lt;c&gt;d&quot;e');
    });

    test('leaves plain text untouched', () {
      expect(svgEscape('plain_label'), 'plain_label');
    });

    test('ampersand is escaped before entities compound', () {
      // A pre-existing entity-looking string must double-escape its `&`.
      expect(svgEscape('&lt;'), '&amp;lt;');
    });
  });
}
