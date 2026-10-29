// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/theme/netcrux_theme.dart';
import 'package:netcrux/domain/models/layout/bounding_box.dart';
import 'package:netcrux/domain/models/layout/edge_route.dart';
import 'package:netcrux/domain/models/layout/netlist_layout.dart';
import 'package:netcrux/domain/models/layout/node_position.dart';
import 'package:netcrux/domain/models/netlist/port_direction.dart';
import 'package:netcrux/domain/models/schematic/cell_kind.dart';
import 'package:netcrux/domain/models/schematic/exported_cell_symbol.dart';
import 'package:netcrux/domain/models/schematic/laid_out_graph.dart';
import 'package:netcrux/domain/models/schematic/pin_tie.dart';
import 'package:netcrux/domain/models/schematic/schematic_graph.dart';
import 'package:netcrux/domain/models/schematic/symbol_shapes.dart';
import 'package:netcrux/features/viewer/services/svg_export_palette_from_theme.dart';
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
        ports: <String, BoundingBox>{
          'u_and:Y': BoundingBox(x: 80, y: 28, width: 4, height: 4),
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
  return LaidOutGraph(graph: graph, layout: layout);
}

/// One cell of every built-in kind, each 120 by 80, in a row.
LaidOutGraph _everyKind() {
  const kinds = CellKind.values;
  return LaidOutGraph(
    graph: SchematicGraph(
      moduleName: 'top',
      cells: <SchematicCell>[
        for (final kind in kinds)
          SchematicCell(
            id: 'u_${kind.name}',
            kind: kind,
            type: '\$${kind.name}',
            ports: const <SchematicPort>[],
          ),
      ],
      boundaryPorts: const <SchematicBoundaryPort>[],
      edges: const <SchematicEdge>[],
    ),
    layout: NetlistLayout(
      nodes: <NodePosition>[
        for (var i = 0; i < kinds.length; i++)
          NodePosition(
            id: 'u_${kinds[i].name}',
            bounds: BoundingBox(x: i * 200.0, y: 0, width: 120, height: 80),
          ),
      ],
      edges: const <EdgeRoute>[],
      bounds: BoundingBox(x: 0, y: 0, width: kinds.length * 200.0, height: 80),
    ),
  );
}

/// The `<g class="cell">` group the export wrote for [kind], without its
/// opening and closing tags.
String _group(String svg, CellKind kind) {
  final match = RegExp(
    '<g class="cell" data-kind="${kind.name}" [^>]*>\\n(.*?)\\n  </g>',
    dotAll: true,
  ).firstMatch(svg);
  expect(match, isNotNull, reason: 'no group for ${kind.name}');
  return match!.group(1)!;
}

/// A graph with a single cell [cell] at [bounds], plus [extraNodes].
LaidOutGraph _single(
  SchematicCell cell,
  NodePosition position, {
  List<SchematicCell> extraCells = const <SchematicCell>[],
  List<NodePosition> extraNodes = const <NodePosition>[],
  List<SchematicBoundaryPort> boundaryPorts = const <SchematicBoundaryPort>[],
  Map<String, Set<String>> symbolCells = const <String, Set<String>>{},
}) {
  return LaidOutGraph(
    graph: SchematicGraph(
      moduleName: 'top',
      cells: <SchematicCell>[cell, ...extraCells],
      boundaryPorts: boundaryPorts,
      edges: const <SchematicEdge>[],
    ),
    layout: NetlistLayout(
      nodes: <NodePosition>[position, ...extraNodes],
      edges: const <EdgeRoute>[],
      bounds: const BoundingBox(x: 0, y: 0, width: 400, height: 300),
    ),
    symbolCells: symbolCells,
  );
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

    test('draws the cell symbol at its node, its label, the boundary port '
        'and the edge polyline', () {
      final svg = exporter.toSvg(_graph());
      expect(
        svg,
        contains(
          '<g class="cell" data-kind="andGate" '
          'transform="translate(20.00,30.00)">',
        ),
      );
      expect(svg, contains('>u_and</text>'));
      // Boundary port filled rect (the accent fill) and its name.
      expect(
        svg,
        contains(
          '<rect x="160.0" y="30.0" width="16.0" height="16.0" '
          'fill="#FFB627" />',
        ),
      );
      expect(svg, contains('>y</text>'));
      // Edge polyline with both points.
      expect(svg, contains('<polyline points="100.00,60.00 160.00,38.00"'));
    });

    test('escapes XML-special characters in cell labels', () {
      final svg = exporter.toSvg(_graph(cellLabel: 'a<b>&"c'));
      expect(svg, contains('>a&lt;b&gt;&amp;&quot;c</text>'));
      expect(svg, isNot(contains('>a<b>')));
    });

    test('a frame sets the size, the view box and the background', () {
      final svg = exporter.toSvg(
        _graph(),
        frame: const BoundingBox(x: -24, y: 10, width: 120, height: 60),
      );
      expect(svg, contains('width="120.00"'));
      expect(svg, contains('height="60.00"'));
      expect(svg, contains('viewBox="-24.00 10.00 120.00 60.00"'));
      expect(
        svg,
        contains(
          '<rect x="-24.00" y="10.00" width="120.00" height="60.00" '
          'fill="#1A1A1A" />',
        ),
      );
    });

    test('an empty graph still yields a valid (cell-free) SVG', () {
      final svg = exporter.toSvg(LaidOutGraph.empty);
      expect(svg, contains('<svg'));
      expect(svg, contains('</svg>'));
      expect(svg, isNot(contains('<polyline')));
      expect(svg, isNot(contains('</text>')));
      expect(svg, isNot(contains('class="cell"')));
    });
  });

  group('built-in symbols', () {
    final svg = exporter.toSvg(_everyKind());

    test('every kind is drawn from the shape the canvas painter draws', () {
      for (final kind in CellKind.values) {
        final expected = symbolShapeSvgElements(
          symbolShapeFor(kind, 120, 80),
          body: SvgExportPalette.dark.body,
          stroke: SvgExportPalette.dark.stroke,
        ).map((e) => '    $e').join('\n');
        expect(_group(svg, kind), expected, reason: kind.name);
      }
    });

    test('gates are drawn as their outlines, not as rectangles', () {
      for (final kind in <CellKind>[
        CellKind.andGate,
        CellKind.orGate,
        CellKind.notGate,
        CellKind.mux,
      ]) {
        expect(_group(svg, kind), isNot(contains('<rect')), reason: kind.name);
      }
    });

    test('AND: flat back and a semicircular front', () {
      // Inset 7.2 (6% of 120); the arc's radius is half the inset height.
      expect(
        _group(svg, CellKind.andGate),
        contains(
          'd="M 7.20 7.20 L 80.00 7.20 A 32.80 32.80 0 0 1 80.00 72.80 '
          'L 7.20 72.80 Z"',
        ),
      );
    });

    test('OR: concave back, two curves meeting at the tip', () {
      final group = _group(svg, CellKind.orGate);
      expect(RegExp(' Q ').allMatches(group), hasLength(3));
      // The tip: the right inset edge at mid-height.
      expect(group, contains('112.80 40.00'));
    });

    test('NOT: a triangle and its bubble', () {
      final group = _group(svg, CellKind.notGate);
      expect(
        group,
        contains('d="M 7.20 7.20 L 100.13 40.00 L 7.20 72.80 Z"'),
      );
      expect(group, contains('<circle cx="106.46" cy="40.00" r="6.34"'));
    });

    test('MUX: a trapezoid narrower on the output side', () {
      expect(
        _group(svg, CellKind.mux),
        contains(
          'd="M 7.20 7.20 L 112.80 19.01 L 112.80 60.99 L 7.20 72.80 Z"',
        ),
      );
    });

    test('flip-flop: a rounded body and an unfilled clock triangle', () {
      final group = _group(svg, CellKind.flipFlop);
      expect(group, contains('rx="4.00"'));
      expect(
        group,
        contains('d="M 7.20 56.80 L 15.04 62.40 L 7.20 68.00 Z" fill="none"'),
      );
    });

    test('latch: a rounded body and the level-sensitive bar', () {
      final group = _group(svg, CellKind.latch);
      expect(group, contains('rx="2.00"'));
      expect(
        group,
        contains(
          'd="M 7.20 37.00 L 19.20 37.00 L 19.20 43.00 L 7.20 43.00 Z" '
          'fill="none"',
        ),
      );
    });

    test('generic: a plain rectangle', () {
      final group = _group(svg, CellKind.generic);
      expect(group, startsWith('    <rect x="7.20" y="7.20"'));
      expect(group, isNot(contains('rx=')));
    });
  });

  group('pin marks', () {
    SchematicCell cell(List<SchematicPort> ports) => SchematicCell(
      id: 'u0',
      kind: CellKind.andGate,
      type: r'$and',
      ports: ports,
    );

    const position = NodePosition(
      id: 'u0',
      bounds: BoundingBox(x: 100, y: 100, width: 40, height: 30),
      ports: <String, BoundingBox>{
        'u0:A': BoundingBox(x: -4, y: 4, width: 4, height: 4),
        'u0:B': BoundingBox(x: -4, y: 20, width: 4, height: 4),
        'u0:Y': BoundingBox(x: 40, y: 13, width: 4, height: 4),
      },
    );

    final svg = exporter.toSvg(
      _single(
        cell(const <SchematicPort>[
          SchematicPort(
            id: 'u0:A',
            name: 'A',
            direction: PortDirection.input,
            side: SchematicPortSide.west,
            tie: PinTie.constant('1'),
          ),
          SchematicPort(
            id: 'u0:B',
            name: 'B',
            direction: PortDirection.input,
            side: SchematicPortSide.west,
            tie: PinTie.undriven,
          ),
          SchematicPort(
            id: 'u0:Y',
            name: 'Y',
            direction: PortDirection.output,
            side: SchematicPortSide.east,
          ),
        ]),
        position,
      ),
    );

    test('a dot on every pin', () {
      expect(RegExp('<circle class="pin"').allMatches(svg), hasLength(3));
      expect(svg, contains('<circle class="pin" cx="142.00" cy="115.00"'));
    });

    test('a constant pin gets a stub leftwards and its value', () {
      expect(
        svg,
        contains(
          '<line class="tie-stub" x1="98.00" y1="106.00" '
          'x2="89.00" y2="106.00"',
        ),
      );
      expect(
        svg,
        contains(
          '<text class="tie-label" x="88.00" y="106.00" '
          'font-family="sans-serif" font-size="8.00"',
        ),
      );
      expect(svg, contains('text-anchor="end" dominant-baseline="middle">1<'));
    });

    test('an undriven pin gets a stub ending in an open ring', () {
      expect(
        svg,
        contains(
          '<line class="tie-stub" x1="98.00" y1="122.00" '
          'x2="89.00" y2="122.00"',
        ),
      );
      expect(
        svg,
        contains(
          '<circle class="undriven-ring" cx="87.00" cy="122.00" r="2.00" '
          'fill="none"',
        ),
      );
    });
  });

  group('module port names', () {
    test('an input is named to its west, an output to its east', () {
      final svg = exporter.toSvg(
        const LaidOutGraph(
          graph: SchematicGraph(
            moduleName: 'top',
            cells: <SchematicCell>[],
            boundaryPorts: <SchematicBoundaryPort>[
              SchematicBoundaryPort(
                id: 'port:a',
                name: 'a',
                direction: PortDirection.input,
                width: 1,
              ),
              SchematicBoundaryPort(
                id: 'port:y',
                name: 'y',
                direction: PortDirection.output,
                width: 1,
              ),
            ],
            edges: <SchematicEdge>[],
          ),
          layout: NetlistLayout(
            nodes: <NodePosition>[
              NodePosition(
                id: 'port:a',
                bounds: BoundingBox(x: 50, y: 10, width: 10, height: 10),
              ),
              NodePosition(
                id: 'port:y',
                bounds: BoundingBox(x: 200, y: 10, width: 10, height: 10),
              ),
            ],
            edges: <EdgeRoute>[],
            bounds: BoundingBox(x: 0, y: 0, width: 300, height: 40),
          ),
        ),
      );
      expect(
        svg,
        contains(
          '<text class="port-label" x="46.00" y="15.00" '
          'font-family="sans-serif" font-size="11.00" fill="#E0E0E0" '
          'text-anchor="end" dominant-baseline="middle">a</text>',
        ),
      );
      expect(
        svg,
        contains(
          '<text class="port-label" x="214.00" y="15.00" '
          'font-family="sans-serif" font-size="11.00" fill="#E0E0E0" '
          'text-anchor="start" dominant-baseline="middle">y</text>',
        ),
      );
    });
  });

  group('custom symbols', () {
    const symbolCell = SchematicCell(
      id: 'u_alu',
      kind: CellKind.generic,
      type: 'alu',
      ports: <SchematicPort>[
        SchematicPort(
          id: 'u_alu:A',
          name: 'A',
          direction: PortDirection.input,
          side: SchematicPortSide.west,
        ),
        SchematicPort(
          id: 'u_alu:Q',
          name: 'Q',
          direction: PortDirection.output,
          side: SchematicPortSide.east,
        ),
      ],
    );
    const symbolNode = NodePosition(
      id: 'u_alu',
      bounds: BoundingBox(x: 100, y: 100, width: 60, height: 40),
      ports: <String, BoundingBox>{
        'u_alu:A': BoundingBox(x: -4, y: 18, width: 4, height: 4),
        'u_alu:Q': BoundingBox(x: 60, y: 18, width: 4, height: 4),
      },
    );
    const artwork =
        '<?xml version="1.0"?>\n'
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 30 20">\n'
        '<path d="M0 0 L30 10 L0 20 Z"/></svg>';

    ExportedCellSymbol? source(SchematicCell cell) =>
        cell.type == 'alu' ? const ExportedCellSymbolSvg(artwork) : null;

    test('a cell with custom artwork is drawn with that artwork, fitted to '
        'its node', () {
      final svg = exporter.toSvg(
        _single(symbolCell, symbolNode),
        customSymbols: source,
      );
      expect(
        svg,
        contains(
          '<svg class="cell custom-symbol" data-type="alu" '
          'x="100.00" y="100.00" width="60.00" height="40.00" '
          'viewBox="0 0 30.00 20.00" preserveAspectRatio="xMidYMid meet"',
        ),
      );
      expect(svg, contains('<path d="M0 0 L30 10 L0 20 Z"/>'));
      // One prolog, the document's own.
      expect(RegExp(r'<\?xml').allMatches(svg), hasLength(1));
      expect(svg, isNot(contains('class="cell" data-kind=')));
    });

    test('artwork sized in other units than its viewBox fills the cell, not '
        'a clipped corner of it', () {
      // An Inkscape drawing in millimetres: 40mm is about 151px, four times
      // the 40-unit viewBox, so a root left at width="40mm" overflows the
      // wrapper's viewBox and the wrapper clips all but its top-left part.
      const mm =
          '<svg xmlns="http://www.w3.org/2000/svg" width="40mm" '
          'height="20mm" viewBox="0 0 40 20">\n'
          '<path d="M0 0 L40 10 L0 20 Z"/></svg>';
      final svg = exporter.toSvg(
        _single(symbolCell, symbolNode),
        customSymbols: (_) => const ExportedCellSymbolSvg(mm),
      );
      expect(
        svg,
        contains(
          'width="60.00" height="40.00" viewBox="0 0 40.00 20.00" '
          'preserveAspectRatio="xMidYMid meet" overflow="hidden">\n'
          '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 40 20" '
          'width="100%" height="100%">\n<path',
        ),
      );
      expect(svg, isNot(contains('mm"')));
    });

    test('a bare numeric root size other than the viewBox is replaced too', () {
      expect(
        nestableSvgDocument(
          '<?xml version="1.0"?>\n'
          "<svg width='200' viewBox=\"0 0 40 20\" height=\"100px\" "
          'stroke-width="2"><rect width="40" height="20"/></svg>',
          idPrefix: 'cs0-',
        ),
        '<svg viewBox="0 0 40 20" stroke-width="2" width="100%" '
        'height="100%"><rect width="40" height="20"/></svg>',
      );
    });

    test('a root without a size gets one, and a self-closing root stays '
        'self-closing', () {
      expect(
        nestableSvgDocument(
          '<svg viewBox="0 0 4 2"><g/></svg>',
          idPrefix: 'cs0-',
        ),
        '<svg viewBox="0 0 4 2" width="100%" height="100%"><g/></svg>',
      );
      expect(
        nestableSvgDocument(
          '<svg viewBox="0 0 4 2" width="8" />',
          idPrefix: 'cs0-',
        ),
        '<svg viewBox="0 0 4 2" width="100%" height="100%"/>',
      );
    });

    test('ids and their references are made unique per symbol', () {
      const withDefs =
          '<svg viewBox="0 0 30 20"><defs>\n'
          '<linearGradient id="g"><stop offset="0"/></linearGradient>\n'
          "<clipPath id='c'><rect width=\"30\" height=\"20\"/></clipPath>\n"
          '</defs>\n'
          '<style>#body { fill: url(#g); } .x { fill: #fff; }</style>\n'
          '<path id="body" d="M0 0 L30 10 L0 20 Z" fill="url(#g)" '
          'clip-path="url(\'#c\')"/>\n'
          '<use href="#body"/>\n'
          '<use xlink:href="#body"/>\n'
          '<use href="#elsewhere"/></svg>';
      final svg = exporter.toSvg(
        _single(
          symbolCell,
          symbolNode,
          extraCells: const <SchematicCell>[
            SchematicCell(
              id: 'u_alu2',
              kind: CellKind.generic,
              type: 'alu',
              ports: <SchematicPort>[],
            ),
          ],
          extraNodes: const <NodePosition>[
            NodePosition(
              id: 'u_alu2',
              bounds: BoundingBox(x: 200, y: 100, width: 60, height: 40),
            ),
          ],
        ),
        customSymbols: (_) => const ExportedCellSymbolSvg(withDefs),
      );
      for (final prefix in <String>['cs0-', 'cs1-']) {
        expect(svg, contains('<linearGradient id="${prefix}g">'));
        expect(svg, contains("<clipPath id='${prefix}c'>"));
        expect(
          svg,
          contains(
            '<style>#${prefix}body { fill: url(#${prefix}g); } '
            '.x { fill: #fff; }</style>',
          ),
        );
        expect(
          svg,
          contains(
            '<path id="${prefix}body" d="M0 0 L30 10 L0 20 Z" '
            'fill="url(#${prefix}g)" clip-path="url(\'#${prefix}c\')"/>',
          ),
        );
        expect(
          svg,
          contains(
            '<use href="#${prefix}body"/>\n<use xlink:href="#${prefix}body"/>',
          ),
        );
      }
      // A reference to no id in the symbol is left alone.
      expect(svg, contains('<use href="#elsewhere"/>'));
      expect(RegExp(r'\sid="g"').allMatches(svg), isEmpty);
    });

    test('artwork that cannot be drawn falls back to the generic box', () {
      final svg = exporter.toSvg(
        _single(symbolCell.copyWithKind(CellKind.andGate), symbolNode),
        customSymbols: (_) => const ExportedCellSymbolUnrenderable(),
      );
      expect(svg, contains('<g class="cell" data-kind="andGate"'));
      expect(
        svg,
        contains(
          '    ${symbolShapeSvgElements(
            genericBoxShape(60, 40),
            body: SvgExportPalette.dark.body,
            stroke: SvgExportPalette.dark.stroke,
          ).single}',
        ),
      );
    });

    test('a symbol cell names its anchored pins inside the drawing and its '
        'label below it', () {
      final svg = exporter.toSvg(
        _single(
          symbolCell,
          symbolNode,
          symbolCells: const <String, Set<String>>{
            'u_alu': <String>{'A', 'Q'},
          },
        ),
        customSymbols: source,
      );
      expect(
        svg,
        contains(
          '<text class="pin-name" x="103.00" y="120.00" '
          'font-family="sans-serif" font-size="8.80" fill="#E0E0E0" '
          'text-anchor="start" dominant-baseline="middle">A</text>',
        ),
      );
      expect(
        svg,
        contains(
          '<text class="pin-name" x="157.00" y="120.00" '
          'font-family="sans-serif" font-size="8.80" fill="#E0E0E0" '
          'text-anchor="end" dominant-baseline="middle">Q</text>',
        ),
      );
      // Below: the node's bottom (140) plus the gap (2) plus half the label
      // height (15.4 / 2).
      expect(
        svg,
        contains('<text class="cell-label" x="130.00" y="149.70" '),
      );
    });

    test('the outside label goes above when a neighbour sits below', () {
      final svg = exporter.toSvg(
        _single(
          symbolCell,
          symbolNode,
          extraNodes: const <NodePosition>[
            NodePosition(
              id: 'u_below',
              bounds: BoundingBox(x: 100, y: 145, width: 60, height: 40),
            ),
          ],
          symbolCells: const <String, Set<String>>{
            'u_alu': <String>{},
          },
        ),
        customSymbols: source,
      );
      // Above: the node's top (100) less the gap (2) less half the label
      // height.
      expect(
        svg,
        contains('<text class="cell-label" x="130.00" y="90.30" '),
      );
    });
  });

  group('svgExportPaletteFromTheme', () {
    test('takes each mark from the canvas theme role', () {
      final theme = NetcruxTheme.light();
      final scheme = theme.colorScheme;
      final palette = svgExportPaletteFromTheme(theme);
      expect(palette.background, cssHexColor(scheme.surface));
      expect(palette.body, cssHexColor(scheme.surfaceContainerHighest));
      expect(palette.stroke, cssHexColor(scheme.onSurface));
      expect(palette.wire, cssHexColor(scheme.onSurfaceVariant));
      expect(palette.port, cssHexColor(scheme.tertiary));
      expect(palette.pin, cssHexColor(scheme.primary));
      expect(palette.undriven, cssHexColor(scheme.error));
    });

    test('cssHexColor writes #RRGGBB', () {
      expect(cssHexColor(const Color(0xFF0A1B2C)), '#0A1B2C');
      expect(cssHexColor(const Color(0x800A1B2C)), '#0A1B2C');
    });
  });

  group('label fitting', () {
    test('fitLabel keeps a short label and shortens a long one', () {
      expect(fitLabel('u0', 100, 10), 'u0');
      // 60 / (10 * 0.6) = 10 characters of room, one of them the ellipsis.
      expect(
        fitLabel('top.u_core.u_alu', 60, 10, elideStart: true),
        '\u2026ore.u_alu',
      );
      expect(fitLabel('top.u_core.u_alu', 60, 10), 'top.u_cor\u2026');
    });

    test('a long cell name keeps its tail, with the full name as its '
        'tooltip', () {
      final svg = exporter.toSvg(
        _graph(cellLabel: r'$and$/work/rtl/top.v:20$6'),
      );
      expect(
        svg,
        contains(
          '>\u2026op.v:20\$6<title>\$and\$/work/rtl/top.v:20\$6</title></text>',
        ),
      );
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

extension on SchematicCell {
  SchematicCell copyWithKind(CellKind kind) =>
      SchematicCell(id: id, kind: kind, type: type, label: label, ports: ports);
}
