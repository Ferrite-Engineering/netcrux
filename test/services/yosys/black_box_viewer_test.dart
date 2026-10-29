// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/netlist/hierarchy_node.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/schematic/schematic_graph.dart';
import 'package:netcrux/services/layout/elk_layout_service.dart';
import 'package:netcrux/services/layout/native_elk_solver.dart';
import 'package:netcrux/services/schematic/schematic_graph_builder.dart';
import 'package:netcrux/services/search/design_search_service.dart';
import 'package:netcrux/services/yosys/black_box_port_inference.dart';
import 'package:netcrux/services/yosys/streaming_yosys_json_reader.dart';

import '../../helpers/elk_ffi_library_gate.dart';

/// `write_json` from Yosys 0.69, `hierarchy` without `-check`, for (cell and
/// net attributes dropped):
///
/// ```verilog
/// module top(input a, input b, input clk, output y, output [1:0] z);
///   wire n1, n2;
///   wire [1:0] bus;
///   INV u1 (.A(a), .Y(n1), .VDD(1'b1), .VSS(1'b0));
///   NAND2 u2 (.A(n1), .B(b), .Y(n2));
///   DFF u3 (clk, n2, y);
///   MACRO m1 (.D(bus), .Q(z), .CLK(clk));
///   sub s1 (.i(a), .o(bus[0]));
///   assign bus[1] = b;
/// endmodule
/// module sub(input i, output o);
///   assign o = ~i;
/// endmodule
/// ```
const String _json = r'''
{"creator":"Yosys 0.69","modules":{"sub":{"attributes":{},"ports":{"i":{"direction":"input",
"bits":[2]},"o":{"direction":"output","bits":[3]}},"cells":{"$not$top.v:12$1":{"hide_name":1,
"type":"$not","parameters":{"A_SIGNED":"00000000000000000000000000000000",
"A_WIDTH":"00000000000000000000000000000001","Y_WIDTH":"00000000000000000000000000000001"},
"attributes":{},"port_directions":{"A":"input","Y":"output"},"connections":{"A":[2],
"Y":[3]}}},"netnames":{"$not$top.v:12$1_Y":{"hide_name":1,"bits":[3],"attributes":{}},
"i":{"hide_name":0,"bits":[2],"attributes":{}},"o":{"hide_name":0,"bits":[3],
"attributes":{}}}},"top":{"attributes":{"top":"00000000000000000000000000000001"},
"ports":{"a":{"direction":"input","bits":[2]},"b":{"direction":"input",
"bits":[3]},"clk":{"direction":"input","bits":[4]},"y":{"direction":"output",
"bits":[5]},"z":{"direction":"output","bits":[6,7]}},"cells":{"m1":{"hide_name":0,
"type":"MACRO","parameters":{},"attributes":{},"connections":{"CLK":[4],
"D":[8,3],"Q":[6,7]}},"s1":{"hide_name":0,"type":"sub","parameters":{},
"attributes":{},"port_directions":{"i":"input","o":"output"},"connections":{"i":[2],
"o":[8]}},"u1":{"hide_name":0,"type":"INV","parameters":{},"attributes":{},
"connections":{"A":[2],"VDD":["1"],"VSS":["0"],"Y":[9]}},"u2":{"hide_name":0,
"type":"NAND2","parameters":{},"attributes":{},"connections":{"A":[9],"B":[3],
"Y":[10]}},"u3":{"hide_name":0,"type":"DFF","parameters":{},"attributes":{},
"connections":{"$1":[4],"$2":[10],"$3":[5]}}},"netnames":{"a":{"hide_name":0,
"bits":[2],"attributes":{}},"b":{"hide_name":0,"bits":[3],"attributes":{}},
"bus":{"hide_name":0,"bits":[8,3],"attributes":{}},"clk":{"hide_name":0,
"bits":[4],"attributes":{}},"n1":{"hide_name":0,"bits":[9],"attributes":{}},
"n2":{"hide_name":0,"bits":[10],"attributes":{}},"y":{"hide_name":0,"bits":[5],
"attributes":{}},"z":{"hide_name":0,"bits":[6,7],"attributes":{}}}}}}
''';

/// The viewer's consumers on a netlist whose cells include types no module
/// defines, after [inferBlackBoxPorts]: the schematic graph, the layout
/// input and a native layout, the hierarchy, and search.
void main() {
  final inferred = inferBlackBoxPorts(
    const StreamingYosysJsonReader().parse(_json),
  );
  final model = inferred.model;
  final root = HierarchyNode.rootOf(model)!;

  test('every black-box pin has a direction', () {
    expect(inferred.report.types, <String>['DFF', 'INV', 'MACRO', 'NAND2']);
    final cells = model.modules['top']!.cells;
    expect(cells['m1']!.portDirections, <String, PortDirection>{
      'CLK': PortDirection.input,
      'D': PortDirection.input,
      'Q': PortDirection.output,
    });
    expect(cells['u2']!.portDirections['Y'], PortDirection.output);
    expect(cells['u3']!.portDirections[r'$2'], PortDirection.input);
  });

  test('the schematic graph wires black boxes output to input', () {
    final graph = const SchematicGraphBuilder().build(model, root);
    final byId = <String, SchematicCell>{
      for (final cell in graph.cells) cell.id: cell,
    };
    expect(byId.keys, containsAll(<String>['u1', 'u2', 'u3', 'm1', 's1']));
    final y = byId['u1']!.ports.singleWhere((port) => port.name == 'Y');
    expect(y.side, SchematicPortSide.east);
    final edge = graph.edges.singleWhere(
      (e) => e.sourcePortId == 'u1:Y' && e.targetPortId == 'u2:A',
    );
    expect(edge.netId, 9);
    expect(
      graph.edges.any(
        (e) => e.sourcePortId == 'u2:Y' && e.targetPortId == r'u3:$2',
      ),
      isTrue,
    );
  });

  test('the layout input places every black-box pin on a side', () {
    final input = buildElkInput(model.modules['top']!);
    final children = (input['children']! as List<Object?>)
        .cast<Map<String, Object?>>();
    final u1 = children.singleWhere((c) => c['id'] == 'u1');
    expect(u1['ports'], hasLength(4));
  });

  test('a native layout places the black boxes', () async {
    if (!requireElkFfiLibrary()) return;
    final service = ElkLayoutService(
      solverFactory: NativeElkSolver.open,
      assetLoader: (_) async => throw StateError('elkjs must not load'),
    );
    addTearDown(service.dispose);
    final layout = await service.layout(model.modules['top']!);
    for (final id in <String>['u1', 'u2', 'u3', 'm1']) {
      expect(layout.findNode(id), isNotNull, reason: id);
    }
  });

  test('a black box is a leaf in the hierarchy; a defined module is not', () {
    expect(root.childInstanceNames(model), <String>['s1']);
    expect(root.child(model, 'u1'), isNull);
    expect(root.child(model, 's1')?.moduleName, 'sub');
  });

  test('search finds a black-box instance as a cell', () {
    final results = const DesignSearchService().search(
      model: model,
      query: 'm1',
    );
    expect(
      results.where((r) => r.name == 'm1').map((r) => r.kind),
      <SearchResultKind>[SearchResultKind.cell],
    );
  });
}
