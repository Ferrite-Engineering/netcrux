// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Cell-library cells drawn as gate symbols: the schematic graph takes the
// symbol from the cell's function, both layout engines put the supply pins
// on the top and bottom faces, the pins the canvas draws sit where the
// layout put them, and the SVG export draws what the canvas draws.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/layout/netlist_layout.dart';
import 'package:netcrux/domain/models/netlist/hierarchy_node.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/schematic/cell_kind.dart';
import 'package:netcrux/domain/models/schematic/laid_out_graph.dart';
import 'package:netcrux/domain/models/schematic/liberty_cell_symbols.dart';
import 'package:netcrux/domain/models/schematic/schematic_graph.dart';
import 'package:netcrux/domain/models/schematic/symbol_shapes.dart';
import 'package:netcrux/services/export/scope_render.dart';
import 'package:netcrux/services/export/svg_exporter.dart';
import 'package:netcrux/services/layout/elk_layout_service.dart';
import 'package:netcrux/services/layout/flutter_js_host_vm.dart';
import 'package:netcrux/services/layout/native_elk_solver.dart';
import 'package:netcrux/services/liberty/liberty_cell_index.dart';
import 'package:netcrux/services/liberty/liberty_library.dart';
import 'package:netcrux/services/liberty/liberty_parser.dart';
import 'package:netcrux/services/schematic/schematic_graph_builder.dart';
import 'package:netcrux/services/schematic/schematic_scope_module.dart';

import '../../helpers/elk_ffi_library_gate.dart';

const String _pg = '''
    pg_pin (VGND) { pg_type : primary_ground ; }
    pg_pin (VNB) { pg_type : pwell ; }
    pg_pin (VPB) { pg_type : nwell ; }
    pg_pin (VPWR) { pg_type : primary_power ; }
''';

final LibertyLibrary _library = LibertyParser.parseString('''
library (cells_tt) {
  cell (NAND2) {
    area : 3.75 ;
$_pg
    pin (A) { direction : input ; }
    pin (B) { direction : input ; }
    pin (Y) { direction : output ; function : "!(A&B)" ; }
  }
  cell (DFF) {
    area : 20 ;
$_pg
    ff (IQ, IQN) { clocked_on : "CLK" ; next_state : "D" ; }
    pin (D) { direction : input ; }
    pin (CLK) { direction : input ; clock : true ; }
    pin (Q) { direction : output ; function : "IQ" ; }
  }
  cell (AOI21) {
    area : 5 ;
$_pg
    pin (A1) { direction : input ; }
    pin (A2) { direction : input ; }
    pin (B1) { direction : input ; }
    pin (Y) { direction : output ; function : "!((A1&A2)|B1)" ; }
  }
}
''', path: 'cells_tt.lib');

Map<String, Object?> _instance(
  String type,
  Map<String, String> directions,
  Map<String, List<Object>> connections,
) => <String, Object?>{
  'hide_name': 0,
  'type': type,
  'parameters': <String, Object?>{},
  'attributes': <String, Object?>{},
  'port_directions': directions,
  'connections': connections,
};

const Map<String, String> _supplyDirections = <String, String>{
  'VGND': 'inout',
  'VNB': 'inout',
  'VPB': 'inout',
  'VPWR': 'inout',
};

const Map<String, List<Object>> _supplyNets = <String, List<Object>>{
  'VGND': <Object>[20],
  'VNB': <Object>[20],
  'VPB': <Object>[21],
  'VPWR': <Object>[21],
};

/// A gate-level top as a post-route netlist has it: a NAND2 into a DFF and
/// an AOI21, every cell wired to power and ground, read with the library's
/// cells as black boxes.
NetlistModel _model() => NetlistModel.fromJson(<String, Object?>{
  'creator': 'test',
  'modules': <String, Object?>{
    'top': <String, Object?>{
      'attributes': const <String, Object?>{'top': '1'},
      'ports': const <String, Object?>{
        'a': <String, Object?>{
          'direction': 'input',
          'bits': <Object>[2],
        },
        'b': <String, Object?>{
          'direction': 'input',
          'bits': <Object>[3],
        },
        'clk': <String, Object?>{
          'direction': 'input',
          'bits': <Object>[4],
        },
        'q': <String, Object?>{
          'direction': 'output',
          'bits': <Object>[6],
        },
        'y': <String, Object?>{
          'direction': 'output',
          'bits': <Object>[7],
        },
      },
      'cells': <String, Object?>{
        'u_nand': _instance(
          'NAND2',
          <String, String>{
            'A': 'input',
            'B': 'input',
            'Y': 'output',
            ..._supplyDirections,
          },
          <String, List<Object>>{
            'A': <Object>[2],
            'B': <Object>[3],
            'Y': <Object>[5],
            ..._supplyNets,
          },
        ),
        'u_dff': _instance(
          'DFF',
          <String, String>{
            'D': 'input',
            'CLK': 'input',
            'Q': 'output',
            ..._supplyDirections,
          },
          <String, List<Object>>{
            'D': <Object>[5],
            'CLK': <Object>[4],
            'Q': <Object>[6],
            ..._supplyNets,
          },
        ),
        'u_aoi': _instance(
          'AOI21',
          <String, String>{
            'A1': 'input',
            'A2': 'input',
            'B1': 'input',
            'Y': 'output',
            ..._supplyDirections,
          },
          <String, List<Object>>{
            'A1': <Object>[2],
            'A2': <Object>[3],
            'B1': <Object>[5],
            'Y': <Object>[7],
            ..._supplyNets,
          },
        ),
      },
      'netnames': const <String, Object?>{},
    },
    for (final name in <String>['NAND2', 'DFF', 'AOI21'])
      name: <String, Object?>{
        'attributes': <String, Object?>{'blackbox': '1'},
        'ports': <String, Object?>{},
        'cells': <String, Object?>{},
        'netnames': <String, Object?>{},
      },
  },
});

LibertyCellSymbols _symbols(NetlistModel model) =>
    LibertyCellIndex(<LibertyLibrary>[_library]).symbolsFor(model);

Map<String, Object?> _node(Map<String, Object?> input, String id) =>
    (input['children']! as List<Object?>)
        .cast<Map<String, Object?>>()
        .firstWhere((n) => n['id'] == id);

Map<String, String> _sides(Map<String, Object?> node) => <String, String>{
  for (final p
      in (node['ports']! as List<Object?>).cast<Map<String, Object?>>())
    (p['id']! as String).split(':').last:
        (p['layoutOptions']! as Map<String, Object?>)['elk.port.side']!
            as String,
};

/// Checks that every supply pin of every library cell in [layout] sits on
/// the face its type names, and every other pin on the face its direction
/// names, with each pin touching its node's border.
void _expectFaces(NetlistLayout layout) {
  const power = <String>{'VPWR', 'VPB'};
  const ground = <String>{'VGND', 'VNB'};
  for (final id in <String>['u_nand', 'u_dff', 'u_aoi']) {
    final node = layout.findNode(id)!;
    final w = node.bounds.width;
    final h = node.bounds.height;
    for (final entry in node.ports.entries) {
      final pin = entry.key.split(':').last;
      final face = symbolPinFace(entry.value, w, h);
      final expected = power.contains(pin)
          ? SchematicPortSide.north
          : ground.contains(pin)
          ? SchematicPortSide.south
          : (pin == 'Y' || pin == 'Q')
          ? SchematicPortSide.east
          : SchematicPortSide.west;
      expect(face, expected, reason: entry.key);
    }
  }
}

void main() {
  final model = _model();
  final top = HierarchyNode.rootOf(model)!;
  final symbols = _symbols(model);

  group('SchematicGraphBuilder with cell libraries', () {
    final graph = SchematicGraphBuilder(liberty: symbols).build(model, top);
    SchematicCell cell(String id) => graph.cells.firstWhere((c) => c.id == id);

    test('each cell takes the symbol its function maps to', () {
      expect(cell('u_nand').kind, CellKind.nandGate);
      expect(cell('u_dff').kind, CellKind.flipFlop);
      expect(cell('u_aoi').kind, CellKind.generic);
    });

    test(
      'the clock pin is marked, and the supply pins face top and bottom',
      () {
        final dff = cell('u_dff');
        expect(dff.hasClockPins, isTrue);
        expect(
          <String>[
            for (final p in dff.ports)
              if (p.clock) p.name,
          ],
          <String>['CLK'],
        );
        final sides = <String, SchematicPortSide>{
          for (final p in cell('u_aoi').ports) p.name: p.side,
        };
        expect(sides['VPWR'], SchematicPortSide.north);
        expect(sides['VPB'], SchematicPortSide.north);
        expect(sides['VGND'], SchematicPortSide.south);
        expect(sides['VNB'], SchematicPortSide.south);
        expect(sides['A1'], SchematicPortSide.west);
        expect(sides['Y'], SchematicPortSide.east);
      },
    );

    test('without libraries the cells are boxes, as before', () {
      final plain = const SchematicGraphBuilder().build(model, top);
      for (final c in plain.cells) {
        expect(c.kind, CellKind.generic, reason: c.id);
        expect(c.hasClockPins, isFalse, reason: c.id);
      }
    });
  });

  group('buildElkInput with cell libraries', () {
    final module = schematicScopeModule(model, top.resolve(model)!);

    test('supply pins go north and south and the node keeps the height its '
        'side pins need', () {
      final input = buildElkInput(module, liberty: symbols);
      final nand = _node(input, 'u_nand');
      expect(_sides(nand), <String, String>{
        'A': 'WEST',
        'B': 'WEST',
        'Y': 'EAST',
        'VGND': 'SOUTH',
        'VNB': 'SOUTH',
        'VPB': 'NORTH',
        'VPWR': 'NORTH',
      });
      expect(nand['width'], 80);
      // Three side pins: 32 + 3 × 10, as for a NAND2 with no supply pins.
      expect(nand['height'], 62);
      // The box keeps its supply pins placed the same way.
      expect(_sides(_node(input, 'u_aoi'))['VPWR'], 'NORTH');
      expect(_node(input, 'u_aoi')['height'], 72);
    });

    test('without libraries the input is exactly what it was', () {
      final before = jsonEncode(buildElkInput(module));
      expect(
        jsonEncode(
          // Passing the default explicitly is the point.
          // ignore: avoid_redundant_argument_values
          buildElkInput(module, liberty: LibertyCellSymbols.none),
        ),
        before,
      );
      expect(_node(buildElkInput(module), 'u_nand')['height'], 32 + 7 * 10);
    });

    test('the native engine puts each pin on its face', () {
      if (!requireElkFfiLibrary()) return;
      final solver = NativeElkSolver.open();
      addTearDown(solver.dispose);
      final layout = NetlistLayout.fromJson(
        jsonDecode(
              solver.solve(jsonEncode(buildElkInput(module, liberty: symbols))),
            )
            as Map<String, Object?>,
      );
      _expectFaces(layout);
    });

    // elkjs runs under `flutter test` on JavaScriptCore only; elsewhere the
    // test is not registered rather than skipped (the CI skip guard).
    if (Platform.isMacOS) {
      test('elkjs puts each pin on the face the native engine does', () {
        if (!requireElkFfiLibrary()) return;
        final input = jsonEncode(buildElkInput(module, liberty: symbols));
        final ElkJsHost host;
        try {
          host = createDefaultElkJsHost();
          initElkRuntime(
            host,
            File('assets/elk/elk.bundled.js').readAsStringSync(),
          );
        } on Object catch (e) {
          markTestSkipped('no JavaScript engine here: $e');
          return;
        }
        addTearDown(host.dispose);
        final js = NetlistLayout.fromJson(
          jsonDecode(runElkLayoutOnHost(host, input)) as Map<String, Object?>,
        );
        _expectFaces(js);
      });
    }
  });

  group('the SVG export of a laid-out scope', () {
    test('draws the gate symbols, and the clock wedge at the clock pin', () {
      if (!requireElkFfiLibrary()) return;
      final solver = NativeElkSolver.open();
      addTearDown(solver.dispose);
      final laidOut = layOutScope(model, top, solver.solve, liberty: symbols);
      final svg = const SvgExporter().toSvg(laidOut);
      expect(svg, contains('data-kind="nandGate"'));
      expect(svg, contains('data-kind="flipFlop"'));
      expect(svg, contains('data-kind="generic"'));

      // The flip-flop's group holds its body and one wedge, centred on the
      // clock pin the layout placed.
      final dff = laidOut.layout.findNode('u_dff')!;
      final shape = <SymbolPrimitive>[
        ...symbolShapeFor(
          CellKind.flipFlop,
          dff.bounds.width,
          dff.bounds.height,
          clockAtPins: true,
        ),
        ...clockWedgeShapes(
          laidOut.graph.cells.firstWhere((c) => c.id == 'u_dff'),
          dff.bounds.width,
          dff.bounds.height,
          dff.ports,
        ),
      ];
      expect(shape, hasLength(2));
      final wedge = shape.last as SymbolPath;
      final tip = wedge.commands[1] as SymbolLineTo;
      final clk = dff.ports['u_dff:CLK']!;
      expect(tip.y, closeTo(clk.y + clk.height / 2, 1e-9));
      final expected = symbolShapeSvgElements(
        shape,
        body: SvgExportPalette.dark.body,
        stroke: SvgExportPalette.dark.stroke,
      ).map((e) => '    $e').join('\n');
      expect(svg, contains(expected));
    });

    test(
      'a cell drawn with a custom symbol gets no wedge from the library',
      () {
        if (!requireElkFfiLibrary()) return;
        final solver = NativeElkSolver.open();
        addTearDown(solver.dispose);
        final laidOut = layOutScope(model, top, solver.solve, liberty: symbols);
        final custom = LaidOutGraph(
          graph: laidOut.graph,
          layout: laidOut.layout,
          symbolCells: const <String, Set<String>>{'u_dff': <String>{}},
        );
        final group = RegExp(
          r'<g class="cell" data-kind="flipFlop" [^>]*>\n(.*?)\n  </g>',
          dotAll: true,
        ).firstMatch(const SvgExporter().toSvg(custom))!.group(1)!;
        expect(group, isNot(contains('<path')));
      },
    );
  });
}
