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
import 'package:netcrux/features/viewer/selection/schematic_keyboard_navigator.dart';

SchematicPort _pin(String cell, String name, PortDirection direction) =>
    SchematicPort(
      id: '$cell:$name',
      name: name,
      direction: direction,
      side: direction == PortDirection.output
          ? SchematicPortSide.east
          : SchematicPortSide.west,
    );

/// Two gates side by side on the top row and a clock port below them,
/// declared out of reading order so the sort is what puts them in it.
///
/// `clk` drives `u_a.A` (net 5); `u_a.Y` drives `u_b.A` and `u_b.B` (net 7,
/// two wires, one net); `u_b.Y` is unconnected.
LaidOutGraph _graph() => LaidOutGraph(
  graph: SchematicGraph(
    moduleName: 'top',
    cells: <SchematicCell>[
      SchematicCell(
        id: 'u_b',
        kind: CellKind.andGate,
        type: r'$and',
        ports: <SchematicPort>[
          _pin('u_b', 'A', PortDirection.input),
          _pin('u_b', 'B', PortDirection.input),
          _pin('u_b', 'Y', PortDirection.output),
        ],
      ),
      SchematicCell(
        id: 'u_a',
        kind: CellKind.notGate,
        type: r'$not',
        ports: <SchematicPort>[
          _pin('u_a', 'A', PortDirection.input),
          _pin('u_a', 'Y', PortDirection.output),
        ],
      ),
    ],
    boundaryPorts: const <SchematicBoundaryPort>[
      SchematicBoundaryPort(
        id: 'port:clk',
        name: 'clk',
        direction: PortDirection.input,
        width: 1,
      ),
    ],
    edges: const <SchematicEdge>[
      SchematicEdge(
        id: 'e0',
        sourcePortId: 'port:clk',
        targetPortId: 'u_a:A',
        netId: 5,
      ),
      SchematicEdge(
        id: 'e1',
        sourcePortId: 'u_a:Y',
        targetPortId: 'u_b:A',
        netId: 7,
      ),
      SchematicEdge(
        id: 'e2',
        sourcePortId: 'u_a:Y',
        targetPortId: 'u_b:B',
        netId: 7,
      ),
    ],
  ),
  layout: const NetlistLayout(
    nodes: <NodePosition>[
      NodePosition(
        id: 'u_b',
        bounds: BoundingBox(x: 300, y: 10, width: 60, height: 40),
      ),
      NodePosition(
        id: 'u_a',
        bounds: BoundingBox(x: 100, y: 10, width: 60, height: 40),
      ),
      NodePosition(
        id: 'port:clk',
        bounds: BoundingBox(x: 10, y: 200, width: 10, height: 10),
      ),
    ],
    edges: <EdgeRoute>[],
    bounds: BoundingBox(x: 0, y: 0, width: 400, height: 300),
  ),
);

const _uA = SelectedElement.cell(cellId: 'u_a');
const _uB = SelectedElement.cell(cellId: 'u_b');
const _clk = SelectedElement.boundaryPort(portId: 'port:clk', portName: 'clk');

void main() {
  final navigator = SchematicKeyboardNavigator(_graph());

  group('stepElement', () {
    test('walks cells and ports in reading order, wrapping', () {
      expect(navigator.elements, <SelectedElement>[_uA, _uB, _clk]);
      expect(navigator.stepElement(_uA, forward: true), _uB);
      expect(navigator.stepElement(_clk, forward: true), _uA);
      expect(navigator.stepElement(_uA, forward: false), _clk);
    });

    test('starts at either end with nothing selected', () {
      const none = SelectedElement.none();
      expect(navigator.stepElement(none, forward: true), _uA);
      expect(navigator.stepElement(none, forward: false), _clk);
    });

    test('a pin or a wire steps from the element it belongs to', () {
      const pin = SelectedElement.port(
        cellId: 'u_a',
        portId: 'u_a:Y',
        portName: 'Y',
      );
      const wire = SelectedElement.wire(edgeId: 'e0', netId: 5);
      expect(navigator.stepElement(pin, forward: true), _uB);
      // e0 is driven by the clock port.
      expect(navigator.stepElement(wire, forward: true), _uA);
    });

    test('an empty scope has nothing to step to', () {
      expect(
        const SchematicKeyboardNavigator(
          LaidOutGraph.empty,
        ).stepElement(_uA, forward: true),
        const SelectedElement.none(),
      );
    });
  });

  group('stepConnection', () {
    SelectedElement pin(String cell, String name) => SelectedElement.port(
      cellId: cell,
      portId: '$cell:$name',
      portName: name,
    );
    const net5 = SelectedElement.wire(edgeId: 'e0', netId: 5);
    const net7 = SelectedElement.wire(edgeId: 'e1', netId: 7);

    test('each pin in declaration order, followed by the net on it', () {
      expect(navigator.connectionsOf(_uA), <SelectedElement>[
        pin('u_a', 'A'),
        net5,
        pin('u_a', 'Y'),
        net7,
      ]);
      // u_b.A and u_b.B share net 7, so it appears once, after A; u_b.Y is
      // unconnected and is a pin with no net after it.
      expect(navigator.connectionsOf(_uB), <SelectedElement>[
        pin('u_b', 'A'),
        net7,
        pin('u_b', 'B'),
        pin('u_b', 'Y'),
      ]);
      // A module port is a pin already: its walk is its net.
      expect(navigator.connectionsOf(_clk), <SelectedElement>[net5]);
    });

    test('steps from the anchor itself through pins and nets, wrapping', () {
      var current = navigator.stepConnection(_uA, _uA, forward: true);
      final visited = <SelectedElement>[current];
      for (var i = 0; i < 4; i++) {
        current = navigator.stepConnection(current, _uA, forward: true);
        visited.add(current);
      }
      expect(visited, <SelectedElement>[
        pin('u_a', 'A'),
        net5,
        pin('u_a', 'Y'),
        net7,
        pin('u_a', 'A'),
      ]);
      expect(navigator.stepConnection(_uA, _uA, forward: false), net7);
      expect(
        navigator.stepConnection(net5, _uA, forward: false),
        pin('u_a', 'A'),
      );
    });

    test('a wire is found by its net, whichever of its wires is selected', () {
      const otherWireOfNet7 = SelectedElement.wire(edgeId: 'e2', netId: 7);
      expect(
        navigator.stepConnection(otherWireOfNet7, _uB, forward: true),
        pin('u_b', 'B'),
      );
    });

    test('an anchor with no pins and no nets yields none', () {
      const lonely = SchematicKeyboardNavigator(LaidOutGraph.empty);
      expect(
        lonely.stepConnection(_uA, _uA, forward: true),
        const SelectedElement.none(),
      );
    });
  });

  test('anchorFor and boundsOf follow a pin to its cell, a wire to its '
      'driver', () {
    const pin = SelectedElement.port(
      cellId: 'u_b',
      portId: 'u_b:A',
      portName: 'A',
    );
    const wire = SelectedElement.wire(edgeId: 'e1', netId: 7);
    expect(navigator.anchorFor(pin), _uB);
    expect(navigator.anchorFor(wire), _uA);
    expect(
      navigator.boundsOf(wire),
      const BoundingBox(x: 100, y: 10, width: 60, height: 40),
    );
    expect(navigator.boundsOf(const SelectedElement.none()), isNull);
  });
}
