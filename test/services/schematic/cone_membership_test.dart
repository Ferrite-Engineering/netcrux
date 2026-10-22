// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/interfaces/cone_of_influence_service.dart';
import 'package:netcrux/domain/models/layout/bounding_box.dart';
import 'package:netcrux/domain/models/layout/edge_route.dart';
import 'package:netcrux/domain/models/layout/netlist_layout.dart';
import 'package:netcrux/domain/models/layout/node_position.dart';
import 'package:netcrux/domain/models/netlist/port_direction.dart';
import 'package:netcrux/domain/models/schematic/cell_kind.dart';
import 'package:netcrux/domain/models/schematic/laid_out_graph.dart';
import 'package:netcrux/domain/models/schematic/schematic_graph.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/domain/models/trace/cone_view.dart';
import 'package:netcrux/domain/models/trace/trace_overlay.dart';
import 'package:netcrux/services/schematic/cone_membership.dart';
import 'package:netcrux/services/schematic/trace_service.dart';

SchematicCell _cell(String id, List<String> inputs, List<String> outputs) =>
    SchematicCell(
      id: id,
      kind: CellKind.generic,
      type: r'$cell',
      ports: <SchematicPort>[
        for (final p in inputs)
          SchematicPort(
            id: '$id:$p',
            name: p,
            direction: PortDirection.input,
            side: SchematicPortSide.west,
          ),
        for (final p in outputs)
          SchematicPort(
            id: '$id:$p',
            name: p,
            direction: PortDirection.output,
            side: SchematicPortSide.east,
          ),
      ],
    );

SchematicBoundaryPort _port(String name, PortDirection direction) =>
    SchematicBoundaryPort(
      id: 'port:$name',
      name: name,
      direction: direction,
      width: 1,
    );

SchematicEdge _edge(String id, String from, String to) =>
    SchematicEdge(id: id, sourcePortId: from, targetPortId: to, netId: 0);

/// a, b -> g1 -> g2 -> g3 -> y, with a register ff that g3 feeds back into
/// and that drives g3's second input, clocked from the clk port:
///
///     a --e1--> g1:A        g1:Y --e3--> g2:A     g2:Y --e4--> g3:A
///     b --e2--> g1:B        ff:Q --e5--> g3:B     g3:Y --e6--> y
///     g3:Y --e7--> ff:D     clk --e8--> ff:C
final _graph = SchematicGraph(
  moduleName: 'top',
  cells: <SchematicCell>[
    _cell('g1', <String>['A', 'B'], <String>['Y']),
    _cell('g2', <String>['A'], <String>['Y']),
    _cell('g3', <String>['A', 'B'], <String>['Y']),
    _cell('ff', <String>['D', 'C'], <String>['Q']),
  ],
  boundaryPorts: <SchematicBoundaryPort>[
    _port('a', PortDirection.input),
    _port('b', PortDirection.input),
    _port('clk', PortDirection.input),
    _port('y', PortDirection.output),
  ],
  edges: <SchematicEdge>[
    _edge('e1', 'port:a', 'g1:A'),
    _edge('e2', 'port:b', 'g1:B'),
    _edge('e3', 'g1:Y', 'g2:A'),
    _edge('e4', 'g2:Y', 'g3:A'),
    _edge('e5', 'ff:Q', 'g3:B'),
    _edge('e6', 'g3:Y', 'port:y'),
    _edge('e7', 'g3:Y', 'ff:D'),
    _edge('e8', 'port:clk', 'ff:C'),
  ],
);

const _g3 = SelectedElement.cell(cellId: 'g3');

void main() {
  group('coneMembership', () {
    test('one level of fan-in is the cells that drive the root', () {
      final cone = coneMembership(
        _graph,
        _g3,
        mode: ConeOfInfluenceMode.fanin,
        depth: 1,
      );
      expect(cone.highlightedCellIds, <String>{'g3', 'g2', 'ff'});
      expect(cone.highlightedEdgeIds, <String>{'e4', 'e5'});
      expect(cone.highlightedBoundaryPortIds, isEmpty);
      expect(cone.mode, TraceOverlayMode.fanin);
    });

    test('each further level steps through the cells reached', () {
      final two = coneMembership(
        _graph,
        _g3,
        mode: ConeOfInfluenceMode.fanin,
        depth: 2,
      );
      expect(two.highlightedCellIds, <String>{'g3', 'g2', 'ff', 'g1'});
      expect(two.highlightedBoundaryPortIds, <String>{'port:clk'});
      expect(two.highlightedEdgeIds, <String>{'e4', 'e5', 'e3', 'e7', 'e8'});
      final three = coneMembership(
        _graph,
        _g3,
        mode: ConeOfInfluenceMode.fanin,
        depth: 3,
      );
      expect(three.highlightedBoundaryPortIds, <String>{
        'port:clk',
        'port:a',
        'port:b',
      });
    });

    test('a deep enough walk stops at the boundary and settles', () {
      final deep = coneMembership(
        _graph,
        _g3,
        mode: ConeOfInfluenceMode.fanin,
        depth: 50,
      );
      expect(
        deep,
        coneMembership(
          _graph,
          _g3,
          mode: ConeOfInfluenceMode.fanin,
          depth: 3,
        ),
      );
    });

    test('fan-out follows wires out of the frontier', () {
      final cone = coneMembership(
        _graph,
        const SelectedElement.cell(cellId: 'g1'),
        mode: ConeOfInfluenceMode.fanout,
        depth: 2,
      );
      expect(cone.highlightedCellIds, <String>{'g1', 'g2', 'g3'});
      expect(cone.highlightedEdgeIds, <String>{'e3', 'e4'});
      expect(cone.mode, TraceOverlayMode.fanout);
    });

    test('a wire grows from both of its ends', () {
      final cone = coneMembership(
        _graph,
        const SelectedElement.wire(edgeId: 'e3', netId: 0),
        mode: ConeOfInfluenceMode.fanin,
        depth: 1,
      );
      expect(cone.highlightedCellIds, <String>{'g1', 'g2'});
      expect(cone.highlightedEdgeIds, <String>{'e3'});
    });

    test('a boundary port grows from itself', () {
      final cone = coneMembership(
        _graph,
        const SelectedElement.boundaryPort(portId: 'port:y', portName: 'y'),
        mode: ConeOfInfluenceMode.fanin,
        depth: 1,
      );
      expect(cone.highlightedBoundaryPortIds, <String>{'port:y'});
      expect(cone.highlightedCellIds, <String>{'g3'});
      expect(cone.highlightedEdgeIds, <String>{'e6'});
    });

    test('a pin grows from that pin only', () {
      final cone = coneMembership(
        _graph,
        const SelectedElement.port(
          cellId: 'g3',
          portId: 'g3:B',
          portName: 'B',
        ),
        mode: ConeOfInfluenceMode.fanin,
        depth: 1,
      );
      expect(cone.highlightedCellIds, <String>{'g3', 'ff'});
      expect(cone.highlightedEdgeIds, <String>{'e5'});
    });

    test('a level takes the wires in graph order', () {
      // s.Y2 -> m.A (e0), s.Y1 -> m.B (e1), m.B -> t.A (e2), with m.B a
      // bidirectional pin. e0 comes first, so reaching m.A steps through m
      // and puts m.B in the next frontier before e1 reaches it: t is two
      // levels out. Taken in frontier order (s.Y1 first) m.B would be
      // reached directly and t never.
      SchematicPort pin(String id, SchematicPortSide side) => SchematicPort(
        id: id,
        name: id.split(':').last,
        direction: side == SchematicPortSide.east
            ? PortDirection.output
            : PortDirection.input,
        side: side,
      );
      final graph = SchematicGraph(
        moduleName: 'double_reach',
        cells: <SchematicCell>[
          SchematicCell(
            id: 's',
            kind: CellKind.generic,
            type: 'g',
            ports: <SchematicPort>[
              pin('s:Y1', SchematicPortSide.east),
              pin('s:Y2', SchematicPortSide.east),
            ],
          ),
          SchematicCell(
            id: 'm',
            kind: CellKind.generic,
            type: 'g',
            ports: <SchematicPort>[
              pin('m:A', SchematicPortSide.west),
              pin('m:B', SchematicPortSide.south),
            ],
          ),
          SchematicCell(
            id: 't',
            kind: CellKind.generic,
            type: 'g',
            ports: <SchematicPort>[pin('t:A', SchematicPortSide.west)],
          ),
        ],
        boundaryPorts: const <SchematicBoundaryPort>[],
        edges: <SchematicEdge>[
          _edge('e0', 's:Y2', 'm:A'),
          _edge('e1', 's:Y1', 'm:B'),
          _edge('e2', 'm:B', 't:A'),
        ],
      );
      final cone = coneMembership(
        graph,
        const SelectedElement.cell(cellId: 's'),
        mode: ConeOfInfluenceMode.fanout,
        depth: 2,
      );
      expect(cone.highlightedCellIds, <String>{'s', 'm', 't'});
    });

    test('zero levels is the root alone', () {
      final cone = coneMembership(
        _graph,
        _g3,
        mode: ConeOfInfluenceMode.fanin,
        depth: 0,
      );
      expect(cone.highlightedCellIds, <String>{'g3'});
      expect(cone.highlightedEdgeIds, isEmpty);
    });

    test('a root the scope does not hold is that root alone', () {
      final cone = coneMembership(
        _graph,
        const SelectedElement.cell(cellId: 'gone'),
        mode: ConeOfInfluenceMode.fanin,
        depth: 3,
      );
      expect(cone.highlightedCellIds, <String>{'gone'});
      expect(cone.highlightedEdgeIds, isEmpty);
    });

    test('one level reaches what the one-step trace lights', () {
      // The trace service is the open-core fan-in and fan-out the one-level
      // cone view stands beside; the two must agree on every root.
      final laidOut = LaidOutGraph(
        graph: _graph,
        layout: NetlistLayout(
          nodes: <NodePosition>[
            for (final c in _graph.cells)
              NodePosition(
                id: c.id,
                bounds: const BoundingBox(x: 0, y: 0, width: 1, height: 1),
              ),
          ],
          edges: const <EdgeRoute>[],
          bounds: const BoundingBox(x: 0, y: 0, width: 1, height: 1),
        ),
      );
      final roots = <SelectedElement>[
        for (final c in _graph.cells) SelectedElement.cell(cellId: c.id),
        for (final e in _graph.edges)
          SelectedElement.wire(edgeId: e.id, netId: 0),
      ];
      for (final root in roots) {
        for (final (mode, traceMode)
            in <(ConeOfInfluenceMode, TraceOverlayMode)>[
              (ConeOfInfluenceMode.fanin, TraceOverlayMode.fanin),
              (ConeOfInfluenceMode.fanout, TraceOverlayMode.fanout),
            ]) {
          final cone = coneMembership(_graph, root, mode: mode, depth: 1);
          final trace = const TraceService().compute(
            laidOut: laidOut,
            selection: root,
            mode: traceMode,
          );
          expect(
            cone.highlightedCellIds,
            trace.highlightedCellIds,
            reason: '$root $mode',
          );
          expect(
            cone.highlightedEdgeIds,
            trace.highlightedEdgeIds,
            reason: '$root $mode',
          );
          expect(
            cone.highlightedBoundaryPortIds,
            trace.highlightedBoundaryPortIds,
            reason: '$root $mode',
          );
        }
      }
    });
  });

  group('coneViewMembership', () {
    test('fan-in alone is the fan-in walk', () {
      expect(
        coneViewMembership(
          _graph,
          _g3,
          direction: ConeViewDirection.fanIn,
          depth: 1,
        ),
        coneMembership(
          _graph,
          _g3,
          mode: ConeOfInfluenceMode.fanin,
          depth: 1,
        ),
      );
    });

    test('fan-in and fan-out is the union of both walks', () {
      final both = coneViewMembership(
        const SchematicGraph(
          moduleName: 'top',
          cells: <SchematicCell>[],
          boundaryPorts: <SchematicBoundaryPort>[],
          edges: <SchematicEdge>[],
        ),
        _g3,
        direction: ConeViewDirection.fanInAndFanOut,
        depth: 1,
      );
      expect(both.highlightedCellIds, <String>{'g3'});
      final cone = coneViewMembership(
        _graph,
        const SelectedElement.cell(cellId: 'g2'),
        direction: ConeViewDirection.fanInAndFanOut,
        depth: 1,
      );
      expect(cone.highlightedCellIds, <String>{'g1', 'g2', 'g3'});
      expect(cone.highlightedEdgeIds, <String>{'e3', 'e4'});
    });
  });

  group('coneSubgraph', () {
    test('keeps the members and every wire between two of them', () {
      final sub = coneSubgraph(
        _graph,
        const TraceOverlay(
          mode: TraceOverlayMode.fanin,
          highlightedCellIds: <String>{'g2', 'g3', 'ff'},
          highlightedEdgeIds: <String>{'e4'},
          highlightedBoundaryPortIds: <String>{'port:y'},
        ),
      );
      expect(sub.moduleName, 'top');
      expect(sub.cells.map((c) => c.id), <String>['g2', 'g3', 'ff']);
      expect(sub.boundaryPorts.map((b) => b.id), <String>['port:y']);
      // e5 and e7 were not walked but join two members, so they are drawn.
      expect(sub.edges.map((e) => e.id), <String>['e4', 'e5', 'e6', 'e7']);
      expect(sub.cells.first, _graph.cells[1]);
    });

    test('an empty cone is an empty graph', () {
      final sub = coneSubgraph(_graph, TraceOverlay.empty);
      expect(sub.isEmpty, isTrue);
    });
  });

  group('unionConeMembership', () {
    test('joins every set and keeps the first mode', () {
      final union = unionConeMembership(
        const TraceOverlay(
          mode: TraceOverlayMode.fanin,
          highlightedCellIds: <String>{'a'},
          highlightedEdgeIds: <String>{'e1'},
          highlightedBoundaryPortIds: <String>{},
        ),
        const TraceOverlay(
          mode: TraceOverlayMode.fanout,
          highlightedCellIds: <String>{'b'},
          highlightedEdgeIds: <String>{},
          highlightedBoundaryPortIds: <String>{'port:p'},
        ),
      );
      expect(union.mode, TraceOverlayMode.fanin);
      expect(union.highlightedCellIds, <String>{'a', 'b'});
      expect(union.highlightedEdgeIds, <String>{'e1'});
      expect(union.highlightedBoundaryPortIds, <String>{'port:p'});
    });
  });
}
