// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:netcrux/domain/models/layout/bounding_box.dart';
import 'package:netcrux/domain/models/layout/netlist_layout.dart';
import 'package:netcrux/domain/models/layout/node_position.dart';
import 'package:netcrux/domain/models/netlist/bit_ref.dart';
import 'package:netcrux/domain/models/netlist/cell.dart';
import 'package:netcrux/domain/models/netlist/hierarchy_node.dart';
import 'package:netcrux/domain/models/netlist/module.dart';
import 'package:netcrux/domain/models/netlist/net.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/netlist/port.dart';
import 'package:netcrux/domain/models/netlist/port_direction.dart';
import 'package:netcrux/domain/models/schematic/laid_out_graph.dart';
import 'package:netcrux/services/schematic/schematic_graph_builder.dart';

/// Where [formalFlowDesign]'s sources sit, as Yosys's `src` attributes name
/// them. Tests that read a property write the files there.
const String kFormalFlowTopFile = 'rtl/top.sv';

/// See [kFormalFlowTopFile].
const String kFormalFlowSubFile = 'rtl/sub.sv';

Cell _cell(
  String name,
  String type,
  Map<String, (PortDirection, List<int>)> pins,
) => Cell(
  name: name,
  type: type,
  parameters: const <String, String>{},
  attributes: const <String, String>{},
  portDirections: <String, PortDirection>{
    for (final e in pins.entries) e.key: e.value.$1,
  },
  connections: <String, List<BitRef>>{
    for (final e in pins.entries)
      e.key: <BitRef>[for (final b in e.value.$2) NetBit(b)],
  },
);

Net _net(String name, List<int> bits) => Net(
  name: name,
  bits: <BitRef>[for (final b in bits) NetBit(b)],
  attributes: const <String, String>{},
);

Port _port(String name, PortDirection direction, List<int> bits) => Port(
  name: name,
  direction: direction,
  bits: <BitRef>[for (final b in bits) NetBit(b)],
);

/// A two-level design with the names real elaborations produce, written by
/// hand from the RTL it stands for (never captured from NetCrux):
///
/// ```verilog
/// module top(input clk, input wr_en, output full);   // rtl/top.sv:1-40
///   reg [1:0] cnt_q;  wire [1:0] d_next = cnt_q & {2{wr_en}};
///   always @(posedge clk) cnt_q <= d_next;           // cnt_reg
///   always @(posedge clk) full <= cnt_q[0];          // full_reg
///   sub u_sub(.i(cnt_q[0]), .o(sub_o));
///   reg \esc.q ;  always @(posedge clk) \esc.q <= sub_o;   // esc_reg
///   p_full: assert property (@(posedge clk) wr_en |-> ##1 !full);  // line 20
///   p_sub:  assert property (@(posedge clk) u_sub.state |-> cnt_q[0]); // 22
/// endmodule
/// module sub(input i, output o);                     // rtl/sub.sv:1-10
///   reg state; always @(posedge clk) state <= i; assign o = state;
/// endmodule
/// ```
///
/// Bits: clk 1, full 2, wr_en 3, cnt_q 4 and 8, d_next 5 and 9, sub_o 6,
/// `esc.q` 7. In `sub`: i 2, state and o 3.
NetlistModel formalFlowDesign({String srcRoot = '/abs/design'}) {
  final top = Module(
    name: 'top',
    attributes: <String, String>{
      'top': '1',
      'src': '$srcRoot/$kFormalFlowTopFile:1.1-40.10',
    },
    ports: <String, Port>{
      'clk': _port('clk', PortDirection.input, <int>[1]),
      'wr_en': _port('wr_en', PortDirection.input, <int>[3]),
      'full': _port('full', PortDirection.output, <int>[2]),
    },
    cells: <String, Cell>{
      'cnt_reg': _cell('cnt_reg', r'$dff', {
        'CLK': (PortDirection.input, <int>[1]),
        'D': (PortDirection.input, <int>[5, 9]),
        'Q': (PortDirection.output, <int>[4, 8]),
      }),
      'g1': _cell('g1', r'$and', {
        'A': (PortDirection.input, <int>[4, 8]),
        'B': (PortDirection.input, <int>[3, 3]),
        'Y': (PortDirection.output, <int>[5, 9]),
      }),
      'full_reg': _cell('full_reg', r'$dff', {
        'CLK': (PortDirection.input, <int>[1]),
        'D': (PortDirection.input, <int>[4]),
        'Q': (PortDirection.output, <int>[2]),
      }),
      'u_sub': _cell('u_sub', 'sub', {
        'i': (PortDirection.input, <int>[4]),
        'o': (PortDirection.output, <int>[6]),
      }),
      'esc_reg': _cell('esc_reg', r'$dff', {
        'CLK': (PortDirection.input, <int>[1]),
        'D': (PortDirection.input, <int>[6]),
        'Q': (PortDirection.output, <int>[7]),
      }),
    },
    nets: <String, Net>{
      'clk': _net('clk', <int>[1]),
      'full': _net('full', <int>[2]),
      'wr_en': _net('wr_en', <int>[3]),
      'cnt_q': _net('cnt_q', <int>[4, 8]),
      'd_next': _net('d_next', <int>[5, 9]),
      'sub_o': _net('sub_o', <int>[6]),
      'esc.q': _net('esc.q', <int>[7]),
    },
  );
  final sub = Module(
    name: 'sub',
    attributes: <String, String>{
      'src': '$srcRoot/$kFormalFlowSubFile:1.1-10.10',
    },
    ports: <String, Port>{
      'i': _port('i', PortDirection.input, <int>[2]),
      'o': _port('o', PortDirection.output, <int>[3]),
    },
    cells: <String, Cell>{
      'state_reg': _cell('state_reg', r'$dff', {
        'D': (PortDirection.input, <int>[2]),
        'Q': (PortDirection.output, <int>[3]),
      }),
    },
    nets: <String, Net>{
      'i': _net('i', <int>[2]),
      'state': _net('state', <int>[3]),
      'o': _net('o', <int>[3]),
    },
  );
  return NetlistModel(
    creator: 'hand-written',
    modules: <String, Module>{'top': top, 'sub': sub},
  );
}

/// [scope] of [model] laid out: the schematic NetCrux builds for it, with a
/// node per cell. Positions are irrelevant to the tests that use it.
LaidOutGraph laidOutScope(NetlistModel model, HierarchyNode scope) {
  final graph = const SchematicGraphBuilder().build(model, scope);
  return LaidOutGraph(
    graph: graph,
    layout: NetlistLayout(
      nodes: <NodePosition>[
        for (final cell in graph.cells)
          NodePosition(
            id: cell.id,
            bounds: const BoundingBox(x: 0, y: 0, width: 1, height: 1),
          ),
      ],
      edges: const [],
      bounds: const BoundingBox(x: 0, y: 0, width: 10, height: 10),
    ),
  );
}

/// The RTL [formalFlowDesign] stands for, as text: what a property's
/// `<file>:<line>` names. Lines are 1-based; line 20 holds `p_full` and
/// line 22 `p_sub`.
String formalFlowTopSource() {
  final lines = List<String>.filled(40, '');
  lines[0] = 'module top(input clk, input wr_en, output reg full);';
  lines[19] =
      '  p_full: assert property (@(posedge clk) wr_en |-> ##1 !full); '
      r'// $past(cnt_q) is not read';
  lines[21] = '  p_sub: assert property (@(posedge clk)';
  lines[22] = '    u_sub.state |-> cnt_q[0]);';
  lines[39] = 'endmodule';
  return '${lines.join('\n')}\n';
}
